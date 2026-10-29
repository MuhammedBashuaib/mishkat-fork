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
import androidx.compose.ui.unit.dp
import androidx.glance.layout.padding
import androidx.glance.appwidget.cornerRadius
import androidx.glance.text.TextAlign
import androidx.core.os.ConfigurationCompat
import java.util.Locale
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity

class AdhkarWidgetHomeWidget : GlanceAppWidget() {
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
        AdhkarWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "a5541cb9",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val widgetData =
        if (preview) AdhkarWidgetData.previewFromPreferences(prefs)
        else AdhkarWidgetData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFFF8F2), night = Color(0xFF211A18))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://adhkar?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.End) {
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF3E6DE), night = Color(0xFF3B2C27))).cornerRadius(999.0.dp).padding(start = 9.0.dp, top = 4.0.dp, end = 9.0.dp, bottom = 4.0.dp), text = widgetData.dhikrCount ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF8B5D43), night = Color(0xFFE8C19F)), fontSize = 10.sp, fontWeight = FontWeight.Bold))
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(text = widgetData.dhikrCategory ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF8B5D43), night = Color(0xFFE8C19F)), fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF3E6DE), night = Color(0xFF3B2C27))).cornerRadius(14.0.dp).padding(start = 11.0.dp, top = 8.0.dp, end = 11.0.dp, bottom = 8.0.dp), text = widgetData.dhikrText ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF3E2C24), night = Color(0xFFF7EEE8)), fontSize = 15.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(text = "← اضغط للمتابعة داخل مشكاة", style = TextStyle(color = ColorProvider(day = Color(0xFF7A6559), night = Color(0xFFC2ACA0)), fontSize = 10.sp, textAlign = TextAlign.End))
                }
            }
    }

  }
}

data class AdhkarWidgetData(
    val dhikrCount: String? = null,
    val dhikrCategory: String? = null,
    val dhikrText: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.AdhkarWidget"

        fun fromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): AdhkarWidgetData {
            val timedValues = resolveTimedValues(prefs, now)
            return AdhkarWidgetData(
                dhikrCount = if (timedValues.has("dhikrCount") && !timedValues.isNull("dhikrCount")) timedValues.optString("dhikrCount") else "مرة واحدة",
                dhikrCategory = if (timedValues.has("dhikrCategory") && !timedValues.isNull("dhikrCategory")) timedValues.optString("dhikrCategory") else "ذِكر اليوم",
                dhikrText = if (timedValues.has("dhikrText") && !timedValues.isNull("dhikrText")) timedValues.optString("dhikrText") else "سبحان الله وبحمده، سبحان الله العظيم.",
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): AdhkarWidgetData {
            val timedValues = resolveTimedValues(prefs, now)
            return AdhkarWidgetData(
                dhikrCount = if (timedValues.has("dhikrCount") && !timedValues.isNull("dhikrCount")) timedValues.optString("dhikrCount") else "٣ مرات",
                dhikrCategory = if (timedValues.has("dhikrCategory") && !timedValues.isNull("dhikrCategory")) timedValues.optString("dhikrCategory") else "أذكار المساء",
                dhikrText = if (timedValues.has("dhikrText") && !timedValues.isNull("dhikrText")) timedValues.optString("dhikrText") else "رَضِيتُ بِاللَّهِ رَبًّا، وَبِالإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا.",
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
