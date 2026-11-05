package com.dakomn.mishkatapp

import android.content.SharedPreferences
import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProvider

/** Shared by the customized native widgets. See docs/HOME_WIDGETS.md before regenerating. */
internal fun mishkatWidgetColor(prefs: SharedPreferences, day: Color, night: Color) =
    when (prefs.getString("widgetTheme", "system")) {
        "light" -> ColorProvider(day = day, night = day)
        "dark" -> ColorProvider(day = night, night = night)
        else -> ColorProvider(day = day, night = night)
    }

/** home_widget stores Dart doubles as their raw IEEE-754 bits in a SharedPreferences Long. */
internal fun mishkatWidgetDouble(prefs: SharedPreferences, key: String, fallback: Double): Double {
    val value = when (val raw = prefs.all[key]) {
        is Long -> if (prefs.getBoolean("home_widget.double.$key", false)) {
            java.lang.Double.longBitsToDouble(raw)
        } else raw.toDouble()
        is Number -> raw.toDouble()
        else -> fallback
    }
    return if (value.isFinite()) value else fallback
}
