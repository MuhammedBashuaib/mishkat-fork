import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Base class representing a geometric segment of an Ayah.
abstract class AyahSegment extends Equatable {
  const AyahSegment();

  /// The axis-aligned bounding box enclosing this segment.
  Rect get bounds;

  /// A guaranteed interior point inside this segment, useful for hit-testing and menu anchoring.
  Offset get samplePoint;

  /// Returns true if [point] (in SVG viewBox coordinates) falls inside this segment.
  bool contains(Offset point);
}

/// An axis-aligned rectangular segment. 99.9% of Ayah geometry segments are of this type.
class AyahRectSegment extends AyahSegment {
  const AyahRectSegment(this.rect);

  final Rect rect;

  @override
  Rect get bounds => rect;

  @override
  Offset get samplePoint => rect.center;

  @override
  bool contains(Offset point) {
    return point.dx >= rect.left &&
        point.dx <= rect.right &&
        point.dy >= rect.top &&
        point.dy <= rect.bottom;
  }

  @override
  List<Object?> get props => [rect];
}

/// A polygonal segment with arbitrary vertices.
/// Present exclusively on Pages 1 and 2 for ornamental curved frame boundaries.
class AyahPolygonSegment extends AyahSegment {
  AyahPolygonSegment(List<Offset> points)
    : points = List.unmodifiable(points),
      bounds = _computeBounds(points),
      _samplePoint = _computeSamplePoint(points, _computeBounds(points));

  final List<Offset> points;

  @override
  final Rect bounds;

  final Offset _samplePoint;

  @override
  Offset get samplePoint => _samplePoint;

  static Rect _computeBounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = points[0].dx;
    double maxX = points[0].dx;
    double minY = points[0].dy;
    double maxY = points[0].dy;
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static Offset _computeSamplePoint(List<Offset> points, Rect bounds) {
    if (points.isEmpty) return bounds.center;

    // 1. If the bounding box center is inside the polygon, use it.
    if (_raycastCheck(bounds.center, points, bounds)) {
      return bounds.center;
    }

    // 2. For concave polygons (such as L-shaped lines), scan internal grid coordinates.
    for (var stepY = 1; stepY < 10; stepY++) {
      final cy = bounds.top + bounds.height * (stepY / 10.0);
      for (var stepX = 1; stepX < 10; stepX++) {
        final candidate = Offset(
          bounds.left + bounds.width * (stepX / 10.0),
          cy,
        );
        if (_raycastCheck(candidate, points, bounds)) {
          return candidate;
        }
      }
    }

    return bounds.center;
  }

  static bool _raycastCheck(Offset point, List<Offset> points, Rect bounds) {
    if (point.dx < bounds.left ||
        point.dx > bounds.right ||
        point.dy < bounds.top ||
        point.dy > bounds.bottom) {
      return false;
    }
    bool inside = false;
    final n = points.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final pi = points[i];
      final pj = points[j];
      final intersects =
          ((pi.dy > point.dy) != (pj.dy > point.dy)) &&
          (point.dx <
              (pj.dx - pi.dx) * (point.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx);
      if (intersects) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  bool contains(Offset point) => _raycastCheck(point, points, bounds);

  @override
  List<Object?> get props => [points, bounds];
}

/// Geometric bounds and hit-testing data for a single Ayah.
class AyahBounds extends Equatable {
  const AyahBounds({
    required this.globalAyah,
    required this.surah,
    required this.ayah,
    required this.page,
    required this.bounds,
    required this.segments,
    this.numberCenter,
  });

  /// The global 1-based index (1..6236).
  final int globalAyah;

  /// Surah number (1..114).
  final int surah;

  /// Ayah number within the Surah (1..N).
  final int ayah;

  /// Mushaf page number (1..604).
  final int page;

  /// Union bounding box enclosing all segments of this Ayah.
  final Rect bounds;

  /// Individual segments (lines / sub-regions) forming this Ayah.
  final List<AyahSegment> segments;

  /// Exact Ayah-number center from the source SVG, in viewBox coordinates.
  final Offset? numberCenter;

  /// A guaranteed interior point inside this Ayah, ideal for hit-testing and menu anchoring.
  Offset get samplePoint => segments.first.samplePoint;

  /// Fast sub-millisecond hit test in SVG viewBox coordinates.
  bool contains(Offset point) {
    // 1. Instant bounding box fast-reject
    if (point.dx < bounds.left ||
        point.dx > bounds.right ||
        point.dy < bounds.top ||
        point.dy > bounds.bottom) {
      return false;
    }

    // 2. Segment-level check
    for (final segment in segments) {
      if (segment.contains(point)) return true;
    }
    return false;
  }

  factory AyahBounds.fromJson(Map<String, dynamic> json, int page) {
    final b = (json['b'] as List).map((e) => (e as num).toDouble()).toList();
    final boundsRect = Rect.fromLTRB(b[0], b[1], b[2], b[3]);

    final segmentList = <AyahSegment>[];

    // Parse rect segments
    if (json['r'] case final List rects) {
      for (final r in rects) {
        final nums = (r as List).map((e) => (e as num).toDouble()).toList();
        segmentList.add(
          AyahRectSegment(Rect.fromLTRB(nums[0], nums[1], nums[2], nums[3])),
        );
      }
    }

    // Parse polygon segments (if present)
    if (json['p'] case final List polys) {
      for (final p in polys) {
        final coords = (p as List).map((e) => (e as num).toDouble()).toList();
        final points = <Offset>[];
        for (var i = 0; i < coords.length; i += 2) {
          points.add(Offset(coords[i], coords[i + 1]));
        }
        segmentList.add(AyahPolygonSegment(points));
      }
    }

    return AyahBounds(
      globalAyah: (json['g'] as num).toInt(),
      surah: (json['s'] as num).toInt(),
      ayah: (json['a'] as num).toInt(),
      page: page,
      bounds: boundsRect,
      segments: List.unmodifiable(segmentList),
      numberCenter: json['n'] is List
          ? Offset(
              (json['n'][0] as num).toDouble(),
              (json['n'][1] as num).toDouble(),
            )
          : null,
    );
  }

  @override
  List<Object?> get props => [
    globalAyah,
    surah,
    ayah,
    page,
    bounds,
    numberCenter,
  ];
}

/// Geometry metadata for a single Mushaf page.
class MushafPageGeometry extends Equatable {
  const MushafPageGeometry({
    required this.page,
    required this.viewBox,
    required this.ayahs,
  });

  /// Mushaf page number (1..604).
  final int page;

  /// Native SVG viewBox (Rect.fromLTWH).
  final Rect viewBox;

  /// List of Ayahs present on this page, ordered by globalAyah.
  final List<AyahBounds> ayahs;

  /// Finds the Ayah at the given [viewBoxCoordinate] (in native SVG viewBox units).
  /// Returns `null` if the coordinate is outside page bounds or does not hit any Ayah.
  AyahBounds? findAyahAt(Offset viewBoxCoordinate) {
    // Fast boundary check against page viewBox
    if (viewBoxCoordinate.dx < viewBox.left ||
        viewBoxCoordinate.dx > viewBox.right ||
        viewBoxCoordinate.dy < viewBox.top ||
        viewBoxCoordinate.dy > viewBox.bottom) {
      return null;
    }

    // Hit-test page Ayahs
    for (final ayah in ayahs) {
      if (ayah.contains(viewBoxCoordinate)) {
        return ayah;
      }
    }
    return null;
  }

  factory MushafPageGeometry.fromJson(Map<String, dynamic> json) {
    final pageNum = (json['p'] as num).toInt();
    final vb = (json['vb'] as List).map((e) => (e as num).toDouble()).toList();
    final viewBox = Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]);

    final rawAyahs = json['ay'] as List? ?? const [];
    final ayahs = rawAyahs
        .map(
          (e) =>
              AyahBounds.fromJson(Map<String, dynamic>.from(e as Map), pageNum),
        )
        .toList(growable: false);

    return MushafPageGeometry(page: pageNum, viewBox: viewBox, ayahs: ayahs);
  }

  @override
  List<Object?> get props => [page, viewBox, ayahs];
}

/// Complete in-memory Mushaf Layout metadata container.
class MushafLayoutData extends Equatable {
  const MushafLayoutData({
    required this.version,
    required this.coordinateSystem,
    required this.totalPages,
    required this.totalAyahs,
    required this.pages,
    required this.ayahIndex,
  });

  final int version;
  final String coordinateSystem;
  final int totalPages;
  final int totalAyahs;

  /// Pages indexed 0..603 corresponding to page numbers 1..604.
  final List<MushafPageGeometry> pages;

  /// Fast O(1) index from globalAyah (1..6236) to AyahBounds.
  final Map<int, AyahBounds> ayahIndex;

  factory MushafLayoutData.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'] as List;
    final pagesList = <MushafPageGeometry>[];
    final ayahMap = <int, AyahBounds>{};

    for (final p in rawPages) {
      final pageGeom = MushafPageGeometry.fromJson(
        Map<String, dynamic>.from(p as Map),
      );
      pagesList.add(pageGeom);
      for (final ayah in pageGeom.ayahs) {
        ayahMap[ayah.globalAyah] = ayah;
      }
    }

    return MushafLayoutData(
      version: (json['version'] as num?)?.toInt() ?? 1,
      coordinateSystem: json['coordinateSystem'] as String? ?? 'svg_viewbox',
      totalPages: (json['totalPages'] as num?)?.toInt() ?? pagesList.length,
      totalAyahs: (json['totalAyahs'] as num?)?.toInt() ?? ayahMap.length,
      pages: List.unmodifiable(pagesList),
      ayahIndex: Map.unmodifiable(ayahMap),
    );
  }

  @override
  List<Object?> get props => [
    version,
    coordinateSystem,
    totalPages,
    totalAyahs,
  ];
}
