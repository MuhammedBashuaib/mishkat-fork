import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/mushaf_layout_models.dart';

/// Repository responsible for loading and querying Mushaf layout and Ayah geometry metadata.
///
/// Backed by the pre-computed static asset `assets/data/mushaf-layout.json`.
/// Provides sub-millisecond O(1) page/Ayah lookups and point-in-geometry hit-testing.
class MushafLayoutRepository {
  MushafLayoutRepository({this.bundle});

  static final MushafLayoutRepository instance = MushafLayoutRepository();

  final AssetBundle? bundle;
  MushafLayoutData? _cache;

  /// Returns `true` if the layout metadata has already been loaded into memory.
  bool get isLoaded => _cache != null;

  /// Returns the cached layout data or throws a [StateError] if not loaded yet.
  MushafLayoutData get data {
    final cached = _cache;
    if (cached == null) {
      throw StateError(
        'MushafLayoutRepository is not loaded. Call load() first.',
      );
    }
    return cached;
  }

  /// Loads the layout metadata from asset bundle. Cached after first load.
  Future<MushafLayoutData> load() async {
    if (_cache case final MushafLayoutData cached) return cached;

    final targetBundle = bundle ?? rootBundle;
    final jsonStr = await targetBundle.loadString(
      'assets/data/mushaf-layout.json',
    );
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final loaded = MushafLayoutData.fromJson(map);
    _cache = loaded;
    return loaded;
  }

  /// Loads layout metadata from a raw JSON string (primarily for testing and benchmarks).
  MushafLayoutData loadFromJsonString(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    final loaded = MushafLayoutData.fromJson(map);
    _cache = loaded;
    return loaded;
  }

  /// Returns the geometry metadata for [page] (1..604).
  ///
  /// Returns `null` if the repository is not loaded or if [page] is out of range.
  MushafPageGeometry? getPageGeometry(int page) {
    final cached = _cache;
    if (cached == null || page < 1 || page > cached.pages.length) {
      return null;
    }
    return cached.pages[page - 1];
  }

  /// Returns the bounds and geometry for [globalAyah] (1..6236).
  ///
  /// Returns `null` if the repository is not loaded or the index is not found.
  AyahBounds? getAyah(int globalAyah) {
    return _cache?.ayahIndex[globalAyah];
  }

  /// Performs a hit-test at [viewBoxCoordinate] (in native SVG viewBox units) on [page].
  ///
  /// Returns the matching [AyahBounds] if a hit occurs, or `null` otherwise.
  AyahBounds? findAyahAt(int page, Offset viewBoxCoordinate) {
    final pageGeom = getPageGeometry(page);
    if (pageGeom == null) return null;
    return pageGeom.findAyahAt(viewBoxCoordinate);
  }

  /// Returns the page number (1..604) containing the given [globalAyah] (1..6236).
  ///
  /// Returns `null` if not found.
  int? pageForAyah(int globalAyah) {
    return _cache?.ayahIndex[globalAyah]?.page;
  }

  /// Clears in-memory cached layout data.
  void clearCache() {
    _cache = null;
  }
}
