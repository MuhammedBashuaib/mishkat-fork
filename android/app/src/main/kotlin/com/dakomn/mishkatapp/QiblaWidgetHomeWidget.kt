// CUSTOMIZED NATIVE WIDGET — preserve when regenerating Dart declarations.
// See docs/HOME_WIDGETS.md for the native rendering/data contract.
package com.dakomn.mishkatapp

import androidx.compose.runtime.Composable
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.ColorFilter
import androidx.glance.layout.size
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
      HomeWidgetPlugin.getData(context).getString("widgetTheme", "system"),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val widgetData =
        if (preview) QiblaWidgetData.previewFromPreferences(prefs)
        else QiblaWidgetData.fromPreferences(prefs)
    val hasBearing = widgetData.qiblaBearingDegrees.isFinite() && widgetData.qiblaBearingDegrees >= 0.0
    GlanceTheme {
            Box(modifier = GlanceModifier.background(mishkatWidgetColor(prefs, day = Color(0xFFF3F8F5), night = Color(0xFF0E2821))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://qibla?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(text = "مِشكاة • القبلة", style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF526F63), night = Color(0xFFB7D0C7)), fontSize = 12.sp, fontWeight = FontWeight.Bold))
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Image(
                        provider = ImageProvider(qiblaCompassBitmap(widgetData.qiblaBearingDegrees)),
                        contentDescription = if (hasBearing) "اتجاه القبلة بالنسبة للشمال" else "الشمال — حدّد موقعك لاتجاه القبلة",
                        modifier = GlanceModifier.size(66.dp).background(mishkatWidgetColor(prefs, day = Color(0xFFE0EDE6), night = Color(0xFF1B4036))).cornerRadius(33.dp),
                        colorFilter = ColorFilter.tint(mishkatWidgetColor(prefs, day = Color(0xFF9B742C), night = Color(0xFFF0CF82))),
                    )
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = if (hasBearing) widgetData.qiblaBearing ?: "القبلة" else "الشمال", maxLines = 1, style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF17362F), night = Color(0xFFF4FAF7)), fontSize = 12.sp, fontWeight = FontWeight.Bold))
                        Text(text = if (hasBearing) "بالنسبة للشمال" else "حدّد موقعك للقبلة", style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF526F63), night = Color(0xFFB7D0C7)), fontSize = 9.sp))
                        Text(text = "اضغط للبوصلة الحية", style = TextStyle(color = mishkatWidgetColor(prefs, day = Color(0xFF526F63), night = Color(0xFFB7D0C7)), fontSize = 9.sp))
                    }
                }
            }
    }

  }
}

data class QiblaWidgetData(
    val qiblaBearingDegrees: Double = -1.0,
    val qiblaArrow: String? = null,
    val qiblaBearing: String? = null,
    val qiblaDistance: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.QiblaWidget"

        fun fromPreferences(prefs: android.content.SharedPreferences): QiblaWidgetData {
            return QiblaWidgetData(
                qiblaBearingDegrees = mishkatWidgetDouble(prefs, "${PREFERENCES_PREFIX}.qiblaBearingDegrees", -1.0),
                qiblaArrow = prefs.getString("${PREFERENCES_PREFIX}.qiblaArrow", "↑"),
                qiblaBearing = prefs.getString("${PREFERENCES_PREFIX}.qiblaBearing", "حدّد موقعك"),
                qiblaDistance = prefs.getString("${PREFERENCES_PREFIX}.qiblaDistance", "افتح مشكاة للبوصلة الحية"),
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences): QiblaWidgetData {
            return QiblaWidgetData(
                qiblaBearingDegrees = mishkatWidgetDouble(prefs, "${PREFERENCES_PREFIX}.qiblaBearingDegrees", 277.0),
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

/** North stays at the top. A widget cannot continuously read the device compass. */
private fun qiblaCompassBitmap(bearing: Double): Bitmap {
    val bitmap = Bitmap.createBitmap(216, 216, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val accent = android.graphics.Color.WHITE
    val ink = android.graphics.Color.WHITE
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = accent
    paint.style = Paint.Style.STROKE
    paint.strokeWidth = 3f
    canvas.drawCircle(108f, 108f, 100f, paint)
    paint.style = Paint.Style.FILL
    paint.color = ink
    paint.textSize = 26f
    paint.textAlign = Paint.Align.CENTER
    canvas.drawText("N", 108f, 35f, paint)
    val angle = if (bearing.isFinite() && bearing >= 0.0) bearing % 360 else 0.0
        canvas.save()
        canvas.rotate(angle.toFloat(), 108f, 108f)
        val arrow = Path().apply {
            moveTo(108f, 48f)
            lineTo(139f, 136f)
            lineTo(108f, 119f)
            lineTo(77f, 136f)
            close()
        }
        paint.color = accent
        canvas.drawPath(arrow, paint)
        canvas.restore()
    return bitmap
}
