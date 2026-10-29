import 'package:flutter/material.dart';

import '../../data/models/mushaf_layout_models.dart';
import '../services/mushaf_coordinate_mapper.dart';

/// Translucent visual highlight overlay rendering selected, playing, and bookmarked Ayah geometry on a Mushaf page.
///
/// Supports distinct visual styles for:
/// - [selectedAyah]: User tap/selection focus (soft emerald / Islamic green).
/// - [playingAyah]: Real-time audio recitation focus (warm amber / golden highlight).
/// - [bookmarkedAyahs]: Subtle vertical golden accent ribbon on the Ayah's margin.
/// - Unified highlight: When the selected Ayah is also actively playing audio.
class MushafAyahOverlay extends StatelessWidget {
  const MushafAyahOverlay({
    super.key,
    this.selectedAyah,
    this.playingAyah,
    this.bookmarkedAyahs = const [],
    required this.viewBox,
    this.mapper = const MushafCoordinateMapper(),
  });

  final AyahBounds? selectedAyah;
  final AyahBounds? playingAyah;
  final List<AyahBounds> bookmarkedAyahs;
  final Rect viewBox;
  final MushafCoordinateMapper mapper;

  @override
  Widget build(BuildContext context) {
    if (selectedAyah == null &&
        playingAyah == null &&
        bookmarkedAyahs.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Selection highlight: soft Islamic green
    final selectionColor = isDark
        ? const Color(0x524CAF50) // ~32% opacity warm emerald green
        : const Color(0x38107C41); // ~22% opacity soft Islamic green

    // Audio playback highlight: warm amber / gold
    final playbackColor = isDark
        ? const Color(0x52D97706) // ~32% opacity warm gold/amber
        : const Color(0x3DF59E0B); // ~24% opacity soft amber

    // Unified highlight when selected == playing: enriched golden emerald
    final unifiedColor = isDark
        ? const Color(0x60059669)
        : const Color(0x450D9488);

    return IgnorePointer(
      child: CustomPaint(
        painter: MushafAyahHighlightPainter(
          selectedAyah: selectedAyah,
          playingAyah: playingAyah,
          bookmarkedAyahs: bookmarkedAyahs,
          viewBox: viewBox,
          mapper: mapper,
          selectionColor: selectionColor,
          playbackColor: playbackColor,
          unifiedColor: unifiedColor,
          isDark: isDark,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Custom painter that translates SVG viewBox Ayah geometry segments into local canvas drawing calls.
class MushafAyahHighlightPainter extends CustomPainter {
  const MushafAyahHighlightPainter({
    this.selectedAyah,
    this.playingAyah,
    this.bookmarkedAyahs = const [],
    required this.viewBox,
    required this.mapper,
    required this.selectionColor,
    required this.playbackColor,
    required this.unifiedColor,
    required this.isDark,
  });

  final AyahBounds? selectedAyah;
  final AyahBounds? playingAyah;
  final List<AyahBounds> bookmarkedAyahs;
  final Rect viewBox;
  final MushafCoordinateMapper mapper;
  final Color selectionColor;
  final Color playbackColor;
  final Color unifiedColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || viewBox.isEmpty) return;

    // 1. Subtle bookmark indicator tabs on the right edge of bookmarked Ayahs
    for (final bookmarked in bookmarkedAyahs) {
      _paintBookmarkIndicator(canvas, size, bookmarked);
    }

    final isUnified =
        selectedAyah != null &&
        playingAyah != null &&
        selectedAyah!.globalAyah == playingAyah!.globalAyah;

    if (isUnified) {
      final fillPaint = Paint()
        ..color = unifiedColor
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = isDark ? const Color(0x99F59E0B) : const Color(0x88D97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      _paintAyah(canvas, size, selectedAyah!, fillPaint, strokePaint);
      return;
    }

    if (playingAyah != null) {
      final fillPaint = Paint()
        ..color = playbackColor
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = isDark ? const Color(0x80F59E0B) : const Color(0x60D97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      _paintAyah(canvas, size, playingAyah!, fillPaint, strokePaint);
    }

    if (selectedAyah != null) {
      final fillPaint = Paint()
        ..color = selectionColor
        ..style = PaintingStyle.fill;
      _paintAyah(canvas, size, selectedAyah!, fillPaint, null);
    }
  }

  void _paintBookmarkIndicator(Canvas canvas, Size size, AyahBounds ayah) {
    if (ayah.segments.isEmpty) return;
    final first = ayah.segments.first;
    final Rect localRect;
    if (first is AyahRectSegment) {
      localRect = mapper.viewBoxRectToLocal(
        viewBoxRect: first.rect,
        contentSize: size,
        viewBox: viewBox,
      );
    } else if (first is AyahPolygonSegment) {
      localRect = mapper
          .viewBoxPathToLocal(
            points: first.points,
            contentSize: size,
            viewBox: viewBox,
          )
          .getBounds();
    } else {
      localRect = mapper.viewBoxRectToLocal(
        viewBoxRect: ayah.bounds,
        contentSize: size,
        viewBox: viewBox,
      );
    }

    if (localRect.isEmpty || localRect.height < 4) return;

    final barColor = isDark
        ? const Color(0xFFFFD54F) // warm bright gold in dark mode
        : const Color(0xFFC59B27); // deep rich gold in light mode

    final barPaint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    // A subtle 3.5px vertical bookmark strip on the right edge (RTL start) of the ayah's first line
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (localRect.right - 3.5).clamp(0.0, size.width - 3.5),
        localRect.top + 2,
        3.5,
        (localRect.height - 4).clamp(4.0, 100.0),
      ),
      const Radius.circular(1.5),
    );

    canvas.drawRRect(barRect, barPaint);
  }

  void _paintAyah(
    Canvas canvas,
    Size size,
    AyahBounds ayah,
    Paint fillPaint,
    Paint? strokePaint,
  ) {
    for (final segment in ayah.segments) {
      if (segment is AyahRectSegment) {
        final localRect = mapper.viewBoxRectToLocal(
          viewBoxRect: segment.rect,
          contentSize: size,
          viewBox: viewBox,
        );
        final rrect = RRect.fromRectAndRadius(
          localRect,
          const Radius.circular(3),
        );
        canvas.drawRRect(rrect, fillPaint);
        if (strokePaint != null) {
          canvas.drawRRect(rrect, strokePaint);
        }
      } else if (segment is AyahPolygonSegment) {
        final localPath = mapper.viewBoxPathToLocal(
          points: segment.points,
          contentSize: size,
          viewBox: viewBox,
        );
        canvas.drawPath(localPath, fillPaint);
        if (strokePaint != null) {
          canvas.drawPath(localPath, strokePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant MushafAyahHighlightPainter oldDelegate) {
    return oldDelegate.selectedAyah != selectedAyah ||
        oldDelegate.playingAyah != playingAyah ||
        !_listEqualsAyahs(oldDelegate.bookmarkedAyahs, bookmarkedAyahs) ||
        oldDelegate.viewBox != viewBox ||
        oldDelegate.selectionColor != selectionColor ||
        oldDelegate.playbackColor != playbackColor ||
        oldDelegate.unifiedColor != unifiedColor ||
        oldDelegate.isDark != isDark;
  }

  static bool _listEqualsAyahs(List<AyahBounds> a, List<AyahBounds> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].globalAyah != b[i].globalAyah) return false;
    }
    return true;
  }
}
