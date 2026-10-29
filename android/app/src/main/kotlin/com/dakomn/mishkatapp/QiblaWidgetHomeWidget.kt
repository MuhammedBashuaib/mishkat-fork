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
import androidx.compose.ui.unit.dp
import androidx.glance.layout.padding
import androidx.glance.appwidget.cornerRadius
import androidx.core.os.ConfigurationCompat
import java.util.Locale
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity

class QiblaWidgetHomeWidget : GlanceAppWidget() {
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
        QiblaWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "a546e530",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val widgetData =
        if (preview) QiblaWidgetData.previewFromPreferences(prefs)
        else QiblaWidgetData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF214F44), night = Color(0xFF0E2821))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://qibla?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = "مِشكاة • القبلة", style = TextStyle(color = ColorProvider(day = Color(0xFFB7D0C7), night = Color(0xFFB7D0C7)), fontSize = 12.sp, fontWeight = FontWeight.Bold))
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Box(
                        modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF0CF82), night = Color(0xFFF0CF82))).cornerRadius(999.0.dp).padding(1.0.dp)
                    ) {
                        Box(
                            modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF315F54), night = Color(0xFF1B4036))).cornerRadius(998.0.dp)
                        ) {
                            Text(modifier = GlanceModifier.padding(start = 15.0.dp, top = 8.0.dp, end = 15.0.dp, bottom = 8.0.dp), text = widgetData.qiblaArrow ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFF0CF82), night = Color(0xFFF0CF82)), fontSize = 42.sp, fontWeight = FontWeight.Normal))
                        }
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = widgetData.qiblaBearing ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFF4FAF7), night = Color(0xFFF4FAF7)), fontSize = 13.sp, fontWeight = FontWeight.Bold))
                        Text(modifier = GlanceModifier.padding(top = 1.0.dp), text = widgetData.qiblaDistance ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFB7D0C7), night = Color(0xFFB7D0C7)), fontSize = 10.sp))
                    }
                }
            }
    }

  }
}

data class QiblaWidgetData(
    val qiblaArrow: String? = null,
    val qiblaBearing: String? = null,
    val qiblaDistance: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.QiblaWidget"

        fun fromPreferences(prefs: android.content.SharedPreferences): QiblaWidgetData {
            return QiblaWidgetData(
                qiblaArrow = prefs.getString("${PREFERENCES_PREFIX}.qiblaArrow", "↑"),
                qiblaBearing = prefs.getString("${PREFERENCES_PREFIX}.qiblaBearing", "حدّد موقعك"),
                qiblaDistance = prefs.getString("${PREFERENCES_PREFIX}.qiblaDistance", "افتح مشكاة للبوصلة الحية"),
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences): QiblaWidgetData {
            return QiblaWidgetData(
                qiblaArrow = prefs.getString("${PREFERENCES_PREFIX}.qiblaArrow", "↗"),
                qiblaBearing = prefs.getString("${PREFERENCES_PREFIX}.qiblaBearing", "٢٧٧° شمال غربي"),
                qiblaDistance = prefs.getString("${PREFERENCES_PREFIX}.qiblaDistance", "٨٢٣ كم إلى الكعبة"),
            )
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
