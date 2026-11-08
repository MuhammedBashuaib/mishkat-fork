import 'package:flutter/material.dart';

/// Typography for the bundled Unicode Quran text, independent of UI labels.
abstract final class QuranTextStyle {
  static TextStyle ayah({
    required Color color,
    double fontSize = 20,
    double height = 1.85,
  }) => TextStyle(
    // Material body/chip styles add tracking and heavier weights. Inheriting
    // those settings can separate Arabic joins or distort Quranic marks.
    inherit: false,
    fontFamily: 'QpcHafs',
    fontFamilyFallback: const ['AmiriQuran'],
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
    letterSpacing: 0,
    wordSpacing: 0,
    height: height,
    color: color,
    decoration: TextDecoration.none,
  );
}
