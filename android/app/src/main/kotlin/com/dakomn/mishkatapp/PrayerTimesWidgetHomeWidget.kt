// CUSTOMIZED NATIVE WIDGET — preserve when regenerating Dart declarations.
// See docs/HOME_WIDGETS.md for the native rendering/data contract.
package com.dakomn.mishkatapp

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.glance.LocalSize
import androidx.glance.appwidget.SizeMode
import android.content.Context
import android.os.SystemClock
import android.widget.RemoteViews
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.layout.width
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.text.Text
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetPlugin
import androidx.glance.layout.Column
import androidx.glance.layout.Alignment
import androidx.glance.layout.Spacer
import androidx.glance.layout.Row
import androidx.glance.layout.fillMaxWidth
import androidx.glance.text.TextStyle
import androidx.compose.ui.unit.sp
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import androidx.compose.ui.unit.dp
import androidx.glance.layout.padding
import androidx.glance.appwidget.cornerRadius
import androidx.core.os.ConfigurationCompat
import java.util.Locale
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity

class PrayerTimesWidgetHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()
  // Lock-screen hosts commonly provide a taller surface than the 4×2 home widget.
  // The same saved prayer data and native clock serve both placements.
  override val sizeMode = SizeMode.Responsive(setOf(
      DpSize(220.dp, 130.dp), DpSize(300.dp, 160.dp),
      DpSize(300.dp, 210.dp), DpSize(360.dp, 240.dp),
  ))

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent { WidgetContent(context, currentState()) }
  }

  override suspend fun providePreview(context: Context, widgetCategory: Int) {
    provideContent { WidgetContent(context, HomeWidgetGlanceState(HomeWidgetPlugin.getData(context)), preview = true) }
  }

  fun previewFingerprint(context: Context): String {
    val hwLocales = hwCurrentLocales(context)
    val hwPreviewData =
        PrayerTimesWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "prayer-home-lock-v2",
      hwLocales.joinToString(","),
      hwPreviewData.copy(prayerNextAt = 0L).toString(),
      HomeWidgetPlugin.getData(context).getString("widgetTheme", "system"),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val size = LocalSize.current
    val compact = size.width < 280.dp || size.height < 150.dp
    val tall = size.height >= 190.dp
    val widgetData =
        if (preview) PrayerTimesWidgetData.previewFromPreferences(prefs)
        else PrayerTimesWidgetData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(mishkatWidgetColor(prefs, day = Color(0xFFF3F8F5), night = Color(0xFF10211B))).padding(if (compact) 12.dp else 16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://prayer?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.End) {
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(modifier = GlanceModifier.defaultWeight(), text = widgetData.prayerCity ?: "", maxLines = 1, style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                        Spacer(modifier = GlanceModifier.width(8.dp))
                        Text(modifier = GlanceModifier.background(mishkatWidgetColor(prefs, day = Color(0xFFDDEDE7), night = Color(0xFF1D3930))).cornerRadius(999.0.dp).padding(start = 8.0.dp, top = 3.0.dp, end = 8.0.dp, bottom = 3.0.dp), text = "مِشكاة • الصلاة", maxLines = 1, style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF276C5D), night = Color(0xFF91DDC0)), fontSize = if (compact) 11.sp else 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(horizontalAlignment = Alignment.Start) {
                            Column(
                                modifier = GlanceModifier.background(mishkatWidgetColor(prefs, day = Color(0xFFDDEDE7), night = Color(0xFF1D3930))).cornerRadius(12.dp).width(if (compact) 110.dp else 132.dp).padding(8.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Text(text = "متبقي", style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp))
                                val remaining = widgetData.prayerNextAt - System.currentTimeMillis()
                                if (remaining > 0L) {
                                    val timer = RemoteViews(context.packageName, R.layout.mishkat_widget_countdown).apply {
                                        // In system mode the day/night XML color tracks the launcher theme.
                                        when (prefs.getString("widgetTheme", "system")) {
                                            "light" -> setTextColor(R.id.mishkat_prayer_countdown, 0xFF276C5D.toInt())
                                            "dark" -> setTextColor(R.id.mishkat_prayer_countdown, 0xFF91DDC0.toInt())
                                        }
                                        setChronometerCountDown(R.id.mishkat_prayer_countdown, true)
                                        // The launcher owns ticking. The saved timeline advances at each prayer.
                                        // Use the system timer format: unlike a static prefix it stays valid at hour boundaries.
                                        setChronometer(R.id.mishkat_prayer_countdown, SystemClock.elapsedRealtime() + remaining, null, !preview)
                                        if (preview) setTextViewText(R.id.mishkat_prayer_countdown, "48:30")
                                    }
                                    AndroidRemoteViews(remoteViews = timer)
                                } else {
                                    Text(text = widgetData.prayerRemaining ?: "افتح مشكاة لتحديث المواقيت", style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, textAlign = TextAlign.Center))
                                }
                            }
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.End) {
                            Text(text = "الصلاة القادمة", style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                            Text(text = widgetData.prayerNextName ?: "", maxLines = 1, style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF17362F), night = Color(0xFFF3F8F5)), fontSize = if (tall) 28.sp else 22.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                            Text(text = widgetData.prayerNextTime ?: "", maxLines = 1, style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF276C5D), night = Color(0xFF91DDC0)), fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                        }
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(modifier = GlanceModifier.background(mishkatWidgetColor(prefs, day = Color(0xFFDDEDE7), night = Color(0xFF1D3930))).cornerRadius(10.0.dp).padding(start = 9.0.dp, top = 5.0.dp, end = 9.0.dp, bottom = 5.0.dp), text = widgetData.prayerUpcoming ?: "", maxLines = if (tall) 2 else 1, style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = if (compact) 10.sp else 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                }
            }
    }

  }
}

data class PrayerTimesWidgetData(
    val prayerNextAt: Long = 0,
    val prayerCity: String? = null,
    val prayerRemaining: String? = null,
    val prayerNextName: String? = null,
    val prayerNextTime: String? = null,
    val prayerUpcoming: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.PrayerTimesWidget"

        fun fromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): PrayerTimesWidgetData {
            val timedValues = resolveTimedValues(prefs, now)
            return PrayerTimesWidgetData(
                prayerNextAt = timedValues.optLong("prayerNextAt", 0L),
                prayerCity = prefs.getString("${PREFERENCES_PREFIX}.prayerCity", "حدّد موقعك في مشكاة"),
                prayerRemaining = if (timedValues.has("prayerRemaining") && !timedValues.isNull("prayerRemaining")) timedValues.optString("prayerRemaining") else "افتح مشكاة لتحديث المواقيت",
                prayerNextName = if (timedValues.has("prayerNextName") && !timedValues.isNull("prayerNextName")) timedValues.optString("prayerNextName") else "—",
                prayerNextTime = if (timedValues.has("prayerNextTime") && !timedValues.isNull("prayerNextTime")) timedValues.optString("prayerNextTime") else "—",
                prayerUpcoming = if (timedValues.has("prayerUpcoming") && !timedValues.isNull("prayerUpcoming")) timedValues.optString("prayerUpcoming") else "تظهر المواقيت بعد تحديد الموقع",
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): PrayerTimesWidgetData {
            val timedValues = resolveTimedValues(prefs, now)
            return PrayerTimesWidgetData(
                prayerNextAt = timedValues.optLong("prayerNextAt", now + 2910000L),
                prayerCity = prefs.getString("${PREFERENCES_PREFIX}.prayerCity", "مكة المكرمة"),
                prayerRemaining = if (timedValues.has("prayerRemaining") && !timedValues.isNull("prayerRemaining")) timedValues.optString("prayerRemaining") else "48:30",
                prayerNextName = if (timedValues.has("prayerNextName") && !timedValues.isNull("prayerNextName")) timedValues.optString("prayerNextName") else "المغرب",
                prayerNextTime = if (timedValues.has("prayerNextTime") && !timedValues.isNull("prayerNextTime")) timedValues.optString("prayerNextTime") else "٥:٤٢ م",
                prayerUpcoming = if (timedValues.has("prayerUpcoming") && !timedValues.isNull("prayerUpcoming")) timedValues.optString("prayerUpcoming") else "العصر ٣:٢١  •  المغرب ٥:٤٢  •  العشاء ٧:١٢",
            )
        }

        private fun resolveTimedValues(prefs: android.content.SharedPreferences, now: Long): org.json.JSONObject {
            val path = prefs.getString("${PREFERENCES_PREFIX}.timedData", null) ?: return org.json.JSONObject()
            return try {
                val file = java.io.File(path)
                if (!file.exists()) return org.json.JSONObject()
                val json = org.json.JSONObject(file.readText())
                var activeKey: String? = null
                var activeTimestamp = 0L
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val timestamp = key.toLongOrNull() ?: continue
                    if (timestamp <= now && (activeKey == null || timestamp > activeTimestamp)) {
                        activeKey = key
                        activeTimestamp = timestamp
                    }
                }
                val resolvedKey = activeKey ?: return org.json.JSONObject()
                val values = json.optJSONObject(resolvedKey) ?: return org.json.JSONObject()
                if (values.optLong("prayerNextAt", 0L) <= now) {
                    org.json.JSONObject().put("prayerRemaining", "افتح مشكاة لتحديث المواقيت")
                } else values
            } catch (_: Exception) {
                org.json.JSONObject()
            }
        }
    }
}


private fun hwCurrentLocales(context: Context): List<String> {
    val configured = ConfigurationCompat
        .getLocales(context.resources.configuration)
    val tags = mutableListOf<String>()
    for (index in 0 until configured.size()) {
        val locale = configured[index] ?: continue
        val tag = locale.toLanguageTag()
        if (tag.isNotEmpty() && tag != "und") tags.add(tag)
    }
    if (tags.isEmpty()) {
        val fallback = Locale.getDefault().toLanguageTag()
        if (fallback.isNotEmpty() && fallback != "und") tags.add(fallback)
    }
    return tags
}
