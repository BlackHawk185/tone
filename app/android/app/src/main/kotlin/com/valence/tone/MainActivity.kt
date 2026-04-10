package com.valence.tone

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** DispatchMessagingService checks this to avoid duplicate alerts in foreground. */
        var isInForeground = false
    }

    private val CHANNEL = "com.valence.tone/settings"
    private var pendingDispatchData: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow this activity to appear on the lock screen and wake the display
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        createNotificationChannels()
        handleDispatchIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
    }

    override fun onPause() {
        super.onPause()
        isInForeground = false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDispatchIntent(intent)
    }

    /**
     * If the activity was launched by DispatchMessagingService with dispatch
     * data, stash it so Flutter can pick it up via the platform channel.
     */
    private fun handleDispatchIntent(intent: Intent?) {
        if (intent?.action == "com.valence.tone.DISPATCH_ALERT") {
            val data = mutableMapOf<String, String>()
            for (key in listOf("incidentId", "incidentType", "address", "units", "natureOfCall", "dispatchTime")) {
                intent.getStringExtra(key)?.let { data[key] = it }
            }
            if (data.containsKey("incidentId")) {
                pendingDispatchData = data
                // Also send to Flutter immediately if engine is running
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onDispatchAlert", data)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openChannelSettings" -> {
                        val channelId = call.argument<String>("channelId")
                        if (channelId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            // Fallback: open app notification settings
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    }
                    "openDndSettings" -> {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        startActivity(intent)
                        result.success(null)
                    }
                    "isDndAccessGranted" -> {
                        val manager = getSystemService(NotificationManager::class.java)
                        result.success(manager?.isNotificationPolicyAccessGranted == true)
                    }
                    "canDrawOverlays" -> {
                        result.success(
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                                Settings.canDrawOverlays(this)
                            else true
                        )
                    }
                    "openOverlaySettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val mgr = getSystemService(NotificationManager::class.java)
                            result.success(mgr?.canUseFullScreenIntent() == true)
                        } else {
                            result.success(true) // Pre-34: always allowed
                        }
                    }
                    "openFullScreenIntentSettings" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "getPendingDispatch" -> {
                        result.success(pendingDispatchData)
                        pendingDispatchData = null
                    }
                    "isChannelEnabled" -> {
                        val channelId = call.argument<String>("channelId")
                        if (channelId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val mgr = getSystemService(NotificationManager::class.java)
                            val ch = mgr?.getNotificationChannel(channelId)
                            result.success(ch != null && ch.importance != NotificationManager.IMPORTANCE_NONE)
                        } else {
                            result.success(true) // Pre-O: channels don't exist, always enabled
                        }
                    }
                    "sendTestDispatch" -> {
                        val testIntent = Intent(this, MainActivity::class.java).apply {
                            action = "com.valence.tone.DISPATCH_ALERT"
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra("incidentId", "debug-test-${System.currentTimeMillis()}")
                            putExtra("incidentType", "FIRE")
                            putExtra("channel", "debug")
                            putExtra("address", "123 Test St - DEBUG")
                            putExtra("units", "[\"E1\",\"T1\"]")
                            putExtra("natureOfCall", "Debug test dispatch")
                            putExtra("dispatchTime", "")
                        }
                        // Use overlay + wake lock (same as real dispatch path)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && Settings.canDrawOverlays(this)) {
                            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                            if (!pm.isInteractive) {
                                val wakeLock = pm.newWakeLock(
                                    android.os.PowerManager.FULL_WAKE_LOCK or
                                    android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP or
                                    android.os.PowerManager.ON_AFTER_RELEASE,
                                    "tone:debug_wake"
                                )
                                wakeLock.acquire(10_000L)
                            }
                            startActivity(testIntent)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            // Fallback: fullScreenIntent notification
                            val pendingIntent = android.app.PendingIntent.getActivity(
                                this, 0, testIntent,
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                            )
                            val notification = androidx.core.app.NotificationCompat.Builder(this, "debug")
                                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                                .setContentTitle("DEBUG: FIRE")
                                .setContentText("123 Test St - DEBUG")
                                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_MAX)
                                .setCategory(androidx.core.app.NotificationCompat.CATEGORY_ALARM)
                                .setVisibility(androidx.core.app.NotificationCompat.VISIBILITY_PUBLIC)
                                .setFullScreenIntent(pendingIntent, true)
                                .setAutoCancel(true)
                                .build()
                            val mgr = getSystemService(NotificationManager::class.java)
                            mgr?.notify(9998, notification)
                        }
                        result.success(true)
                    }
                    "cancelVibration" -> {
                        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val mgr = getSystemService(VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                            mgr.defaultVibrator
                        } else {
                            @Suppress("DEPRECATION")
                            getSystemService(VIBRATOR_SERVICE) as android.os.Vibrator
                        }
                        vibrator.cancel()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Per-type notification channels so users can control each category
     * independently via Android Settings.  DND bypass enabled on dispatch
     * channels so tones always come through.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return

        // Vibration patterns: [delay, vibrate, pause, vibrate, ...] in ms
        val urgentVibration = longArrayOf(0, 400, 200, 400, 200, 800) // strong pulses
        val normalVibration = longArrayOf(0, 250, 150, 250)           // short double-tap

        data class Ch(val id: String, val name: String, val desc: String, val bypassDnd: Boolean, val vibration: LongArray)

        val channels = listOf(
            Ch("dispatch_fire", "Fire Dispatch", "Fire dispatch alerts", true, urgentVibration),
            Ch("dispatch_ems", "EMS Dispatch", "EMS dispatch alerts", true, urgentVibration),
            Ch("priority_messages", "Priority Traffic", "Priority traffic messages", true, urgentVibration),
            Ch("messages", "Messages", "General department messages", false, normalVibration),
            Ch("debug", "Debug Test", "Debug channel for testing dispatch alerts", false, normalVibration),
        )

        for (ch in channels) {
            val channel = NotificationChannel(
                ch.id,
                ch.name,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = ch.desc
                enableVibration(true)
                vibrationPattern = ch.vibration
                if (ch.bypassDnd) setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }

        // Clean up the old single "dispatch" channel if it exists
        manager.deleteNotificationChannel("dispatch")
    }
}
