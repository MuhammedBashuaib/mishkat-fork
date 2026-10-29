import 'package:flutter/material.dart';

/// Centralized Spacing Tokens for Mishkat.
/// Adheres strictly to the 4/8/12/16/20/24/32/40/48 system.
class MishkatSpacing {
  const MishkatSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double base = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 40.0;
  static const double huge = 48.0;

  // Insets shortcuts
  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 12, 16, 100);
  static const EdgeInsets pageLg = EdgeInsets.fromLTRB(20, 16, 20, 110);
  static const EdgeInsets card = EdgeInsets.all(16.0);
  static const EdgeInsets cardCompact = EdgeInsets.all(12.0);
  static const EdgeInsets button = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );
}

/// Centralized Corner Radius Tokens for Mishkat.
class MishkatRadius {
  const MishkatRadius._();

  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 20.0;
  static const double xl = 28.0;
  static const double pill = 999.0;

  static const Radius rXs = Radius.circular(xs);
  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);
  static const Radius rXl = Radius.circular(xl);

  static final BorderRadius brXs = BorderRadius.circular(xs);
  static final BorderRadius brSm = BorderRadius.circular(sm);
  static final BorderRadius brMd = BorderRadius.circular(md);
  static final BorderRadius brLg = BorderRadius.circular(lg);
  static final BorderRadius brXl = BorderRadius.circular(xl);
  static final BorderRadius brPill = BorderRadius.circular(pill);
}

/// Centralized Subtle Shadows for Mishkat.
/// Preference: Surface difference + subtle border; shadows used only where needed.
class MishkatShadows {
  const MishkatShadows._();

  static List<BoxShadow> subtle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) return const [];
    return [
      BoxShadow(
        color: const Color(0xFF0B3D32).withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> elevated(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0B3D32).withValues(alpha: 0.08),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ];
  }
}
