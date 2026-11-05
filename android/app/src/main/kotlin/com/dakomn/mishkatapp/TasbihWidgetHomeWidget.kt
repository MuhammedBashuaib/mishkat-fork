// CUSTOMIZED native widget. Maintain by hand; see docs/HOME_WIDGETS.md.
package com.dakomn.mishkatapp

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.glance.LocalSize
import androidx.glance.appwidget.SizeMode
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.ColorFilter
import androidx.glance.layout.size
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.roundToInt
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
import androidx.glance.text.TextStyle
import androidx.compose.ui.unit.sp
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import androidx.compose.ui.unit.dp
import androidx.glance.layout.padding
import androidx.core.os.ConfigurationCompat
import java.util.Locale
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity

class TasbihWidgetHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()
  override val sizeMode = SizeMode.Responsive(setOf(
      DpSize(110.dp, 110.dp), DpSize(150.dp, 150.dp),
      DpSize(150.dp, 170.dp), DpSize(240.dp, 150.dp),
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
        TasbihWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "compact-tasbih-v2",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
      HomeWidgetPlugin.getData(context).getString("widgetTheme", "system"),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val data = if (preview) TasbihWidgetData.previewFromPreferences(prefs) else TasbihWidgetData.fromPreferences(prefs)
    val size = LocalSize.current
    val compact = size.width < 140.dp || size.height < 140.dp
    val ringSize = if (compact) 58.dp else 78.dp
    val countLength = data.tasbihCount.orEmpty().length
    val countFont = when {
        countLength >= 5 -> if (compact) 16.sp else 24.sp
        countLength >= 4 -> if (compact) 20.sp else 28.sp
        else -> if (compact) 24.sp else 34.sp
    }
    val ringPixels = (ringSize.value * context.resources.displayMetrics.density).roundToInt().coerceAtLeast(1)
    val accent = mishkatWidgetColor(prefs, day = Color(0xFF82569C), night = Color(0xFFD7B1EE))
    val secondary = mishkatWidgetColor(prefs, day = Color(0xFF85708D), night = Color(0xFFBFAACB))
    val track = mishkatWidgetColor(prefs, day = Color(0xFFE3D6EB), night = Color(0xFF513B5F))

    GlanceTheme {
      Column(
          modifier = GlanceModifier.fillMaxSize()
              .background(mishkatWidgetColor(prefs, day = Color(0xFFF8F3FC), night = Color(0xFF271E30)))
              .clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://tasbih?homeWidget")))
              .padding(if (compact) 10.dp else 12.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Text(text = "المسبحة", maxLines = 1, style = TextStyle(color = secondary, fontSize = if (compact) 9.sp else 10.sp, textAlign = TextAlign.Center))
        Text(
            text = data.tasbihDhikr.orEmpty(), maxLines = 1,
            style = TextStyle(color = accent, fontSize = if (compact) 11.sp else 12.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center),
        )
        Spacer(modifier = GlanceModifier.defaultWeight())
        Box(modifier = GlanceModifier.size(ringSize), contentAlignment = Alignment.Center) {
          Image(
              provider = ImageProvider(tasbihRingBitmap(1.0, beads = true, pixels = ringPixels)), contentDescription = null,
              modifier = GlanceModifier.fillMaxSize(), colorFilter = ColorFilter.tint(track),
          )
          Image(
              provider = ImageProvider(tasbihRingBitmap(data.tasbihProgressValue, beads = false, pixels = ringPixels)),
              contentDescription = "تقدم التسبيح", modifier = GlanceModifier.fillMaxSize(), colorFilter = ColorFilter.tint(accent),
          )
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = data.tasbihCount.orEmpty(), maxLines = 1,
                style = TextStyle(color = accent, fontSize = countFont, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
            )
            Text(
                text = data.tasbihTarget.orEmpty(), maxLines = 1,
                style = TextStyle(color = secondary, fontSize = if (compact) 8.sp else 9.sp, textAlign = TextAlign.Center),
            )
          }
        }
        Spacer(modifier = GlanceModifier.defaultWeight())
        if (size.height >= 160.dp && size.width >= 140.dp) {
          Text(text = data.tasbihToday.orEmpty(), maxLines = 1, style = TextStyle(color = secondary, fontSize = 10.sp, textAlign = TextAlign.Center))
        }
      }
    }
  }
}

data class TasbihWidgetData(
    val tasbihProgressValue: Double = 0.0,
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
                tasbihProgressValue = mishkatWidgetDouble(prefs, "${PREFERENCES_PREFIX}.tasbihProgressValue", 0.0).coerceIn(0.0, 1.0),
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
                tasbihProgressValue = mishkatWidgetDouble(prefs, "${PREFERENCES_PREFIX}.tasbihProgressValue", (24.0 / 33.0)).coerceIn(0.0, 1.0),
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

/** Transparent masks keep both the bead track and progress arc responsive to system theme. */
private fun tasbihRingBitmap(progress: Double, beads: Boolean, pixels: Int): Bitmap {
    val bitmap = Bitmap.createBitmap(pixels, pixels, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(pixels / 240f, pixels / 240f)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        strokeWidth = 7f
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
    }
    val bounds = RectF(17f, 17f, 223f, 223f)
    if (beads) {
        canvas.drawOval(bounds, paint)
        paint.style = Paint.Style.FILL
        for (bead in 0 until 12) {
            val radians = Math.toRadians(bead * 30.0 - 90.0)
            canvas.drawCircle(120f + 103f * cos(radians).toFloat(), 120f + 103f * sin(radians).toFloat(), 5f, paint)
        }
    } else if (progress > 0.0) {
        canvas.drawArc(bounds, -90f, (progress.coerceIn(0.0, 1.0) * 360).toFloat(), false, paint)
    }
    return bitmap
}
