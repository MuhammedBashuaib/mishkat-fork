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
