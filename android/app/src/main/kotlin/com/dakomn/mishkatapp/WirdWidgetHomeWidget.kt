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

class WirdWidgetHomeWidget : GlanceAppWidget() {
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
        WirdWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "83323d82",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val widgetData =
        if (preview) WirdWidgetData.previewFromPreferences(prefs)
        else WirdWidgetData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF2F7F3), night = Color(0xFF152923))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://wird?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.End) {
                    Text(text = "مِشكاة • الورد اليومي", style = TextStyle(color = ColorProvider(day = Color(0xFF486B65), night = Color(0xFFA9D9CC)), fontSize = 11.sp, fontWeight = FontWeight.Bold))
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Column(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE2EEE7), night = Color(0xFF233E33))).cornerRadius(18.0.dp).padding(start = 12.0.dp, top = 8.0.dp, end = 12.0.dp, bottom = 8.0.dp), horizontalAlignment = Alignment.End) {
                        Text(text = widgetData.wirdName ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF486B65), night = Color(0xFFA9D9CC)), fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                        Text(text = widgetData.wirdPages ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF263B35), night = Color(0xFFF6F4F1)), fontSize = 23.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End))
                        Text(text = widgetData.wirdDetail ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF486B65), night = Color(0xFFA9D9CC)), fontSize = 12.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                        Text(text = widgetData.wirdProgress ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF486B65), night = Color(0xFFA9D9CC)), fontSize = 12.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Text(text = widgetData.wirdAction ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF486B65), night = Color(0xFFA9D9CC)), fontSize = 10.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End))
                }
            }
    }

  }
}

data class WirdWidgetData(
    val wirdName: String? = null,
    val wirdPages: String? = null,
    val wirdDetail: String? = null,
    val wirdProgress: String? = null,
    val wirdAction: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.WirdWidget"

        fun fromPreferences(prefs: android.content.SharedPreferences): WirdWidgetData {
            return WirdWidgetData(
                wirdName = prefs.getString("${PREFERENCES_PREFIX}.wirdName", "رحلتك مع القرآن"),
                wirdPages = prefs.getString("${PREFERENCES_PREFIX}.wirdPages", "ابدأ ختمتك الأولى"),
                wirdDetail = prefs.getString("${PREFERENCES_PREFIX}.wirdDetail", "حدّد خطتك ليظهر وردك هنا"),
                wirdProgress = prefs.getString("${PREFERENCES_PREFIX}.wirdProgress", "خطوة صغيرة كل يوم"),
                wirdAction = prefs.getString("${PREFERENCES_PREFIX}.wirdAction", "اضغط لإنشاء خطة"),
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences): WirdWidgetData {
            return WirdWidgetData(
                wirdName = prefs.getString("${PREFERENCES_PREFIX}.wirdName", "ختمتي"),
                wirdPages = prefs.getString("${PREFERENCES_PREFIX}.wirdPages", "صفحة ٤٢ – ٦٢"),
                wirdDetail = prefs.getString("${PREFERENCES_PREFIX}.wirdDetail", "٢١ صفحة في وردك الحالي"),
                wirdProgress = prefs.getString("${PREFERENCES_PREFIX}.wirdProgress", "٧٪ من الختمة"),
                wirdAction = prefs.getString("${PREFERENCES_PREFIX}.wirdAction", "اضغط لمتابعة القراءة"),
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
