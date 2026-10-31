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

class TasbihWidgetHomeWidget : GlanceAppWidget() {
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
        TasbihWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "976163be",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val widgetData =
        if (preview) TasbihWidgetData.previewFromPreferences(prefs)
        else TasbihWidgetData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF8F3FC), night = Color(0xFF271E30))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://tasbih?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = "مِشكاة • المسبحة", style = TextStyle(color = ColorProvider(day = Color(0xFF725387), night = Color(0xFFD7B8EE)), fontSize = 11.sp, fontWeight = FontWeight.Bold))
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Column(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFEFE3F7), night = Color(0xFF3A2945))).cornerRadius(18.0.dp).padding(start = 12.0.dp, top = 8.0.dp, end = 12.0.dp, bottom = 8.0.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = widgetData.tasbihDhikr ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF725387), night = Color(0xFFD7B8EE)), fontSize = 13.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center))
                        Text(text = widgetData.tasbihCount ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF263B35), night = Color(0xFFF6F4F1)), fontSize = 36.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center))
                        Text(text = widgetData.tasbihTarget ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF725387), night = Color(0xFFD7B8EE)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center))
                        Text(text = widgetData.tasbihToday ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF725387), night = Color(0xFFD7B8EE)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center))
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(text = widgetData.tasbihAction ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF725387), night = Color(0xFFD7B8EE)), fontSize = 10.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center))
                }
            }
    }

  }
}

data class TasbihWidgetData(
    val tasbihDhikr: String? = null,
    val tasbihCount: String? = null,
    val tasbihTarget: String? = null,
    val tasbihAction: String? = null,
    val tasbihToday: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.TasbihWidget"

        fun fromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): TasbihWidgetData {
            val timedValues = resolveTimedValues(prefs, now)
            return TasbihWidgetData(
                tasbihDhikr = prefs.getString("${PREFERENCES_PREFIX}.tasbihDhikr", "سبحان الله"),
                tasbihCount = prefs.getString("${PREFERENCES_PREFIX}.tasbihCount", "٠"),
                tasbihTarget = prefs.getString("${PREFERENCES_PREFIX}.tasbihTarget", "الهدف ٣٣"),
                tasbihAction = prefs.getString("${PREFERENCES_PREFIX}.tasbihAction", "اضغط لفتح المسبحة"),
                tasbihToday = if (timedValues.has("tasbihToday") && !timedValues.isNull("tasbihToday")) timedValues.optString("tasbihToday") else "اليوم ٠ تسبيحة",
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): TasbihWidgetData {
            val timedValues = resolveTimedValues(prefs, now)
            return TasbihWidgetData(
                tasbihDhikr = prefs.getString("${PREFERENCES_PREFIX}.tasbihDhikr", "سبحان الله"),
                tasbihCount = prefs.getString("${PREFERENCES_PREFIX}.tasbihCount", "٢٤"),
                tasbihTarget = prefs.getString("${PREFERENCES_PREFIX}.tasbihTarget", "الهدف ٣٣"),
                tasbihAction = prefs.getString("${PREFERENCES_PREFIX}.tasbihAction", "اضغط لفتح المسبحة"),
                tasbihToday = if (timedValues.has("tasbihToday") && !timedValues.isNull("tasbihToday")) timedValues.optString("tasbihToday") else "اليوم ٩٠ تسبيحة",
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
