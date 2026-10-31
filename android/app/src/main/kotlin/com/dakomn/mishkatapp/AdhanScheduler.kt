package com.dakomn.mishkatapp

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/** Persists the audible prayer calendar independently of the Flutter engine. */
object AdhanScheduler {
    private const val STORE = "mishkat_adhan_calendar"
    private const val KEY = "alarms"
    const val EXTRA = "adhan"
    private fun preferences(context: Context) = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(AlarmManager::class.java)
    fun canScheduleExact(context: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || manager(context).canScheduleExactAlarms()

    private fun read(context: Context): List<JSONObject> {
        val array = JSONArray(preferences(context).getString(KEY, "[]"))
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    private fun pending(context: Context, item: JSONObject): PendingIntent = PendingIntent.getBroadcast(
        context, item.getInt("id"),
        Intent(context, AdhanAlarmReceiver::class.java).putExtra(EXTRA, item.toString()),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun replace(context: Context, values: List<Map<*, *>>) {
        val items = values.map { JSONObject(it) }
        // Validate before replacing a working calendar.
        items.forEach { require(AdhanPlaybackService.soundResource(it.getString("soundName")) != 0) }
        read(context).forEach { manager(context).cancel(pending(context, it)) }
        check(preferences(context).edit().putString(KEY, JSONArray(items).toString()).commit())
        restore(context)
    }

    fun cancel(context: Context) {
        replace(context, emptyList())
        context.stopService(Intent(context, AdhanPlaybackService::class.java))
    }

    fun restore(context: Context) {
        val now = System.currentTimeMillis()
        read(context).filter { it.getLong("at") > now }.forEach { item ->
            val intent = pending(context, item)
            if (canScheduleExact(context)) {
                try {
                    manager(context).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.getLong("at"), intent)
                } catch (_: SecurityException) {
                    manager(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.getLong("at"), intent)
                }
            } else {
                manager(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.getLong("at"), intent)
            }
        }
    }

    fun take(context: Context, candidate: JSONObject): JSONObject? {
        val items = read(context)
        // Reject cancelled/replaced alarms, including a broadcast already queued by Android.
        val current = items.firstOrNull {
            it.getInt("id") == candidate.getInt("id") && it.toString() == candidate.toString()
        } ?: return null
        preferences(context).edit().putString(
            KEY, JSONArray(items.filter { it.getInt("id") != current.getInt("id") }).toString(),
        ).commit()
        return current
    }

    fun play(context: Context, item: JSONObject) {
        try {
            ContextCompat.startForegroundService(
                context, Intent(context, AdhanPlaybackService::class.java).putExtra(EXTRA, item.toString()),
            )
        } catch (_: IllegalStateException) {
            // Inexact alarms lack the background-service exemption. Still deliver
            // the prayer alert with the bundled short sound if Android denies playback.
            AdhanPlaybackService.showFallback(context, item)
        } catch (_: SecurityException) {
            AdhanPlaybackService.showFallback(context, item)
        }
    }
}

class AdhanAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val raw = intent.getStringExtra(AdhanScheduler.EXTRA) ?: return
        val item = AdhanScheduler.take(context, JSONObject(raw)) ?: return
        // Never play a stale adhan after a long shutdown or a clock correction.
        if (System.currentTimeMillis() - item.getLong("at") > 10 * 60 * 1000) return
        AdhanScheduler.play(context, item)
    }
}

class AdhanRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AdhanScheduler.restore(context)
    }
}
