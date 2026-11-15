import 'dart:convert';

import 'package:flutter/services.dart';

/// Blank separators measured from the bundled artwork, never from verse
/// hit boxes (a hit box can cover several printed lines).
class MushafLineBreaksRepository {
  static final instance = MushafLineBreaksRepository();

  Future<Map<int, List<List<Offset>>>>? _load;
  Map<int, List<List<Offset>>>? _cache;

  Future<Map<int, List<List<Offset>>>> load() async {
    if (_cache case final cached?) return cached;
    return _load ??= _read();
  }

  Future<Map<int, List<List<Offset>>>> _read() async {
    try {
      final source = await rootBundle.loadString(
        'assets/data/mushaf-line-breaks.json',
      );
      final json = jsonDecode(source) as Map<String, dynamic>;
      return _cache = Map.unmodifiable({
        for (final page in json['pages'] as List)
          page['p'] as int: List<List<Offset>>.unmodifiable(
            (page['seams'] as List).map(
              (seam) => List<Offset>.unmodifiable(
                (seam as List).map(
                  (point) => Offset(
                    (point[0] as num).toDouble(),
                    (point[1] as num).toDouble(),
                  ),
                ),
              ),
            ),
          ),
      });
    } catch (_) {
      _load = null;
      rethrow;
    }
  }
}
