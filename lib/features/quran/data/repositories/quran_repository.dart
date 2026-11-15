import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'quran_search_repository.dart';
import '../models/quran_models.dart';

class QuranRepository {
  QuranData? _cache;
  Future<QuranData>? _pending;
  final QuranSearchRepository _searchRepository = QuranSearchRepository();

  Future<QuranData> load() {
    if (_cache case final QuranData data) return Future.value(data);
    return _pending ??= _read().whenComplete(() => _pending = null);
  }

  Future<QuranData> _read() async {
    final raw = await Future.wait([
      rootBundle.loadString('assets/data/quran.json'),
      rootBundle.loadString('assets/data/hafs-kfqc-manifest.json'),
    ]);
    final data = await compute(_parseQuran, raw);
    _cache = data;
    return data;
  }

  List<QuranSearchResult> search(
    QuranData data,
    String query, {
    int limit = 80,
  }) {
    final matches = _searchRepository.search(
      data: data,
      query: query,
      limit: limit,
    );
    return [
      for (final chapter in matches.matchedSurahs)
        QuranSearchResult(chapter: chapter),
      for (final ayah in matches.matchedAyahs)
        QuranSearchResult(
          chapter: data.chapter(ayah.surah),
          ayah: ayah.ayah,
          text: ayah.originalText,
        ),
    ].take(limit).toList(growable: false);
  }
}

QuranData _parseQuran(List<String> raw) {
  final quran = Map<String, dynamic>.from(jsonDecode(raw[0]) as Map);
  final manifest = Map<String, dynamic>.from(jsonDecode(raw[1]) as Map);
  return QuranData(
    chapters: (quran['surahs'] as List)
        .map(
          (item) =>
              QuranChapter.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    juz: (quran['juz'] as List)
        .map(
          (item) => JuzStart.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    pages: (manifest['pages'] as List)
        .map(
          (item) =>
              MushafPageInfo.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );
}
