import 'package:flutter/material.dart';

import 'mushaf_line_layout.dart';

export 'mushaf_line_layout.dart' show MushafLineBand;

/// Pure coordinate mapping service translating between Screen/Widget local coordinates
/// and SVG viewBox coordinates for the King Fahd Quran Complex (KFQC) Mushaf pages.
///
/// Uses the same fit and padding as the SVG, including the fullscreen canvas
/// and custom viewBox offsets on the two opening pages.
class MushafCoordinateMapper {
  const MushafCoordinateMapper({
    this.contentPadding = defaultPadding,
    this.lineBreaks = const [],
    this.lineSeams = const [],
  });

  final EdgeInsets contentPadding;

  /// Verified horizontal cuts without ink, in original SVG coordinates.
  final List<double> lineBreaks;

  /// Verified paths through whitespace, ordered from the top of the page.
  final List<List<Offset>> lineSeams;

  /// Default padding applied inside the Mushaf page container.
  static const EdgeInsets defaultPadding = EdgeInsets.all(8);

  /// The exact source slices and destination rectangles used by the artwork.
  List<MushafLineBand> getBands({
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) => MushafLineLayout(
    contentPadding: contentPadding,
    lineBreaks: lineBreaks,
    lineSeams: lineSeams,
  ).getBands(contentSize: contentSize, viewBox: viewBox, padding: padding);

  /// Bounds of the artwork, including any added space between its lines.
  Rect getSvgDestinationRect({
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) {
    final bands = getBands(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    if (bands.isEmpty) return Rect.zero;
    return bands.first.destination.expandToInclude(bands.last.destination);
  }

  /// Converts a [localPosition] (in local coordinates of the page content widget)
  /// to native SVG viewBox coordinates.
  ///
  /// Returns `null` if the position falls outside the rendered SVG artwork.
  Offset? localToViewBox({
    required Offset localPosition,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) {
    final bands = getBands(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );

    if (bands.isEmpty) return null;
    final destRect = bands.first.destination.expandToInclude(
      bands.last.destination,
    );

    // Reject touches in empty letterbox / pillarbox margins (with small 0.5px tolerance)
    if (localPosition.dx < destRect.left - 0.5 ||
        localPosition.dx > destRect.right + 0.5 ||
        localPosition.dy < destRect.top - 0.5 ||
        localPosition.dy > destRect.bottom + 0.5) {
      return null;
    }

    final clampedX = localPosition.dx.clamp(destRect.left, destRect.right);
    final clampedY = localPosition.dy.clamp(destRect.top, destRect.bottom);
    for (final band in bands) {
      // The spaces inserted between lines contain no artwork or ayah target.
      if (clampedY < band.destination.top ||
          clampedY > band.destination.bottom) {
        continue;
      }
      final source = band.toSource(Offset(clampedX, clampedY));
      if (band.containsSource(source)) return source;
    }
    return null;
  }

  /// Converts an SVG [viewBoxCoordinate] to local widget coordinates within [contentSize].
  Offset viewBoxToLocal({
    required Offset viewBoxCoordinate,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) {
    final bands = getBands(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );

    return _viewBoxToLocal(viewBoxCoordinate, bands);
  }

  Offset _viewBoxToLocal(Offset point, List<MushafLineBand> bands) {
    if (bands.isEmpty) return Offset.zero;
    final band = bands.firstWhere(
      (band) => band.containsSource(point, includeBottom: false),
      orElse: () =>
          point.dy < bands.first.source.top ? bands.first : bands.last,
    );
    return band.toLocal(point);
  }

  /// Bounds of a mapped rectangle. Use [viewBoxRectToLocalPath] for painting
  /// geometry that may cross a seam. [preserveShape] maps its center and keeps
  /// its dimensions proportional, suitable for the circular ayah-number badge.
  Rect viewBoxRectToLocal({
    required Rect viewBoxRect,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
    bool preserveShape = false,
  }) {
    final bands = getBands(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    if (bands.isEmpty) return Rect.zero;
    if (preserveShape || bands.length == 1) {
      return Rect.fromCenter(
        center: _viewBoxToLocal(viewBoxRect.center, bands),
        width: viewBoxRect.width * bands.first.scale,
        height: viewBoxRect.height * bands.first.scale,
      );
    }
    return _transformSourcePath(
      Path()..addRect(viewBoxRect),
      bands,
    ).getBounds();
  }

  /// Maps each part of the rectangle with its own line, preserving empty gaps.
  /// [cornerRadius] is measured in destination logical pixels.
  Path viewBoxRectToLocalPath({
    required Rect viewBoxRect,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
    double cornerRadius = 0,
  }) {
    final bands = getBands(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    if (bands.isEmpty) return Path();
    final path = Path();
    if (cornerRadius > 0) {
      path.addRRect(
        RRect.fromRectAndRadius(
          viewBoxRect,
          Radius.circular(cornerRadius / bands.first.scale),
        ),
      );
    } else {
      path.addRect(viewBoxRect);
    }
    return _transformSourcePath(path, bands);
  }

  Path _transformSourcePath(Path sourcePath, List<MushafLineBand> bands) {
    final result = Path();
    final sourceBounds = sourcePath.getBounds();
    for (final band in bands) {
      if (!band.source.overlaps(sourceBounds)) continue;
      final clipped = bands.length == 1
          ? sourcePath
          : Path.combine(PathOperation.intersect, sourcePath, band.sourceClip);
      final transform = Matrix4.identity()
        ..setEntry(0, 0, band.scale)
        ..setEntry(1, 1, band.scale)
        ..setEntry(0, 3, band.destination.left - band.source.left * band.scale)
        ..setEntry(1, 3, band.destination.top - band.source.top * band.scale);
      result.addPath(clipped.transform(transform.storage), Offset.zero);
    }
    return result;
  }

  /// Converts a polygon vertex list in SVG viewBox coordinates to a local [Path].
  Path viewBoxPathToLocal({
    required List<Offset> points,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) {
    if (points.isEmpty) return Path();
    final bands = getBands(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    return _transformSourcePath(Path()..addPolygon(points, true), bands);
  }

  /// Converts a global [screenPosition] to native SVG viewBox coordinates using the
  /// given [pageRenderBox]. Automatically accounts for [InteractiveViewer] pan & zoom.
  Offset? screenToViewBox({
    required Offset screenPosition,
    required RenderBox pageRenderBox,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) {
    final localPosition = pageRenderBox.globalToLocal(screenPosition);
    return localToViewBox(
      localPosition: localPosition,
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
  }
}
