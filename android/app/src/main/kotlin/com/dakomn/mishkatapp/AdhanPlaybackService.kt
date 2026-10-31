package com.dakomn.mishkatapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/** Owns playback for its entire duration, including when Flutter is terminated. */
class AdhanPlaybackService : Service() {
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    private var current: JSONObject? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finishPlayback() }
    private val audio by lazy { getSystemService(AudioManager::class.java) }
    private val focusListener = AudioManager.OnAudioFocusChangeListener {
        if (it != AudioManager.AUDIOFOCUS_GAIN) finishPlayback()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            finishPlayback()
            return START_NOT_STICKY
        }
        val raw = intent?.getStringExtra(AdhanScheduler.EXTRA)
        if (raw == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        releasePlayer()
        val item = JSONObject(raw)
        current = item
        startForeground(item.getInt("id"), notification(this, item, playing = true))
        val notifications = getSystemService(NotificationManager::class.java)
        val channel = if (Build.VERSION.SDK_INT >= 26) notifications.getNotificationChannel(channelId(item)) else null
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled() ||
            (channel != null && channel.importance < NotificationManager.IMPORTANCE_DEFAULT) ||
            audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
            notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL ||
            audio.getStreamVolume(AudioManager.STREAM_MUSIC) == 0) {
            finishPlayback()
            return START_NOT_STICKY
        }
        try {
            val granted = if (Build.VERSION.SDK_INT >= 26) {
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(attributes()).setOnAudioFocusChangeListener(focusListener).build()
                focus = request
                audio.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            }
            if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                finishPlayback()
                return START_NOT_STICKY
            }
            val resource = soundResource(item.getString("soundName"))
            require(resource != 0)
            val media = MediaPlayer()
            player = media
            media.setAudioAttributes(attributes())
            media.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK)
            resources.openRawResourceFd(resource).use { fd ->
                media.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            }
            media.setOnPreparedListener { it.start() }
            media.setOnCompletionListener { finishPlayback() }
            media.setOnErrorListener { _, _, _ ->
                finishPlayback()
                showFallback(this, item)
                true
            }
            media.prepareAsync()
            handler.postDelayed(timeout, 10 * 60 * 1000L)
        } catch (_: Exception) {
            finishPlayback()
            showFallback(this, item)
        }
        return START_NOT_STICKY
    }

    private fun finishPlayback() {
        releasePlayer()
        stopForeground(STOP_FOREGROUND_DETACH)
        current?.let { item ->
            if (NotificationManagerCompat.from(this).areNotificationsEnabled()) {
                getSystemService(NotificationManager::class.java).notify(item.getInt("id"), notification(this, item, playing = false))
            }
        }
        current = null
        stopSelf()
    }

    private fun releasePlayer() {
        handler.removeCallbacks(timeout)
        player?.release()
        player = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { audio.abandonAudioFocusRequest(it) }
        else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(focusListener)
        }
        focus = null
    }

    override fun onDestroy() {
        releasePlayer()
        super.onDestroy()
    }

    companion object {
        private const val STOP = "com.dakomn.mishkatapp.STOP_ADHAN"
        // Explicit references also keep these resources in optimized release builds.
        fun soundResource(name: String): Int = when (name) {
            "adhan1" -> R.raw.adhan1
            "adhan2" -> R.raw.adhan2
            "adhan4" -> R.raw.adhan4
            "adhan1_short" -> R.raw.adhan1_short
            "adhan2_short" -> R.raw.adhan2_short
            "adhan4_short" -> R.raw.adhan4_short
            else -> 0
        }
        private fun attributes() = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        private fun channelId(item: JSONObject) = "mishkat_adhan_playback_v1_${item.optBoolean("vibrate", true)}"

        private fun notification(context: Context, item: JSONObject, playing: Boolean): Notification {
            val channelId = channelId(item)
            if (Build.VERSION.SDK_INT >= 26) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(channelId, "تشغيل الأذان", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "صوت الأذان من مشكاة مع زر لإيقافه"
                        setSound(null, null) // MediaPlayer owns the sound; never play it twice.
                        enableVibration(item.optBoolean("vibrate", true))
                    },
                )
            }
            val launch = Intent(context, MainActivity::class.java).apply {
                action = "SELECT_NOTIFICATION"
                putExtra("notificationId", item.getInt("id"))
                putExtra("payload", item.optString("payload", "prayer"))
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val tap = PendingIntent.getActivity(context, item.getInt("id"), launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_stat_mishkat)
                .setContentTitle(item.getString("title")).setContentText(item.getString("body"))
                .setCategory(NotificationCompat.CATEGORY_ALARM).setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(tap).setAutoCancel(!playing).setOngoing(playing).setOnlyAlertOnce(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setSound(null)
            if (item.optBoolean("vibrate", true)) builder.setVibrate(longArrayOf(0, 250, 150, 250))
            if (playing) {
                val stop = PendingIntent.getService(context, 0, Intent(context, AdhanPlaybackService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE)
                builder.addAction(0, "إيقاف الأذان", stop)
                builder.setDeleteIntent(stop)
            }
            return builder.build()
        }

        fun showFallback(context: Context, item: JSONObject) {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
            val name = item.getString("soundName").removeSuffix("_short") + "_short"
            val sound = Uri.parse("android.resource://${context.packageName}/${soundResource(name)}")
            val id = "mishkat_adhan_fallback_v1_${name}_${item.optBoolean("vibrate", true)}"
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel(id, "تنبيه الأذان المختصر", NotificationManager.IMPORTANCE_HIGH).apply {
                    setSound(sound, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).build())
                    enableVibration(item.optBoolean("vibrate", true))
                },
            )
            manager.notify(item.getInt("id"), NotificationCompat.Builder(context, id)
                .setSmallIcon(R.drawable.ic_stat_mishkat).setContentTitle(item.getString("title"))
                .setContentText(item.getString("body")).setSound(sound).setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH).build())
        }
    }
}
