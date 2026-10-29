// GENERATED CODE - DO NOT MODIFY BY HAND
//
// This is a placeholder Glance (Jetpack Compose) widget.
package com.dakomn.mishkatapp

import androidx.compose.runtime.Composable
import android.content.Context
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
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.Row
import androidx.glance.layout.fillMaxWidth
import androidx.glance.text.TextStyle
import androidx.glance.color.ColorProvider
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
      "e179124a",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val widgetData =
        if (preview) PrayerTimesWidgetData.previewFromPreferences(prefs)
        else PrayerTimesWidgetData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF3F8F5), night = Color(0xFF10211B))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://prayer?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.End) {
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(text = widgetData.prayerCity ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFDDEDE7), night = Color(0xFF1D3930))).cornerRadius(999.0.dp).padding(start = 8.0.dp, top = 3.0.dp, end = 8.0.dp, bottom = 3.0.dp), text = "مِشكاة • الصلاة", style = TextStyle(color = ColorProvider(day = Color(0xFF276C5D), night = Color(0xFF91DDC0)), fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFDDEDE7), night = Color(0xFF1D3930))).cornerRadius(12.0.dp).padding(start = 10.0.dp, top = 7.0.dp, end = 10.0.dp, bottom = 7.0.dp), text = widgetData.prayerRemaining ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.End) {
                            Text(text = "الصلاة القادمة", style = TextStyle(color = ColorProvider(day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                            Text(text = widgetData.prayerNextName ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF17362F), night = Color(0xFFF3F8F5)), fontSize = 22.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                            Text(text = widgetData.prayerNextTime ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF276C5D), night = Color(0xFF91DDC0)), fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                        }
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFDDEDE7), night = Color(0xFF1D3930))).cornerRadius(10.0.dp).padding(start = 9.0.dp, top = 5.0.dp, end = 9.0.dp, bottom = 5.0.dp), text = widgetData.prayerUpcoming ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF60716B), night = Color(0xFFADBBB5)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                }
            }
    }

  }
}

data class PrayerTimesWidgetData(
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
                prayerCity = prefs.getString("${PREFERENCES_PREFIX}.prayerCity", "مكة المكرمة"),
                prayerRemaining = if (timedValues.has("prayerRemaining") && !timedValues.isNull("prayerRemaining")) timedValues.optString("prayerRemaining") else "متبقي نحو ساعتين",
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
                json.optJSONObject(resolvedKey) ?: org.json.JSONObject()
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
