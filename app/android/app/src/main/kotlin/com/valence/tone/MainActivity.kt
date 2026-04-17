package com.valence.tone

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
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
    private var testMediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    // ── Alert sequence engine ──
    private var soundPool: SoundPool? = null
    private var thrumSoundId = 0
    private var thrumLoaded = false
    private var alertHandler: Handler? = null
    private var alertLooping = false

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
        initTts()
        initSoundPool()
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
            for (key in listOf("incidentId", "incidentType", "address", "units", "unitCodes", "natureOfCall", "dispatchTime")) {
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
                    "vibrate" -> {
                        // Fire a one-shot vibration pattern: [delay, on, off, on, off, ...]
                        val pattern = call.argument<List<Int>>("pattern")
                        if (pattern != null) {
                            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                val mgr = getSystemService(VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                                mgr.defaultVibrator
                            } else {
                                @Suppress("DEPRECATION")
                                getSystemService(VIBRATOR_SERVICE) as android.os.Vibrator
                            }
                            val arr = pattern.map { it.toLong() }.toLongArray()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(android.os.VibrationEffect.createWaveform(arr, -1)) // -1 = no repeat
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(arr, -1)
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "playSound" -> {
                        val sound = call.argument<String>("sound")
                        val volume = call.argument<Double>("volume") ?: 1.0
                        if (sound != null) {
                            try {
                                // Look up resource in res/raw/ (e.g. "dispatch_tone" → R.raw.dispatch_tone)
                                val resId = resources.getIdentifier(sound, "raw", packageName)
                                if (resId != 0) {
                                    // Release any previous player
                                    testMediaPlayer?.release()
                                    val mp = MediaPlayer.create(this, resId)
                                    val vol = volume.toFloat().coerceIn(0f, 1f)
                                    mp?.setVolume(vol, vol)
                                    mp?.setOnCompletionListener { it.release(); testMediaPlayer = null }
                                    mp?.start()
                                    testMediaPlayer = mp
                                    result.success(true)
                                } else {
                                    result.success(false)
                                }
                            } catch (e: Exception) {
                                result.error("PLAY_ERROR", e.message, null)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "stopSound" -> {
                        testMediaPlayer?.let {
                            it.stop()
                            it.release()
                        }
                        testMediaPlayer = null
                        result.success(true)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text")
                        val pitch = call.argument<Double>("pitch")?.toFloat() ?: 0.95f
                        val rate = call.argument<Double>("rate")?.toFloat() ?: 0.9f
                        if (text != null && ttsReady) {
                            tts?.setPitch(pitch)
                            tts?.setSpeechRate(rate)
                            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "tone_alert")
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "stopSpeaking" -> {
                        tts?.stop()
                        result.success(true)
                    }
                    "isTtsReady" -> {
                        result.success(ttsReady)
                    }
                    "startAlertSequence" -> {
                        val speechText = call.argument<String>("speechText") ?: "Dispatch received"
                        startAlertSequence(speechText)
                        result.success(true)
                    }
                    "stopAlertSequence" -> {
                        stopAlertSequence()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ────────────────────────────────────────────────────────────────────
    // TTS
    // ────────────────────────────────────────────────────────────────────

    private fun initTts() {
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val langResult = tts?.setLanguage(java.util.Locale.US)
                Log.d("Tone", "TTS language set: $langResult")
                tts?.setPitch(0.95f)
                tts?.setSpeechRate(0.9f)

                // Route TTS through the ALARM stream so it's audible even if media is muted
                val ttsAudio = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                tts?.setAudioAttributes(ttsAudio)

                ttsReady = true
                Log.d("Tone", "TTS ready (alarm stream)")
            } else {
                Log.w("Tone", "TTS init failed: $status")
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // SoundPool (low-latency thrum playback)
    // ────────────────────────────────────────────────────────────────────

    private fun initSoundPool() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        soundPool = SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(attrs)
            .build()
        soundPool?.setOnLoadCompleteListener { _, _, status ->
            thrumLoaded = (status == 0)
            Log.d("Tone", "Thrum loaded: $thrumLoaded")
        }
        thrumSoundId = soundPool?.load(this, R.raw.dispatch_thrum, 1) ?: 0
    }

    // ────────────────────────────────────────────────────────────────────
    // Alert sequence: "Dispatch received" → [thrum×3] ─pause─ [thrum×3] → loop
    // Each thrum: SoundPool play + amplitude-ramped vibration
    // ────────────────────────────────────────────────────────────────────

    private val THRUM_MS = 800L         // duration of one thrum WAV
    private val GAP_IN_GROUP = 250L     // short gap within a group of 3
    private val THRUMS_PER_GROUP = 3
    private val PAUSE_BETWEEN_GROUPS = 1000L // breathing room between groups

    // Vibration ramp for one thrum: 16 × 50ms = 800ms
    private val VIB_DELAY = 300L  // vibration starts 300ms after audio
    // 12 × 50ms = 600ms ramp from soft to full (covers audio's audible portion)
    private val VIB_TIMINGS = longArrayOf(50,50,50,50,50,50,50,50,50,50,50,50)
    private val VIB_AMPLITUDES = intArrayOf(20,50,90,130,165,195,220,238,248,253,255,255)

    private fun startAlertSequence(speechText: String = "Dispatch received") {
        if (alertLooping) return
        alertLooping = true
        alertHandler = Handler(Looper.getMainLooper())

        // Speech once as primer, then thrums only
        Log.d("Tone", "startAlertSequence: ttsReady=$ttsReady, speech='$speechText'")
        if (ttsReady) {
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    Log.d("Tone", "TTS onStart: $utteranceId")
                }
                override fun onDone(utteranceId: String?) {
                    Log.d("Tone", "TTS onDone: $utteranceId")
                    alertHandler?.postDelayed({ playThrumPattern() }, 400)
                }
                @Deprecated("Deprecated in API")
                override fun onError(utteranceId: String?) {
                    Log.w("Tone", "TTS onError: $utteranceId")
                    alertHandler?.postDelayed({ playThrumPattern() }, 400)
                }
            })
            val speakResult = tts?.speak(speechText, TextToSpeech.QUEUE_FLUSH, null, "alert_cycle")
            Log.d("Tone", "TTS speak result: $speakResult")
        } else {
            Log.w("Tone", "TTS not ready, skipping speech")
            playThrumPattern()
        }
    }

    private fun playThrumPattern() {
        if (!alertLooping || !thrumLoaded) return

        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = getSystemService(VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
            mgr.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as android.os.Vibrator
        }

        // Schedule 1 group of 3 thrums
        var offset = 0L
        for (t in 0 until THRUMS_PER_GROUP) {
            val thisOffset = offset
            // Audio starts immediately
            alertHandler?.postDelayed({
                if (!alertLooping) return@postDelayed
                soundPool?.play(thrumSoundId, 1.0f, 1.0f, 1, 0, 1.0f)
            }, thisOffset)
            // Vibration starts VIB_DELAY ms later
            alertHandler?.postDelayed({
                if (!alertLooping) return@postDelayed
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(
                        android.os.VibrationEffect.createWaveform(VIB_TIMINGS, VIB_AMPLITUDES, -1)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(THRUM_MS)
                }
            }, thisOffset + VIB_DELAY)
            offset += THRUM_MS + GAP_IN_GROUP
        }

        // After group finishes, pause then loop
        alertHandler?.postDelayed({
            if (alertLooping) playThrumPattern()
        }, offset + PAUSE_BETWEEN_GROUPS)
    }

    private fun stopAlertSequence() {
        alertLooping = false
        alertHandler?.removeCallbacksAndMessages(null)
        alertHandler = null
        tts?.stop()
        // Cancel vibration
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = getSystemService(VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
            mgr.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as android.os.Vibrator
        }
        vibrator.cancel()
    }

    override fun onDestroy() {
        stopAlertSequence()
        tts?.shutdown()
        tts = null
        soundPool?.release()
        soundPool = null
        super.onDestroy()
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

        // All known agencies
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
                ch.id,
                ch.name,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = ch.desc
                enableVibration(true)
                vibrationPattern = ch.vibration
                
                // Set notification sound with audio attributes
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                setSound(soundUri, audioAttributes)
                
                if (ch.bypassDnd) setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }

        // Clean up legacy channels
        for (old in listOf("dispatch", "dispatch_fire", "dispatch_ems", "priority_messages", "priority", "messages")) {
            manager.deleteNotificationChannel(old)
        }
    }
}
