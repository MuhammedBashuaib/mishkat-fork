import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Premium Islamic Qibla Compass Widget.
///
/// Features:
/// - Distinctive visual identity: Clear separation between True North and Qibla.
/// - Stylized golden Kaaba indicator at calculated bearing.
/// - Rotating compass dial with Cardinal letters (ش, ق, ج, غ) and degree marks.
/// - Top phone direction chevron target marker at 12 o'clock.
/// - Seamless shortest-arc angle animation (no 359° -> 0° jumps).
/// - Dynamic alignment glow and celebration state when facing Kaaba.
/// - Subtle authentic Islamic geometric rosette watermark on the dial.
/// - Responsive scaling supporting compact 320px phones up to tablets.
class MishkatCompassWidget extends StatefulWidget {
  const MishkatCompassWidget({
    super.key,
    required this.heading,
    required this.bearing,
    required this.aligned,
    this.accuracy,
    this.isListening = true,
  });

  final double? heading;
  final double? bearing;
  final bool aligned;
  final double? accuracy;
  final bool isListening;

  @override
  State<MishkatCompassWidget> createState() => _MishkatCompassWidgetState();
}

class _MishkatCompassWidgetState extends State<MishkatCompassWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _headingAnimation;

  double _currentContinuousHeading = 0.0;

  @override
  void initState() {
    super.initState();
    final initialHeading = widget.heading ?? 0.0;
    _currentContinuousHeading = initialHeading;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _headingAnimation =
        Tween<double>(begin: initialHeading, end: initialHeading).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
  }

  @override
  void didUpdateWidget(covariant MishkatCompassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newHeading = widget.heading ?? 0.0;
    if (widget.heading != null && widget.heading != oldWidget.heading) {
      // Calculate shortest circular difference to avoid 359° -> 0° spinning glitches
      final currentNormalized = ((_currentContinuousHeading % 360) + 360) % 360;
      final delta = ((newHeading - currentNormalized + 540) % 360) - 180;

      final start = _currentContinuousHeading;
      final end = _currentContinuousHeading + delta;

      _headingAnimation = Tween<double>(begin: start, end: end).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
      );

      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? context.mishkat.primary
        : context.mishkat.primary;
    final goldColor = context.mishkat.gold;
    final surfaceColor = isDark ? context.mishkat.surface : Colors.white;
    final borderColor = isDark
        ? context.mishkat.borderSubtle
        : context.mishkat.border;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsively bound compass diameter: safe for 320px screens and tablet layouts
        final availableSize = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final diameter = availableSize.isFinite && availableSize > 0
            ? math.min(availableSize, 310.0)
            : 280.0;

        return Center(
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: AnimatedBuilder(
              animation: _headingAnimation,
              builder: (context, child) {
                final animatedHeading = widget.heading != null
                    ? _headingAnimation.value
                    : 0.0;
                _currentContinuousHeading = animatedHeading;

                return CustomPaint(
                  size: Size(diameter, diameter),
                  painter: _CompassPainter(
                    heading: animatedHeading,
                    bearing: widget.bearing ?? 0.0,
                    aligned: widget.aligned,
                    isListening: widget.isListening && widget.heading != null,
                    primary: primaryColor,
                    gold: goldColor,
                    surface: surfaceColor,
                    border: borderColor,
                    text: textColor,
                    isDark: isDark,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({
    required this.heading,
    required this.bearing,
    required this.aligned,
    required this.isListening,
    required this.primary,
    required this.gold,
    required this.surface,
    required this.border,
    required this.text,
    required this.isDark,
  });

  final double heading;
  final double bearing;
  final bool aligned;
  final bool isListening;
  final Color primary;
  final Color gold;
  final Color surface;
  final Color border;
  final Color text;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.shortestSide / 2 - 4;
    final dialRadius = outerRadius - 16;

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Outer Bezel & Elevation Rings
    // ─────────────────────────────────────────────────────────────────────────
    // Outer glow / shadow when aligned
    if (aligned && isListening) {
      final glowPaint = Paint()
        ..color = primary.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, outerRadius + 2, glowPaint);
    }

    // Outer subtle ring
    final outerBezelPaint = Paint()
      ..color = aligned && isListening
          ? primary.withValues(alpha: 0.3)
          : (isDark ? border : const Color(0xFFE2EBE5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = aligned && isListening ? 3 : 1.5;
    canvas.drawCircle(center, outerRadius, outerBezelPaint);

    // Inner dial background
    final dialBgPaint = Paint()
      ..color = surface
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius - 1, dialBgPaint);

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Subtle Islamic Geometric Rosette Watermark
    // ─────────────────────────────────────────────────────────────────────────
    _drawIslamicGeometricWatermark(canvas, center, dialRadius * 0.72);

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Dial Tick Marks & Degrees (Rotates with -heading)
    // ─────────────────────────────────────────────────────────────────────────
    // The dial rotates by -heading so that True North stays pointed to real North
    final effectiveHeading = isListening ? heading : 0.0;

    for (var degree = 0; degree < 360; degree += 2) {
      final isMajor = degree % 30 == 0;
      final isMedium = degree % 10 == 0 && !isMajor;

      // -90 is canvas offset so 0° (North) is at 12 o'clock
      final angle = (degree - effectiveHeading - 90) * math.pi / 180;

      final tickLength = isMajor ? 12.0 : (isMedium ? 7.0 : 3.5);
      final start =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (dialRadius - tickLength);
      final end =
          center + Offset(math.cos(angle), math.sin(angle)) * dialRadius;

      Color tickColor;
      if (degree == 0) {
        tickColor = primary; // North tick
      } else if (isMajor) {
        tickColor = text.withValues(alpha: 0.75);
      } else if (isMedium) {
        tickColor = text.withValues(alpha: 0.4);
      } else {
        tickColor = text.withValues(alpha: 0.15);
      }

      final tickPaint = Paint()
        ..color = tickColor
        ..strokeWidth = isMajor ? 2.0 : (isMedium ? 1.2 : 0.8)
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(start, end, tickPaint);

      // Degree labels at 30° increments (skip cardinal 0, 90, 180, 270)
      if (isMajor && degree % 90 != 0) {
        final labelPos =
            center +
            Offset(math.cos(angle), math.sin(angle)) * (dialRadius - 22);
        _drawCenteredText(
          canvas: canvas,
          text: '$degree°',
          position: labelPos,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: text.withValues(alpha: 0.5),
            fontFamily: 'Cairo',
          ),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Cardinal Direction Labels (ش, ق, ج, غ)
    // ─────────────────────────────────────────────────────────────────────────
    final cardinals = <int, String>{
      0: 'ش', // North
      90: 'ق', // East
      180: 'ج', // South
      270: 'غ', // West
    };

    for (final entry in cardinals.entries) {
      final deg = entry.key;
      final label = entry.value;
      final angle = (deg - effectiveHeading - 90) * math.pi / 180;
      final labelPos =
          center + Offset(math.cos(angle), math.sin(angle)) * (dialRadius - 25);

      final isNorth = deg == 0;
      _drawCenteredText(
        canvas: canvas,
        text: label,
        position: labelPos,
        style: TextStyle(
          fontSize: isNorth ? 16 : 13,
          fontWeight: isNorth ? FontWeight.w900 : FontWeight.w700,
          color: isNorth ? primary : text.withValues(alpha: 0.8),
          fontFamily: 'Cairo',
        ),
      );

      // True North Triangular Badge at 0°
      if (isNorth) {
        final triTip =
            center +
            Offset(math.cos(angle), math.sin(angle)) * (dialRadius - 2);
        final triBase1 =
            center +
            Offset(math.cos(angle - 0.08), math.sin(angle - 0.08)) *
                (dialRadius - 12);
        final triBase2 =
            center +
            Offset(math.cos(angle + 0.08), math.sin(angle + 0.08)) *
                (dialRadius - 12);

        final northPath = Path()
          ..moveTo(triTip.dx, triTip.dy)
          ..lineTo(triBase1.dx, triBase1.dy)
          ..lineTo(triBase2.dx, triBase2.dy)
          ..close();

        canvas.drawPath(
          northPath,
          Paint()
            ..color = primary
            ..style = PaintingStyle.fill,
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Distinct Qibla Needle & Kaaba Emblem (At bearing angle)
    // ─────────────────────────────────────────────────────────────────────────
    final qiblaAngle = (bearing - effectiveHeading - 90) * math.pi / 180;
    _drawQiblaNeedle(canvas, center, qiblaAngle, dialRadius);

    // ─────────────────────────────────────────────────────────────────────────
    // 6. Central Hub Disc (Concentric Rings + Pivot)
    // ─────────────────────────────────────────────────────────────────────────
    _drawCenterHub(canvas, center, dialRadius);

    // ─────────────────────────────────────────────────────────────────────────
    // 7. Top Phone Orientation Target Indicator (Fixed at 12 o'clock)
    // ─────────────────────────────────────────────────────────────────────────
    _drawTopTargetIndicator(canvas, center, outerRadius);
  }

  /// Draws a subtle, elegant 8-point Islamic rosette watermark in the dial center.
  void _drawIslamicGeometricWatermark(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final watermarkPaint = Paint()
      ..color = (isDark ? primary : const Color(0xFF0B3D32)).withValues(
        alpha: 0.045,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Concentric subtle circles
    canvas.drawCircle(center, radius, watermarkPaint);
    canvas.drawCircle(center, radius * 0.65, watermarkPaint);

    // Two interlocked squares forming an 8-pointed Islamic star
    final half = radius * 0.55;
    final r1 = Rect.fromCenter(
      center: center,
      width: half * 2,
      height: half * 2,
    );
    canvas.drawRect(r1, watermarkPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi / 4);
    final r2 = Rect.fromCenter(
      center: Offset.zero,
      width: half * 2,
      height: half * 2,
    );
    canvas.drawRect(r2, watermarkPaint);
    canvas.restore();
  }

  /// Draws the distinctive golden/emerald Qibla needle and Kaaba marker.
  void _drawQiblaNeedle(
    Canvas canvas,
    Offset center,
    double angle,
    double dialRadius,
  ) {
    final needleLength = dialRadius - 38;
    final tip =
        center + Offset(math.cos(angle), math.sin(angle)) * needleLength;

    // Perpendicular angle for needle base width
    final perpAngle = angle + math.pi / 2;
    const baseWidth = 5.0;
    const midWidth = 3.0;

    final baseLeft =
        center + Offset(math.cos(perpAngle), math.sin(perpAngle)) * baseWidth;
    final baseRight =
        center - Offset(math.cos(perpAngle), math.sin(perpAngle)) * baseWidth;

    final midDist = needleLength * 0.65;
    final midLeft =
        center +
        Offset(math.cos(angle), math.sin(angle)) * midDist +
        Offset(math.cos(perpAngle), math.sin(perpAngle)) * midWidth;
    final midRight =
        center +
        Offset(math.cos(angle), math.sin(angle)) * midDist -
        Offset(math.cos(perpAngle), math.sin(perpAngle)) * midWidth;

    // Golden tapered needle
    final needleLeftPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(midLeft.dx, midLeft.dy)
      ..lineTo(tip.dx, tip.dy)
      ..close();

    final needleRightPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..lineTo(midRight.dx, midRight.dy)
      ..lineTo(tip.dx, tip.dy)
      ..close();

    // Two-tone gold shading for 3D depth
    final goldBright = aligned ? const Color(0xFFD4AF37) : gold;
    final goldDark = aligned
        ? const Color(0xFFB8860B)
        : const Color(0xFF8A6720);

    canvas.drawPath(
      needleLeftPath,
      Paint()
        ..color = goldBright
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      needleRightPath,
      Paint()
        ..color = goldDark
        ..style = PaintingStyle.fill,
    );

    // Kaaba Marker at the outer dial rim
    final kaabaCenter =
        center + Offset(math.cos(angle), math.sin(angle)) * (dialRadius - 10);

    // Glow if aligned
    if (aligned && isListening) {
      canvas.drawCircle(
        kaabaCenter,
        14,
        Paint()
          ..color = primary.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Kaaba Badge (Golden border + dark cuboid silhouette with golden Kiswah band)
    final kaabaRect = Rect.fromCenter(
      center: kaabaCenter,
      width: 18,
      height: 18,
    );
    final kaabaRRect = RRect.fromRectAndRadius(
      kaabaRect,
      const Radius.circular(3.5),
    );

    // Outer gold border of badge
    canvas.drawRRect(
      kaabaRRect,
      Paint()
        ..color = aligned ? Colors.white : goldBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Black/Dark Kaaba body
    canvas.drawRRect(
      kaabaRRect,
      Paint()
        ..color = const Color(0xFF141916)
        ..style = PaintingStyle.fill,
    );

    // Golden Kiswah stripe across Kaaba
    final bandY = kaabaCenter.dy - 3.0;
    canvas.drawLine(
      Offset(kaabaCenter.dx - 8.0, bandY),
      Offset(kaabaCenter.dx + 8.0, bandY),
      Paint()
        ..color = goldBright
        ..strokeWidth = 2.0,
    );

    // Small golden door accent
    canvas.drawRect(
      Rect.fromLTWH(kaabaCenter.dx + 1.0, kaabaCenter.dy + 1.0, 3.5, 5.0),
      Paint()..color = goldBright,
    );
  }

  /// Draws the multi-tiered center hub disc.
  void _drawCenterHub(Canvas canvas, Offset center, double dialRadius) {
    // Outer hub ring
    canvas.drawCircle(
      center,
      18,
      Paint()
        ..color = aligned && isListening
            ? primary.withValues(alpha: 0.25)
            : border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Mid disc
    canvas.drawCircle(
      center,
      16,
      Paint()
        ..color = surface
        ..style = PaintingStyle.fill,
    );

    // Center pivot cap
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = aligned && isListening
            ? primary
            : (isDark ? primary : const Color(0xFF0B3D32))
        ..style = PaintingStyle.fill,
    );

    // Inner gold pin
    canvas.drawCircle(
      center,
      3.5,
      Paint()
        ..color = gold
        ..style = PaintingStyle.fill,
    );
  }

  /// Draws the fixed top chevron target representing the phone's forward direction.
  void _drawTopTargetIndicator(
    Canvas canvas,
    Offset center,
    double outerRadius,
  ) {
    final topOffset = center - Offset(0, outerRadius + 1);

    final targetPaint = Paint()
      ..color = aligned && isListening ? primary : const Color(0xFF8C9993)
      ..style = PaintingStyle.fill;

    // Small triangular chevron pointing DOWN into the dial
    final chevronPath = Path()
      ..moveTo(topOffset.dx, topOffset.dy + 7) // tip pointing down
      ..lineTo(topOffset.dx - 6, topOffset.dy - 4)
      ..lineTo(topOffset.dx + 6, topOffset.dy - 4)
      ..close();

    canvas.drawPath(chevronPath, targetPaint);

    if (aligned && isListening) {
      // Glow behind top target when facing Qibla
      canvas.drawCircle(
        topOffset,
        8,
        Paint()
          ..color = primary.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _drawCenteredText({
    required Canvas canvas,
    required String text,
    required Offset position,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
    )..layout();

    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) =>
      oldDelegate.heading != heading ||
      oldDelegate.bearing != bearing ||
      oldDelegate.aligned != aligned ||
      oldDelegate.isListening != isListening ||
      oldDelegate.isDark != isDark;
}
