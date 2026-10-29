package com.dakomn.mishkatapp

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dakomn.mishkatapp/speech_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openVoiceInputSettings" -> result.success(openVoiceInputSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun openVoiceInputSettings(): Boolean {
        val voiceSettings = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)
        if (voiceSettings.resolveActivity(packageManager) != null) {
            return try {
                startActivity(voiceSettings)
                true
            } catch (_: ActivityNotFoundException) {
                openApplicationSettings()
            }
        }
        return openApplicationSettings()
    }

    private fun openApplicationSettings(): Boolean {
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
