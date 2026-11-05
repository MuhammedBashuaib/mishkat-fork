package com.dakomn.mishkatapp

import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.AudioAttributes
import android.media.SoundPool
import android.net.Uri
import android.provider.Settings
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var tasbihSound: TasbihSound? = null
    private var adhanChannel: MethodChannel? = null
    private var speechModels: ArabicSpeechModelManager? = null
    private var speechSettingsChannel: MethodChannel? = null
    private var offlineRecitation: OfflineRecitationPlugin? = null
    private var readerWindowChannel: MethodChannel? = null
    private var readerFullscreen = false

    private fun applyReaderWindow() {
        WindowInsetsControllerCompat(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (readerFullscreen) {
                hide(WindowInsetsCompat.Type.systemBars())
            } else {
                show(WindowInsetsCompat.Type.systemBars())
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && readerFullscreen) applyReaderWindow()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        readerWindowChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dakomn.mishkatapp/reader_window",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setFullscreen" -> {
                        readerFullscreen = call.arguments == true
                        applyReaderWindow()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        offlineRecitation?.dispose()
        offlineRecitation = OfflineRecitationPlugin(this, flutterEngine.dartExecutor.binaryMessenger)

        adhanChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.dakomn.mishkatapp/adhan").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "replace" -> {
                            @Suppress("UNCHECKED_CAST")
                            AdhanScheduler.replace(this, call.arguments as List<Map<*, *>>)
                            result.success(null)
                        }
                        "cancelAll" -> { AdhanScheduler.cancel(this); result.success(null) }
                        "stop" -> { stopService(Intent(this, AdhanPlaybackService::class.java)); result.success(null) }
                        "play" -> {
                            AdhanScheduler.play(this, org.json.JSONObject(call.arguments as Map<*, *>))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("adhan_error", error.message, null)
                }
            }
        }

        tasbihSound?.dispose()
        tasbihSound = TasbihSound(this, flutterEngine)

        speechModels?.dispose()
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dakomn.mishkatapp/speech_settings",
        )
        val models = ArabicSpeechModelManager(this, channel)
        speechModels = models
        speechSettingsChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openVoiceInputSettings" -> result.success(openVoiceInputSettings())
                "getArabicModelStatus" -> models.getStatus { result.success(it) }
                "downloadArabicModel" -> models.download { result.success(it) }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        readerWindowChannel?.setMethodCallHandler(null)
        readerWindowChannel = null
        if (readerFullscreen) {
            readerFullscreen = false
            applyReaderWindow()
        }
        offlineRecitation?.dispose()
        offlineRecitation = null
        tasbihSound?.dispose()
        tasbihSound = null
        adhanChannel?.setMethodCallHandler(null)
        adhanChannel = null
        speechSettingsChannel?.setMethodCallHandler(null)
        speechSettingsChannel = null
        speechModels?.dispose()
        speechModels = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        offlineRecitation?.onHostStop()
        super.onStop()
    }

    private fun openVoiceInputSettings(): Boolean {
        // Android package visibility can hide a resolvable Settings activity
        // from resolveActivity(). Launch directly and handle OEM differences.
        for (action in listOf(
            Settings.ACTION_VOICE_INPUT_SETTINGS,
            Settings.ACTION_INPUT_METHOD_SETTINGS,
        )) {
            if (startSettingsActivity(Intent(action))) return true
        }
        return openApplicationSettings()
    }

    private fun openApplicationSettings(): Boolean {
        return startSettingsActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun startSettingsActivity(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}

/** Native effects do not allocate a second just_audio_background player. */
private class TasbihSound(
    private val activity: MainActivity,
    private val engine: FlutterEngine,
) {
    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "com.dakomn.mishkatapp/tasbih_sound",
    )
    private var pool: SoundPool? = null
    private var soundId = 0
    private var ready = false
    private val pending = mutableListOf<MethodChannel.Result>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(result)
                "play" -> {
                    val stream = if (ready) pool?.play(soundId, 1f, 1f, 1, 0, 1f) else 0
                    if (stream == null || stream == 0) {
                        result.error("tasbih_sound_error", "Cannot start chime", null)
                    } else {
                        result.success(null)
                    }
                }
                "dispose" -> { release(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepare(result: MethodChannel.Result) {
        if (ready) { result.success(null); return }
        pending.add(result)
        if (pool != null) return
        try {
            val player = SoundPool.Builder()
                .setMaxStreams(1)
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                .build()
            pool = player
            player.setOnLoadCompleteListener { loadedPool, _, status ->
                activity.runOnUiThread {
                    if (pool !== loadedPool) return@runOnUiThread
                    ready = status == 0
                    val callbacks = pending.toList()
                    pending.clear()
                    if (!ready) release()
                    callbacks.forEach {
                        if (status == 0) it.success(null)
                        else it.error("tasbih_sound_error", "Cannot load chime", null)
                    }
                }
            }
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/audio/tasbih_complete.wav")
            activity.assets.openFd(key).use { soundId = player.load(it, 1) }
            if (soundId == 0) throw IllegalStateException("Cannot load chime asset")
        } catch (error: Exception) {
            val callbacks = pending.toList()
            pending.clear()
            release()
            callbacks.forEach { it.error("tasbih_sound_error", error.message, null) }
        }
    }

    private fun release() {
        ready = false
        pool?.release()
        pool = null
        soundId = 0
        val callbacks = pending.toList()
        pending.clear()
        callbacks.forEach { it.error("tasbih_sound_disposed", "Sound player disposed", null) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        release()
    }
}
