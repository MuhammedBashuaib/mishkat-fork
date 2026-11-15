import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../models/library_models.dart';

class LibraryRepository {
  List<LibraryBook>? _books;
  final Map<String, List<LibraryEntry>> _entries = {};

  Future<List<LibraryBook>> loadCatalog() async {
    if (_books case final List<LibraryBook> books) return books;
    final data = Map<String, dynamic>.from(
      jsonDecode(
        await rootBundle.loadString('assets/data/library-catalog.json'),
      ) as Map,
    );
    final books = (data['books'] as List)
        .map(
          (item) =>
              LibraryBook.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    _books = books;
    return books;
  }

  Future<List<LibraryEntry>> loadBook(LibraryBook book) async {
    if (_entries[book.id] case final List<LibraryEntry> entries) return entries;
    if (book.contentType == 'tafsir') return _loadTafsir(book);
    final fileName = book.contentPath.split('/').last;
    final raw = await rootBundle.loadString('assets/data/$fileName');
    final entries = await compute(_parseBook, raw);
    _entries[book.id] = entries;
    return entries;
  }

  Future<List<LibraryEntry>> _loadTafsir(LibraryBook book) async {
    final raw = await Future.wait([
      rootBundle.loadString('assets/data/tafsir-muyassar.json'),
      rootBundle.loadString('assets/data/quran.json'),
    ]);
    final entries = await compute(_parseTafsir, (raw, book.sourceUrl));
    _entries[book.id] = entries;
    return entries;
  }
}

List<LibraryEntry> _parseBook(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  return (data['entries'] as List)
      .map(
        (item) => LibraryEntry.fromJson(Map<String, dynamic>.from(item as Map)),
      )
      .toList(growable: false);
}

List<LibraryEntry> _parseTafsir((List<String>, String) input) {
  final tafsir = jsonDecode(input.$1[0]) as Map<String, dynamic>;
  final quran = jsonDecode(input.$1[1]) as Map<String, dynamic>;
  final explanations = Map<String, dynamic>.from(tafsir['entries'] as Map);
  final entries = <LibraryEntry>[];
  var globalNumber = 1;
  for (final rawSurah in quran['surahs'] as List) {
    final surah = Map<String, dynamic>.from(rawSurah as Map);
    final surahName = '${surah['name']}'.replaceAll('ٱ', 'ا');
    final ayahs = surah['ayahs'] as List;
    for (var index = 0; index < ayahs.length; index++) {
      final explanation = '${explanations['$globalNumber'] ?? ''}';
      entries.add(
        LibraryEntry(
          id: 'tafsir-$globalNumber',
          number: globalNumber,
          title: 'الآية ${index + 1}',
          chapter: 'سورة $surahName',
          text: '${ayahs[index]}\n\n$explanation',
          reference: 'التفسير الميسر · سورة $surahName · الآية ${index + 1}',
          sourceUrl: input.$2,
        ),
      );
      globalNumber++;
    }
  }
  return entries;
}
