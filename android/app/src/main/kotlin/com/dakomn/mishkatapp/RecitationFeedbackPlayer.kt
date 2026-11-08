package com.dakomn.mishkatapp

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Short, original, non-verbal foreground cues. This player never owns audio
 * focus, changes the device volume/routing, or touches the recitation recorder.
 * All mutations and SoundPool completion handling run on the main thread.
 */
internal class RecitationFeedbackPlayer(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(
        messenger,
        "com.dakomn.mishkatapp/recitation_feedback",
    )
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val notifications =
        activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val names = listOf("ready", "mistake", "corrected", "paused", "complete")
    private val soundIds = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val pending = mutableListOf<MethodChannel.Result>()
    // A page replaced by another owner can never reacquire the player from a
    // delayed prepare continuation or dispose resources belonging to its heir.
    private val retiredOwners = mutableSetOf<String>()
    private var ownerId: String? = null
    private var pool: SoundPool? = null
    private var streamId = 0
    private var generation = 0
    private var foreground = false
    private var armed = false
    private var closed = false

    private val ready: Boolean
        get() = soundIds.size == names.size && loaded.size == names.size

    init {
        channel.setMethodCallHandler { call, result ->
            val caller = call.argument<String>("ownerId")
            if (closed || caller.isNullOrBlank()) {
                if (call.method == "play") result.success(false)
                else result.error("feedback_unavailable", "Feedback owner unavailable", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "prepare" -> prepare(caller, result)
                "play" -> result.success(play(caller, call.argument<String>("cue")))
                "stop" -> {
                    if (caller == ownerId) stopOwner()
                    result.success(null)
                }
                "dispose" -> {
                    retiredOwners.add(caller)
                    if (caller == ownerId) {
                        release()
                        ownerId = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepare(caller: String, result: MethodChannel.Result) {
        if (!foreground || caller in retiredOwners) {
            result.error("feedback_inactive", "Feedback owner is inactive", null)
            return
        }
        if (ownerId != caller) {
            ownerId?.let(retiredOwners::add)
            release()
            ownerId = caller
        }
        armed = true
        if (ready) {
            result.success(null)
            return
        }
        pending.add(result)
        if (pool != null) return
        val loadGeneration = generation
        try {
            val player = SoundPool.Builder()
                .setMaxStreams(1)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .build()
            pool = player
            player.setOnLoadCompleteListener { completedPool, soundId, status ->
                activity.runOnUiThread {
                    if (closed || pool !== completedPool || generation != loadGeneration) {
                        return@runOnUiThread
                    }
                    if (status != 0) {
                        failPreparation("Cannot load feedback cue")
                        return@runOnUiThread
                    }
                    loaded.add(soundId)
                    if (ready) {
                        val callbacks = pending.toList()
                        pending.clear()
                        callbacks.forEach { it.success(null) }
                    }
                }
            }
            for (name in names) {
                val key = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/audio/recitation_$name.wav")
                val soundId = activity.assets.openFd(key).use { player.load(it, 1) }
                check(soundId != 0) { "Cannot load feedback asset" }
                soundIds[name] = soundId
            }
        } catch (_: Exception) {
            failPreparation("Cannot prepare feedback cues")
        }
    }

    private fun play(caller: String, cue: String?): Boolean {
        if (closed || !foreground || !armed || caller != ownerId || !ready) return false
        val soundId = soundIds[cue] ?: return false
        return try {
            // Do not bypass silent/vibrate mode, zero media volume, or DND.
            // Reading these states requires no notification-policy permission.
            if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
                audio.getStreamVolume(AudioManager.STREAM_MUSIC) == 0 ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                    notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL)
            ) {
                return false
            }
            val player = pool ?: return false
            if (streamId != 0) player.stop(streamId)
            streamId = player.play(soundId, 0.6f, 0.6f, 1, 0, 1f)
            streamId != 0
        } catch (_: Exception) {
            // Optional effects cannot fail or interrupt the recognition path.
            false
        }
    }

    private fun failPreparation(message: String) {
        val callbacks = pending.toList()
        pending.clear()
        release()
        callbacks.forEach { it.error("feedback_prepare_failed", message, null) }
    }

    private fun stopOwner() {
        armed = false
        // A stop during loading invalidates every callback from that load. No
        // sound is ever queued by prepare, and play must be explicitly retried.
        if (!ready) {
            release()
        } else {
            pool?.let { if (streamId != 0) it.stop(streamId) }
            streamId = 0
        }
    }

    private fun release() {
        generation++
        armed = false
        streamId = 0
        pool?.release()
        pool = null
        soundIds.clear()
        loaded.clear()
        val callbacks = pending.toList()
        pending.clear()
        callbacks.forEach {
            it.error("feedback_cancelled", "Feedback preparation cancelled", null)
        }
    }

    fun onHostStart() {
        foreground = true
    }

    fun onHostStop() {
        foreground = false
        stopOwner()
    }

    fun dispose() {
        closed = true
        foreground = false
        channel.setMethodCallHandler(null)
        release()
        ownerId = null
        retiredOwners.clear()
    }
}
