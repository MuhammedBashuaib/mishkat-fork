import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'navigation_icons.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light([double scale = 1.0]) => _build(
    brightness: Brightness.light,
    background: MishkatColors.light.background,
    surface: MishkatColors.light.surface,
    primary: MishkatColors.light.primary,
    onSurface: MishkatColors.light.textPrimary,
    colors: MishkatColors.light,
    scale: scale,
  );

  static ThemeData dark([double scale = 1.0]) => _build(
    brightness: Brightness.dark,
    background: MishkatColors.dark.background,
    surface: MishkatColors.dark.surface,
    primary: MishkatColors.dark.primary,
    onSurface: MishkatColors.dark.textPrimary,
    colors: MishkatColors.dark,
    scale: scale,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color primary,
    required Color onSurface,
    required MishkatColors colors,
    required double scale,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: primary,
          onPrimary: brightness == Brightness.light
              ? Colors.white
              : Colors.black,
          surface: surface,
          onSurface: onSurface,
          outline: colors.border,
          outlineVariant: colors.borderSubtle,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Cairo',
      fontFamilyFallback: const [
        'Cairo',
        'SF Arabic',
        'Noto Sans Arabic',
        'Segoe UI',
        'Arial',
      ],
      extensions: <ThemeExtension<dynamic>>[colors],
    );

    return base.copyWith(
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(MishkatNavigationIcons.back),
      ),
      textTheme: base.textTheme
          .apply(
            fontFamily: 'Cairo',
            bodyColor: onSurface,
            displayColor: onSurface,
          )
          .copyWith(
            displayLarge: base.textTheme.displayLarge?.copyWith(
              fontSize: 28 * scale,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.5,
            ),
            displayMedium: base.textTheme.displayMedium?.copyWith(
              fontSize: 24 * scale,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
            displaySmall: base.textTheme.displaySmall?.copyWith(
              fontSize: 22 * scale,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            headlineLarge: base.textTheme.headlineLarge?.copyWith(
              fontSize: 22 * scale,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontSize: 20 * scale,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontSize: 18 * scale,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontSize: 16.5 * scale,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            titleSmall: base.textTheme.titleSmall?.copyWith(
              fontSize: 13.5 * scale,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            bodyLarge: base.textTheme.bodyLarge?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5 * scale,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
              height: 1.5,
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              fontSize: 13.5 * scale,
              fontWeight: FontWeight.w700,
            ),
            labelMedium: base.textTheme.labelMedium?.copyWith(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
            ),
            labelSmall: base.textTheme.labelSmall?.copyWith(
              fontSize: 11 * scale,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: 'Cairo',
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: background,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: colors.borderSubtle)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 17.5 * scale,
          fontWeight: FontWeight.w700,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: MishkatRadius.brLg,
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? colors.surfaceVariant
            : colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: MishkatRadius.brMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MishkatRadius.brMd,
          borderSide: BorderSide(color: colors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MishkatRadius.brMd,
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontSize: 13.5 * scale,
          color: colors.textMuted,
          fontWeight: FontWeight.w400,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: brightness == Brightness.light
              ? Colors.white
              : Colors.black,
          minimumSize: const Size(44, 46),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: MishkatRadius.brMd),
          textStyle: TextStyle(
            fontSize: 14 * scale,
            fontWeight: FontWeight.w700,
            fontFamily: 'Cairo',
            fontFamilyFallback: const [
              'Cairo',
              'SF Arabic',
              'Noto Sans Arabic',
            ],
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(borderRadius: MishkatRadius.brMd),
          side: BorderSide(color: colors.border, width: 1),
          textStyle: TextStyle(
            fontSize: 13.5 * scale,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
            fontFamilyFallback: const [
              'Cairo',
              'SF Arabic',
              'Noto Sans Arabic',
            ],
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: TextStyle(
            fontSize: 13 * scale,
            fontWeight: FontWeight.w700,
            fontFamily: 'Cairo',
            fontFamilyFallback: const [
              'Cairo',
              'SF Arabic',
              'Noto Sans Arabic',
            ],
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: TextStyle(
          fontSize: 13.5 * scale,
          fontWeight: FontWeight.w700,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 13.5 * scale,
          fontWeight: FontWeight.w500,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: TextStyle(
          fontSize: 17 * scale,
          fontWeight: FontWeight.w700,
          color: onSurface,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
        contentTextStyle: TextStyle(
          fontSize: 13.5 * scale,
          fontWeight: FontWeight.w400,
          color: colors.textSecondary,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(
          fontSize: 12 * scale,
          fontWeight: FontWeight.w600,
          fontFamily: 'Cairo',
          fontFamilyFallback: const ['Cairo', 'SF Arabic', 'Noto Sans Arabic'],
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.textMuted.withValues(alpha: 0.55);
          }
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          // Keep the handle visibly separate from the muted off track.
          return brightness == Brightness.light
              ? colors.surface
              : colors.textPrimary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceMuted.withValues(alpha: 0.55);
          }
          return states.contains(WidgetState.selected)
              ? primary
              : colors.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.borderSubtle.withValues(alpha: 0.55);
          }
          return states.contains(WidgetState.selected)
              ? primary
              : colors.border;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primarySoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11 * scale,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            fontFamily: 'Cairo',
            fontFamilyFallback: const [
              'Cairo',
              'SF Arabic',
              'Noto Sans Arabic',
            ],
            color: isSelected
                ? (brightness == Brightness.light
                      ? colors.primaryDark
                      : colors.primary)
                : colors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected
                ? (brightness == Brightness.light
                      ? colors.primaryDark
                      : colors.primary)
                : colors.textSecondary,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.brandDeep,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Cairo',
        ),
        shape: RoundedRectangleBorder(borderRadius: MishkatRadius.brMd),
      ),
    );
  }
}
