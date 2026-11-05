// CUSTOMIZED NATIVE WIDGET — preserve when regenerating Dart declarations.
// See docs/HOME_WIDGETS.md for the native rendering/data contract.
package com.dakomn.mishkatapp

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.glance.LocalSize
import androidx.glance.appwidget.SizeMode
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.ColorFilter
import androidx.glance.layout.Row
import androidx.glance.layout.width
import androidx.glance.layout.size
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
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
import kotlin.math.roundToInt
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity

class WirdWidgetHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()
  override val sizeMode = SizeMode.Responsive(setOf(
      DpSize(220.dp, 130.dp), DpSize(300.dp, 150.dp), DpSize(360.dp, 170.dp),
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
        WirdWidgetData.previewFromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "wide-wird-v3",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
      HomeWidgetPlugin.getData(context).getString("widgetTheme", "system"),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState, preview: Boolean = false) {
    val prefs = currentState.preferences
    val data = if (preview) WirdWidgetData.previewFromPreferences(prefs) else WirdWidgetData.fromPreferences(prefs)
    val size = LocalSize.current
    val compact = size.width < 280.dp || size.height < 145.dp
    val noPlan = data.wirdPages == "ابدأ ختمتك الأولى"
    val paused = data.wirdDetail == "الخطة متوقفة مؤقتًا"
    val completed = !noPlan && data.wirdProgressValue >= 1.0
    val accent = mishkatWidgetColor(prefs, day = Color(0xFF238661), night = Color(0xFF72D4A3))
    val secondary = mishkatWidgetColor(prefs, day = Color(0xFF60766B), night = Color(0xFFA9C2B5))
    val ink = mishkatWidgetColor(prefs, day = Color(0xFF263B35), night = Color(0xFFF6F4F1))
    val percentage = ((data.wirdProgressValue * 100).roundToInt()).toString()
        .map { digit -> if (digit in '0'..'9') "٠١٢٣٤٥٦٧٨٩"[digit - '0'] else digit }.joinToString("") + "٪"
    val reading = when {
        noPlan -> "ابدأ ختمتك"
        paused -> "متوقفة مؤقتًا"
        completed -> "أتممت الختمة"
        else -> data.wirdPages.orEmpty()
    }
    val caption = when {
        noPlan -> "رحلتك مع القرآن"
        paused -> "خطة الختمة"
        completed -> "تقبّل الله قراءتك"
        else -> "وردك الحالي"
    }

    GlanceTheme {
      Column(
          modifier = GlanceModifier.fillMaxSize()
              .background(mishkatWidgetColor(prefs, day = Color(0xFFF2F7F3), night = Color(0xFF152923)))
              .clickable(onClick = actionStartActivity<MainActivity>(context, Uri.parse("mishkat://wird?homeWidget")))
              .padding(if (compact) 12.dp else 14.dp),
          horizontalAlignment = Alignment.End,
      ) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
          Text(
              modifier = GlanceModifier.defaultWeight(), text = if (noPlan) "مِشكاة" else data.wirdName.orEmpty(), maxLines = 1,
              style = TextStyle(color = secondary, fontSize = if (compact) 10.sp else 11.sp, fontWeight = FontWeight.Medium),
          )
          Spacer(modifier = GlanceModifier.width(8.dp))
          Text(text = "ورد الختمة", maxLines = 1, style = TextStyle(color = accent, fontSize = 10.sp, fontWeight = FontWeight.Bold))
          Spacer(modifier = GlanceModifier.width(5.dp))
          Image(
              provider = ImageProvider(wirdBookBitmap()), contentDescription = null,
              modifier = GlanceModifier.size(15.dp), colorFilter = ColorFilter.tint(accent),
          )
        }
        Row(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Column(
              modifier = GlanceModifier.width(if (compact) 68.dp else 80.dp),
              horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Text(
                text = if (noPlan) "—" else percentage, maxLines = 1,
                style = TextStyle(color = accent, fontSize = if (compact) 32.sp else 36.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
            )
            Text(text = if (noPlan) "بداية جديدة" else "من الختمة", maxLines = 1, style = TextStyle(color = secondary, fontSize = 9.sp, textAlign = TextAlign.Center))
          }
          Spacer(modifier = GlanceModifier.width(if (compact) 8.dp else 14.dp))
          Column(modifier = GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.End) {
            Text(text = caption, maxLines = 1, style = TextStyle(color = secondary, fontSize = 10.sp, textAlign = TextAlign.End))
            Text(
                text = reading, maxLines = 1,
                style = TextStyle(color = ink, fontSize = if (compact) 18.sp else 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End),
            )
            if (!compact && !paused && !completed) {
              Text(text = if (noPlan) "خطة تناسب وقتك" else data.wirdDetail.orEmpty(), maxLines = 1, style = TextStyle(color = secondary, fontSize = 10.sp, textAlign = TextAlign.End))
            }
          }
        }
        LinearProgressIndicator(
            progress = data.wirdProgressValue.toFloat(), modifier = GlanceModifier.fillMaxWidth().height(5.dp),
            color = accent, backgroundColor = mishkatWidgetColor(prefs, day = Color(0xFFD5E5DC), night = Color(0xFF355449)),
        )
        Row(modifier = GlanceModifier.fillMaxWidth().padding(top = 5.dp)) {
          Text(
              modifier = GlanceModifier.defaultWeight(), text = if (noPlan) "خطوة صغيرة كل يوم" else data.wirdRemainingPages, maxLines = 1,
              style = TextStyle(color = secondary, fontSize = if (compact) 9.sp else 10.sp),
          )
          Spacer(modifier = GlanceModifier.width(6.dp))
          Text(
              modifier = GlanceModifier.defaultWeight(), text = if (noPlan) "ابدأ من حيث تحب" else data.wirdCompletedPages, maxLines = 1,
              style = TextStyle(color = accent, fontSize = if (compact) 9.sp else 10.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.End),
          )
        }
      }
    }
  }
}

data class WirdWidgetData(
    val wirdProgressValue: Double = 0.0,
    val wirdCompletedPages: String = "",
    val wirdRemainingPages: String = "",
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
                wirdProgressValue = mishkatWidgetDouble(prefs, "${PREFERENCES_PREFIX}.wirdProgressValue", 0.0).coerceIn(0.0, 1.0),
                wirdCompletedPages = prefs.getString("${PREFERENCES_PREFIX}.wirdCompletedPages", "") ?: "",
                wirdRemainingPages = prefs.getString("${PREFERENCES_PREFIX}.wirdRemainingPages", "") ?: "",
                wirdName = prefs.getString("${PREFERENCES_PREFIX}.wirdName", "رحلتك مع القرآن"),
                wirdPages = prefs.getString("${PREFERENCES_PREFIX}.wirdPages", "ابدأ ختمتك الأولى"),
                wirdDetail = prefs.getString("${PREFERENCES_PREFIX}.wirdDetail", "حدّد خطتك ليظهر وردك هنا"),
                wirdProgress = prefs.getString("${PREFERENCES_PREFIX}.wirdProgress", "خطوة صغيرة كل يوم"),
                wirdAction = prefs.getString("${PREFERENCES_PREFIX}.wirdAction", "اضغط لإنشاء خطة"),
            )
        }

        fun previewFromPreferences(prefs: android.content.SharedPreferences): WirdWidgetData {
            return WirdWidgetData(
                wirdProgressValue = mishkatWidgetDouble(prefs, "${PREFERENCES_PREFIX}.wirdProgressValue", (41.0 / 604.0)).coerceIn(0.0, 1.0),
                wirdCompletedPages = prefs.getString("${PREFERENCES_PREFIX}.wirdCompletedPages", "أنجزت ٤١ صفحة") ?: "",
                wirdRemainingPages = prefs.getString("${PREFERENCES_PREFIX}.wirdRemainingPages", "باقي ٥٦٣ صفحة") ?: "",
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

/** Small monochrome book mark, tinted by the widget's live day/night palette. */
private fun wirdBookBitmap(): Bitmap {
    val bitmap = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }
    val book = Path().apply {
        moveTo(24f, 12f)
        cubicTo(18f, 7f, 10f, 6f, 4f, 8f)
        lineTo(4f, 36f)
        cubicTo(11f, 34f, 18f, 35f, 24f, 40f)
        cubicTo(30f, 35f, 37f, 34f, 44f, 36f)
        lineTo(44f, 8f)
        cubicTo(38f, 6f, 30f, 7f, 24f, 12f)
        lineTo(24f, 40f)
    }
    canvas.drawPath(book, paint)
    return bitmap
}
