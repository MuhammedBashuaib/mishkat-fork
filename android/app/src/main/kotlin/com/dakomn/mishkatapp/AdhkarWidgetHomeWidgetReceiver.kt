// GENERATED CODE - DO NOT MODIFY BY HAND
package com.dakomn.mishkatapp

import android.content.Context
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

class AdhkarWidgetHomeWidgetReceiver : HomeWidgetGlanceWidgetReceiver<AdhkarWidgetHomeWidget>() {
  override val glanceAppWidget = AdhkarWidgetHomeWidget()

  override fun previewFingerprint(context: Context): String =
      glanceAppWidget.previewFingerprint(context)
}
