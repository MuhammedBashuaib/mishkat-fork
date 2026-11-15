import 'package:flutter/painting.dart';

/// A horizontal slice of the original artwork and its position on the page.
/// Both axes retain the same scale; only the space between slices can grow.
class MushafLineBand {
  const MushafLineBand({
    required this.source,
    required this.destination,
    required this.sourceClip,
    required this.upperBoundary,
    required this.lowerBoundary,
  });

  final Rect source;
  final Rect destination;
  final Path sourceClip;
  final List<Offset> upperBoundary;
  final List<Offset> lowerBoundary;

  double get scale => destination.width / source.width;

  Offset toLocal(Offset point) => Offset(
    destination.left + (point.dx - source.left) * scale,
    destination.top + (point.dy - source.top) * scale,
  );

  Offset toSource(Offset point) => Offset(
    source.left + (point.dx - destination.left) / scale,
    source.top + (point.dy - destination.top) / scale,
  );

  bool containsSource(Offset point, {bool includeBottom = true}) {
    const tolerance = 1e-7;
    if (point.dx < source.left - tolerance ||
        point.dx > source.right + tolerance) {
      return false;
    }
    final top = boundaryY(upperBoundary, point.dx);
    final bottom = boundaryY(lowerBoundary, point.dx);
    return point.dy >= top - tolerance &&
        (includeBottom ? point.dy <= bottom + tolerance : point.dy < bottom);
  }

  /// Linear interpolation on a monotone-x seam, including its edge points.
  static double boundaryY(List<Offset> boundary, double x) {
    if (x <= boundary.first.dx) return boundary.first.dy;
    if (x >= boundary.last.dx) return boundary.last.dy;
    var low = 0;
    var high = boundary.length - 1;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (boundary[middle].dx <= x) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final left = boundary[low];
    final right = boundary[high];
    return left.dy +
        (right.dy - left.dy) * (x - left.dx) / (right.dx - left.dx);
  }
}

/// Fits a printed page while distributing spare height between safe line cuts.
///
/// [lineBreaks] are absolute y coordinates in the original SVG viewBox. They
/// must be taken from horizontal strips without ink, including diacritics.
/// Opening pages or any page without verified cuts retain the original fit.
class MushafLineLayout {
  const MushafLineLayout({
    this.lineBreaks = const [],
    this.lineSeams = const [],
    this.contentPadding = EdgeInsets.zero,
  });

  final List<double> lineBreaks;

  /// Paths through empty space between lines, with increasing absolute x.
  final List<List<Offset>> lineSeams;
  final EdgeInsets contentPadding;

  List<MushafLineBand> getBands({
    required Size contentSize,
    required Rect viewBox,
    EdgeInsets? padding,
  }) {
    final inset = padding ?? contentPadding;
    final width = (contentSize.width - inset.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final height = (contentSize.height - inset.vertical).clamp(
      0.0,
      double.infinity,
    );
    if (viewBox.isEmpty ||
        !viewBox.isFinite ||
        width <= 0 ||
        height <= 0 ||
        !width.isFinite ||
        !height.isFinite) {
      return const [];
    }

    final available = Rect.fromLTWH(inset.left, inset.top, width, height);
    final fitted = applyBoxFit(BoxFit.contain, viewBox.size, available.size);
    final original = Alignment.center.inscribe(fitted.destination, available);
    final cuts =
        lineBreaks
            .where(
              (cut) =>
                  cut.isFinite && cut > viewBox.top && cut < viewBox.bottom,
            )
            .toSet()
            .toList()
          ..sort();
    final scale = original.width / viewBox.width;
    final extraHeight = (available.height - original.height).clamp(
      0.0,
      double.infinity,
    );
    List<Offset> horizontal(double y) => [
      Offset(viewBox.left, y),
      Offset(viewBox.right, y),
    ];
    final seams = lineSeams.isNotEmpty
        ? lineSeams
        : [for (final cut in cuts) horizontal(cut)];
    if (seams.isEmpty || extraHeight < .001) {
      return [
        MushafLineBand(
          source: viewBox,
          destination: original,
          sourceClip: Path()..addRect(viewBox),
          upperBoundary: horizontal(viewBox.top),
          lowerBoundary: horizontal(viewBox.bottom),
        ),
      ];
    }
    final gap = extraHeight / seams.length;
    final top = available.top;
    final boundaries = [
      horizontal(viewBox.top),
      ...seams,
      horizontal(viewBox.bottom),
    ];

    final bands = <MushafLineBand>[];
    for (var index = 0; index < boundaries.length - 1; index++) {
      final upper = boundaries[index];
      final lower = boundaries[index + 1];
      final clip = Path()..addPolygon([...upper, ...lower.reversed], true);
      final bounds = clip.getBounds();
      bands.add(
        MushafLineBand(
          source: bounds,
          sourceClip: clip,
          upperBoundary: upper,
          lowerBoundary: lower,
          destination: Rect.fromLTWH(
            original.left + (bounds.left - viewBox.left) * scale,
            top + (bounds.top - viewBox.top) * scale + index * gap,
            bounds.width * scale,
            bounds.height * scale,
          ),
        ),
      );
    }
    return bands;
  }
}
