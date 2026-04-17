package com.valence.tone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Custom FirebaseMessagingService that wakes the device and brings the app
 * to the foreground when a dispatch-type FCM data message arrives.
 *
 * Respects per-channel OS toggles: if the user has disabled the channel
 * for this message type, the alert is silently dropped.
 *
 * Uses two strategies depending on screen state:
 * - Screen ON + unlocked: direct startActivity() via SYSTEM_ALERT_WINDOW
 * - Screen OFF / locked: high-priority notification with fullScreenIntent
 */
class DispatchMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "DispatchMsgSvc"
        private const val DISPATCH_NOTIFICATION_ID = 9999
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(TAG, "FCM message received: ${message.data}")

        // Ensure channels exist (MainActivity may not have run yet on cold wake)
        ensureChannelsExist()

        val incidentId = message.data["incidentId"] ?: return
        val incidentType = message.data["incidentType"] ?: return
        val channelId = message.data["channel"] ?: "dispatch_PBAMB"

        // Don't hijack screen for plain messages
        if (incidentType == "MESSAGE") return

        // Check if the OS channel is enabled — single source of truth
        if (!isChannelEnabled(channelId)) {
            Log.d(TAG, "Channel '$channelId' disabled by user, dropping alert")
            return
        }

        // App is in foreground — Flutter's onMessage handler will show the alert
        if (MainActivity.isInForeground) {
            Log.d(TAG, "App in foreground, skipping native launch (Flutter handles it)")
            return
        }

        Log.d(TAG, "Bringing app to foreground for dispatch: $incidentId")

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.valence.tone.DISPATCH_ALERT"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("incidentId", incidentId)
            putExtra("incidentType", incidentType)
            putExtra("address", message.data["address"] ?: "")
            putExtra("units", message.data["units"] ?: "[]")
            putExtra("unitCodes", message.data["unitCodes"] ?: "[]")
            putExtra("natureOfCall", message.data["natureOfCall"] ?: "")
            putExtra("dispatchTime", message.data["dispatchTime"] ?: "")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && Settings.canDrawOverlays(this)) {
            // We have overlay permission — wake screen + launch directly
            // This is the most reliable path on Samsung/Android 14+
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                val wakeLock = pm.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                    "tone:dispatch_wake"
                )
                wakeLock.acquire(10_000L)
            }
            startActivity(launchIntent)
            startDispatchVibration()
        } else {
            // No overlay permission — fall back to fullScreenIntent notification
            showFullScreenNotification(launchIntent, channelId, incidentType, message.data["address"] ?: "")
            startDispatchVibration()
        }
    }

    private fun showFullScreenNotification(launchIntent: Intent, channelId: String, incidentType: String, address: String) {
        // Acquire a wake lock to ensure the screen turns on
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or
            PowerManager.ACQUIRE_CAUSES_WAKEUP or
            PowerManager.ON_AFTER_RELEASE,
            "tone:dispatch_wake"
        )
        wakeLock.acquire(10_000L) // 10 seconds max

        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("TONE: $incidentType")
            .setContentText(address)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(DISPATCH_NOTIFICATION_ID, notification)

        Log.d(TAG, "Posted fullScreenIntent notification to wake device")
    }

    /**
     * Start a repeating vibration pattern that continues until cancelled.
     * Pattern: buzz-pause-buzz-pause-buzz, repeating from index 0.
     */
    private fun startDispatchVibration() {
        val pattern = longArrayOf(0, 500, 300, 500, 300, 500, 1000) // buzz buzz buzz, 1s gap, repeat
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            mgr.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0)) // 0 = repeat from start
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
        Log.d(TAG, "Started repeating dispatch vibration")
    }

    /**
     * Check whether the given notification channel is enabled by the user.
     * Returns true on pre-O devices (no channels) or if importance > NONE.
     */
    private fun isChannelEnabled(channelId: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel(channelId) ?: return true
        return channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    /**
     * Ensure notification channels exist. Called before every message because
     * this service can run before MainActivity.onCreate() on a cold wake.
     * createNotificationChannel is a no-op if the channel already exists,
     * and never overrides user-modified settings.
     */
    private fun ensureChannelsExist() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        val urgentVibration = longArrayOf(0, 400, 200, 400, 200, 800)
        val normalVibration = longArrayOf(0, 250, 150, 250)

        data class Ch(val id: String, val name: String, val desc: String, val bypassDnd: Boolean, val vibration: LongArray)

        val agencies = mapOf(
            "PBAMB" to "PB EMS",
            "21523" to "LCFD5",
        )

        val channels = mutableListOf<Ch>()
        for ((code, label) in agencies) {
            channels.add(Ch("dispatch_$code", "Dispatch \u2014 $label", "Dispatch alerts for $label", true, urgentVibration))
            channels.add(Ch("priority_$code", "Priority \u2014 $label", "Priority traffic for $label", true, urgentVibration))
            channels.add(Ch("messages_$code", "Messages \u2014 $label", "Messages for $label", false, normalVibration))
        }

        for (ch in channels) {
            val channel = NotificationChannel(
                ch.id, ch.name, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = ch.desc
                enableVibration(true)
                vibrationPattern = ch.vibration
                if (ch.bypassDnd) setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "FCM token refreshed: $token")
    }
}
