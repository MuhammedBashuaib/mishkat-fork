import 'package:flutter/material.dart';

/// Pure coordinate mapping service translating between Screen/Widget local coordinates
/// and SVG viewBox coordinates for the King Fahd Quran Complex (KFQC) Mushaf pages.
///
/// Handles aspect-ratio preservation via [BoxFit.contain], letterboxing/pillarboxing,
/// page padding, and custom viewBox offsets (such as Pages 1-2 ornamental frames).
class MushafCoordinateMapper {
  const MushafCoordinateMapper();

  /// Default padding applied inside the Mushaf page container.
  static const EdgeInsets defaultPadding = EdgeInsets.all(8);

  /// Computes the exact destination [Rect] where the SVG artwork is rendered within [contentSize].
  Rect getSvgDestinationRect({
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets padding = defaultPadding,
  }) {
    final availableWidth = (contentSize.width - padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final availableHeight = (contentSize.height - padding.vertical).clamp(
      0.0,
      double.infinity,
    );
    final availableSize = Size(availableWidth, availableHeight);

    if (viewBox.width <= 0 || viewBox.height <= 0 || availableSize.isEmpty) {
      return Rect.zero;
    }

    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(viewBox.width, viewBox.height),
      availableSize,
    );

    return Alignment.center.inscribe(
      fitted.destination,
      Rect.fromLTWH(
        padding.left,
        padding.top,
        availableSize.width,
        availableSize.height,
      ),
    );
  }

  /// Converts a [localPosition] (in local coordinates of the page content widget)
  /// to native SVG viewBox coordinates.
  ///
  /// Returns `null` if the position falls outside the rendered SVG artwork.
  Offset? localToViewBox({
    required Offset localPosition,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets padding = defaultPadding,
  }) {
    final destRect = getSvgDestinationRect(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );

    if (destRect.isEmpty) return null;

    // Reject touches in empty letterbox / pillarbox margins (with small 0.5px tolerance)
    if (localPosition.dx < destRect.left - 0.5 ||
        localPosition.dx > destRect.right + 0.5 ||
        localPosition.dy < destRect.top - 0.5 ||
        localPosition.dy > destRect.bottom + 0.5) {
      return null;
    }

    final scaleX = destRect.width / viewBox.width;
    final scaleY = destRect.height / viewBox.height;

    final clampedX = localPosition.dx.clamp(destRect.left, destRect.right);
    final clampedY = localPosition.dy.clamp(destRect.top, destRect.bottom);

    final viewBoxX = viewBox.left + (clampedX - destRect.left) / scaleX;
    final viewBoxY = viewBox.top + (clampedY - destRect.top) / scaleY;

    return Offset(viewBoxX, viewBoxY);
  }

  /// Converts an SVG [viewBoxCoordinate] to local widget coordinates within [contentSize].
  Offset viewBoxToLocal({
    required Offset viewBoxCoordinate,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets padding = defaultPadding,
  }) {
    final destRect = getSvgDestinationRect(
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );

    final scaleX = destRect.width / viewBox.width;
    final scaleY = destRect.height / viewBox.height;

    final localX =
        destRect.left + (viewBoxCoordinate.dx - viewBox.left) * scaleX;
    final localY = destRect.top + (viewBoxCoordinate.dy - viewBox.top) * scaleY;

    return Offset(localX, localY);
  }

  /// Converts an axis-aligned [viewBoxRect] to a local widget [Rect].
  Rect viewBoxRectToLocal({
    required Rect viewBoxRect,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets padding = defaultPadding,
  }) {
    final topLeft = viewBoxToLocal(
      viewBoxCoordinate: viewBoxRect.topLeft,
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    final bottomRight = viewBoxToLocal(
      viewBoxCoordinate: viewBoxRect.bottomRight,
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Converts a polygon vertex list in SVG viewBox coordinates to a local [Path].
  Path viewBoxPathToLocal({
    required List<Offset> points,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets padding = defaultPadding,
  }) {
    final path = Path();
    if (points.isEmpty) return path;

    final first = viewBoxToLocal(
      viewBoxCoordinate: points.first,
      contentSize: contentSize,
      viewBox: viewBox,
      padding: padding,
    );
    path.moveTo(first.dx, first.dy);

    for (var i = 1; i < points.length; i++) {
      final pt = viewBoxToLocal(
        viewBoxCoordinate: points[i],
        contentSize: contentSize,
        viewBox: viewBox,
        padding: padding,
      );
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    return path;
  }

  /// Converts a global [screenPosition] to native SVG viewBox coordinates using the
  /// given [pageRenderBox]. Automatically accounts for [InteractiveViewer] pan & zoom.
  Offset? screenToViewBox({
    required Offset screenPosition,
    required RenderBox pageRenderBox,
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets padding = defaultPadding,
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
