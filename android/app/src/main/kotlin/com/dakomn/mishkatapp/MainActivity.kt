package com.dakomn.mishkatapp

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var adhanChannel: MethodChannel? = null
    private var speechModels: ArabicSpeechModelManager? = null
    private var speechSettingsChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
        adhanChannel?.setMethodCallHandler(null)
        adhanChannel = null
        speechSettingsChannel?.setMethodCallHandler(null)
        speechSettingsChannel = null
        speechModels?.dispose()
        speechModels = null
        super.cleanUpFlutterEngine(flutterEngine)
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
