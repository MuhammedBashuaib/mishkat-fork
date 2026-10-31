import 'dart:convert';

import 'package:flutter/services.dart';

import 'quran_search_repository.dart';
import '../models/quran_models.dart';

class QuranRepository {
  QuranData? _cache;
  final QuranSearchRepository _searchRepository = QuranSearchRepository();

  Future<QuranData> load() async {
    if (_cache case final QuranData data) return data;
    final raw = await Future.wait([
      rootBundle.loadString('assets/data/quran.json'),
      rootBundle.loadString('assets/data/hafs-kfqc-manifest.json'),
    ]);
    final quran = Map<String, dynamic>.from(jsonDecode(raw[0]) as Map);
    final manifest = Map<String, dynamic>.from(jsonDecode(raw[1]) as Map);
    final data = QuranData(
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
