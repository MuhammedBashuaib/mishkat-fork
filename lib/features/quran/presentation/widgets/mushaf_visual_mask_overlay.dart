import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/mushaf_layout_models.dart';
import '../services/mushaf_coordinate_mapper.dart';

/// Geometry masking mode for Visual Recall overlays.
enum MaskBoundaryMode {
  /// Raw axis-aligned bounding rectangles directly from layout metadata.
  raw,

  /// Micro-inset (0.5 SVG points contraction on shared line boundaries).
  microInset,

  /// Subtle rounded corners (R = 3.0 pt) for calligraphic visual softening.
  rounded,
}

/// Custom painter that translates SVG viewBox Ayah geometry segments into solid opaque mask fills.
///
/// Supports both [AyahRectSegment] (line corridors on Pages 3..604) and [AyahPolygonSegment]
/// (calligraphic boundary paths on Pages 1..2).
class VisualMaskPainter extends CustomPainter {
  const VisualMaskPainter({
    required this.maskedAyahs,
    this.currentAyah,
    required this.viewBox,
    this.mapper = const MushafCoordinateMapper(),
    required this.maskColor,
    this.currentNumberOutlineColor,
    this.preserveAyahNumbers = true,
    this.boundaryMode = MaskBoundaryMode.raw,
  });

  /// The list of Ayah geometry bounds on the current page to be visually masked.
  final List<AyahBounds> maskedAyahs;

  /// The active Ayah currently in focus, if any.
  final AyahBounds? currentAyah;

  /// Native SVG viewBox rect for the page.
  final Rect viewBox;

  /// Coordinate mapper service translating viewBox units to local canvas points.
  final MushafCoordinateMapper mapper;

  /// Solid opaque color used to conceal the Quranic text (matches page canvas/ink).
  final Color maskColor;

  /// Outline drawn around the current Ayah number so the next reveal target is clear.
  final Color? currentNumberOutlineColor;

  /// Draws an independent Ayah-number medallion above the opaque text mask.
  final bool preserveAyahNumbers;

  /// Boundary adjustment mode.
  final MaskBoundaryMode boundaryMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || viewBox.isEmpty || maskedAyahs.isEmpty) return;

    final maskPaint = Paint()
      ..color = maskColor
      ..style = PaintingStyle.fill;

    for (final ayah in maskedAyahs) {
      _paintAyahGeometry(canvas, size, ayah, maskPaint);
    }

    // Numbers must not be holes through the mask: a guessed cutout exposes
    // neighboring letters, particularly around multi-line opening-page Ayahs.
    if (preserveAyahNumbers) {
      for (final ayah in maskedAyahs) {
        final window = ayahNumberWindow(ayah, size);
        if (window == null) continue;
        final ink = maskColor.computeLuminance() > .5
            ? const Color(0xFF231F20)
            : const Color(0xFFECE5D8);
        canvas.drawOval(window, maskPaint);
        canvas.drawOval(
          window,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
        final number = ayah.ayah
            .toString()
            .split('')
            .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
            .join();
        final label = TextPainter(
          text: TextSpan(
            text: number,
            style: TextStyle(
              color: ink,
              fontFamily: 'Cairo',
              fontSize: window.height * (number.length >= 3 ? .38 : .5),
              height: 1,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        label.paint(
          canvas,
          window.center - Offset(label.width / 2, label.height / 2),
        );
        label.dispose();
      }
    }

    final focusedAyah = currentAyah;
    final outlineColor = currentNumberOutlineColor;
    if (preserveAyahNumbers &&
        focusedAyah != null &&
        outlineColor != null &&
        maskedAyahs.any((ayah) => ayah.globalAyah == focusedAyah.globalAyah)) {
      final numberWindow = ayahNumberWindow(focusedAyah, size);
      if (numberWindow != null) {
        final outlinePaint = Paint()
          ..color = outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawOval(numberWindow.inflate(2.5), outlinePaint);
      }
    }
  }

  /// Returns the badge bounds at the source SVG's exact Ayah-number center.
  @visibleForTesting
  Rect? ayahNumberWindow(AyahBounds ayah, Size size) {
    if (ayah.segments.isEmpty || size.isEmpty || viewBox.isEmpty) return null;

    if (ayah.numberCenter case final Offset center) {
      final diameter = ayah.page <= 2 ? 14.0 : 20.0;
      return mapper.viewBoxRectToLocal(
        viewBoxRect: Rect.fromCenter(
          center: center,
          width: diameter,
          height: diameter,
        ),
        contentSize: size,
        viewBox: viewBox,
        padding: EdgeInsets.zero,
      );
    }

    // Compatibility with manually constructed/older layout fixtures.
    final finalSegment = ayah.segments.last;
    final localBounds = mapper.viewBoxRectToLocal(
      viewBoxRect: finalSegment.bounds,
      contentSize: size,
      viewBox: viewBox,
      padding: EdgeInsets.zero,
    );
    if (localBounds.isEmpty) return null;

    final diameter = (localBounds.height * .72).clamp(14.0, 30.0).toDouble();
    final centerX = (localBounds.left + diameter / 2).clamp(
      localBounds.left,
      localBounds.right,
    );
    final center = Offset(centerX.toDouble(), localBounds.center.dy);
    return Rect.fromCenter(center: center, width: diameter, height: diameter);
  }

  void _paintAyahGeometry(
    Canvas canvas,
    Size size,
    AyahBounds ayah,
    Paint paint,
  ) {
    for (var index = 0; index < ayah.segments.length; index++) {
      final segment = ayah.segments[index];
      Path localPath;

      if (segment is AyahRectSegment) {
        Rect effectiveRect = segment.rect;

        if (boundaryMode == MaskBoundaryMode.microInset) {
          // Contract horizontal edges by 0.5 SVG points if not full-width
          final isLeftEdge = effectiveRect.left <= (viewBox.left + 2.0);
          final isRightEdge = effectiveRect.right >= (viewBox.right - 2.0);
          final insetLeft = isLeftEdge ? 0.0 : 0.5;
          final insetRight = isRightEdge ? 0.0 : 0.5;
          effectiveRect = Rect.fromLTRB(
            effectiveRect.left + insetLeft,
            effectiveRect.top,
            effectiveRect.right - insetRight,
            effectiveRect.bottom,
          );
        }

        final localRect = mapper.viewBoxRectToLocal(
          viewBoxRect: effectiveRect,
          contentSize: size,
          viewBox: viewBox,
          padding: EdgeInsets
              .zero, // Exact 1:1 match with SvgPicture.asset inside the Stack
        );

        if (boundaryMode == MaskBoundaryMode.rounded) {
          localPath = Path()
            ..addRRect(
              RRect.fromRectAndRadius(localRect, const Radius.circular(3.0)),
            );
        } else {
          localPath = Path()..addRect(localRect);
        }
      } else if (segment is AyahPolygonSegment) {
        localPath = mapper.viewBoxPathToLocal(
          points: segment.points,
          contentSize: size,
          viewBox: viewBox,
          padding: EdgeInsets
              .zero, // Exact 1:1 match with SvgPicture.asset inside the Stack
        );
      } else {
        continue;
      }

      canvas.drawPath(localPath, paint);
      // Adjacent polygon corridors contain subpixel gaps in the source layout.
      // Seal their edges so antialiased strokes cannot show through as hints.
      canvas.drawPath(
        localPath,
        Paint()
          ..color = maskColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant VisualMaskPainter oldDelegate) {
    return oldDelegate.maskColor != maskColor ||
        oldDelegate.viewBox != viewBox ||
        oldDelegate.boundaryMode != boundaryMode ||
        oldDelegate.currentAyah != currentAyah ||
        oldDelegate.currentNumberOutlineColor != currentNumberOutlineColor ||
        oldDelegate.preserveAyahNumbers != preserveAyahNumbers ||
        !listEquals(oldDelegate.maskedAyahs, maskedAyahs);
  }
}

/// Repaint-isolated widget rendering the solid opaque visual mask layer over a Mushaf page.
class MushafVisualMaskOverlay extends StatelessWidget {
  const MushafVisualMaskOverlay({
    super.key,
    required this.maskedAyahs,
    this.currentAyah,
    required this.viewBox,
    this.mapper = const MushafCoordinateMapper(),
    required this.maskColor,
    this.currentNumberOutlineColor,
    this.preserveAyahNumbers = true,
    this.boundaryMode = MaskBoundaryMode.raw,
  });

  final List<AyahBounds> maskedAyahs;
  final AyahBounds? currentAyah;
  final Rect viewBox;
  final MushafCoordinateMapper mapper;
  final Color maskColor;
  final Color? currentNumberOutlineColor;
  final bool preserveAyahNumbers;
  final MaskBoundaryMode boundaryMode;

  @override
  Widget build(BuildContext context) {
    if (maskedAyahs.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: VisualMaskPainter(
            maskedAyahs: maskedAyahs,
            currentAyah: currentAyah,
            viewBox: viewBox,
            mapper: mapper,
            maskColor: maskColor,
            currentNumberOutlineColor: currentNumberOutlineColor,
            preserveAyahNumbers: preserveAyahNumbers,
            boundaryMode: boundaryMode,
          ),
        ),
      ),
    );
  }
}
