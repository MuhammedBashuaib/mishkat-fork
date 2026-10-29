import 'package:equatable/equatable.dart';

import 'quran_models.dart';

/// Filter mode for Quran search queries.
enum QuranSearchFilter { all, ayahs, surahs, pages }

/// A character range representing a match within text.
class TextMatchRange extends Equatable {
  const TextMatchRange({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;

  @override
  List<Object?> get props => [start, end];
}

/// Direct reference parsed from a user query (e.g., "2:255", "البقرة 255", "ص 604").
enum QuranReferenceType { surah, ayah, page, globalAyah }

/// Represents a parsed direct reference targeting a specific Quran location.
class QuranParsedReference extends Equatable {
  const QuranParsedReference({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.page,
    this.surah,
    this.ayah,
    this.globalAyah,
  });

  final QuranReferenceType type;
  final String title;
  final String subtitle;
  final int page;
  final int? surah;
  final int? ayah;
  final int? globalAyah;

  @override
  List<Object?> get props => [
    type,
    title,
    subtitle,
    page,
    surah,
    ayah,
    globalAyah,
  ];
}

/// Domain search result representing a matched Ayah in the Quran.
class QuranAyahSearchResult extends Equatable {
  const QuranAyahSearchResult({
    required this.globalAyah,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.page,
    required this.originalText,
    required this.normalizedText,
    required this.matchRanges,
    this.relevanceScore = 0,
  });

  final int globalAyah;
  final int surah;
  final String surahName;
  final int ayah;
  final int page;
  final String originalText;
  final String normalizedText;
  final List<TextMatchRange> matchRanges;
  final int relevanceScore;

  QuranPoint get point =>
      QuranPoint(surah: surah, ayah: ayah, global: globalAyah);

  @override
  List<Object?> get props => [
    globalAyah,
    surah,
    surahName,
    ayah,
    page,
    originalText,
    normalizedText,
    matchRanges,
    relevanceScore,
  ];
}

/// Combined container for search output.
class QuranSearchResults extends Equatable {
  const QuranSearchResults({
    required this.query,
    this.directReference,
    this.matchedSurahs = const [],
    this.matchedAyahs = const [],
    this.totalMatches = 0,
  });

  static const empty = QuranSearchResults(query: '');

  final String query;
  final QuranParsedReference? directReference;
  final List<QuranChapter> matchedSurahs;
  final List<QuranAyahSearchResult> matchedAyahs;
  final int totalMatches;

  bool get isEmpty =>
      directReference == null && matchedSurahs.isEmpty && matchedAyahs.isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  List<Object?> get props => [
    query,
    directReference,
    matchedSurahs,
    matchedAyahs,
    totalMatches,
  ];
}
