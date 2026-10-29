import '../../../../core/services/local_storage_service.dart';
import '../models/quran_models.dart';
import '../models/quran_search_models.dart';
import '../../presentation/services/quran_reference_parser.dart';
import '../../presentation/services/quran_search_normalizer.dart';

class _SearchableAyah {
  const _SearchableAyah({
    required this.globalAyah,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.page,
    required this.originalText,
    required this.normalizedText,
    required this.indexMap,
  });

  final int globalAyah;
  final int surah;
  final String surahName;
  final int ayah;
  final int page;
  final String originalText;
  final String normalizedText;
  final List<int> indexMap;
}

/// High-performance local-first Quran search repository.
///
/// Pre-normalizes all 6,236 Ayahs into memory on first initialization (~60ms),
/// enabling sub-millisecond query evaluation without duplicating original Quran text.
class QuranSearchRepository {
  QuranSearchRepository({this.storage});

  final LocalStorageService? storage;
  List<_SearchableAyah>? _indexedAyahs;

  static const String _historyKey = 'quran_search_history';
  static const int _maxHistoryEntries = 10;

  /// Returns whether the search index is initialized in memory.
  bool get isInitialized => _indexedAyahs != null;

  /// Builds or ensures the pre-computed in-memory search index from canonical [QuranData].
  void initialize(QuranData data) {
    if (_indexedAyahs != null) return;

    final index = <_SearchableAyah>[];
    for (final chapter in data.chapters) {
      final surahNum = chapter.number;
      final surahName = chapter.name;
      final globalStart = chapter.globalStart;

      for (var a = 0; a < chapter.ayahs.length; a++) {
        final original = chapter.ayahs[a];
        final ayahNum = a + 1;
        final global = globalStart + a;
        final page = data.pageForGlobal(global);

        final normResult = QuranSearchNormalizer.normalizeWithMap(original);

        index.add(
          _SearchableAyah(
            globalAyah: global,
            surah: surahNum,
            surahName: surahName,
            ayah: ayahNum,
            page: page,
            originalText: original,
            normalizedText: normResult.normalized,
            indexMap: normResult.indexMap,
          ),
        );
      }
    }

    _indexedAyahs = List.unmodifiable(index);
  }

  /// Searches Quran text, Surahs, and references using [query] and [filter].
  QuranSearchResults search({
    required QuranData data,
    required String query,
    QuranSearchFilter filter = QuranSearchFilter.all,
    int limit = 100,
  }) {
    final rawTrimmed = query.trim();
    if (rawTrimmed.isEmpty) {
      return QuranSearchResults.empty;
    }

    initialize(data);
    final index = _indexedAyahs!;

    final normalizedQuery = QuranSearchNormalizer.normalize(
      QuranSearchNormalizer.convertArabicDigits(rawTrimmed),
    );

    // 1. Direct Reference Parser Check
    final directRef = QuranReferenceParser.parse(rawTrimmed, data);

    // 2. Surah Matching (if filter permits)
    final matchedSurahs = <QuranChapter>[];
    if (filter == QuranSearchFilter.all || filter == QuranSearchFilter.surahs) {
      final queryNum = int.tryParse(
        QuranSearchNormalizer.convertArabicDigits(rawTrimmed),
      );
      for (final ch in data.chapters) {
        final normName = QuranSearchNormalizer.normalize(ch.name);
        final normEnName = QuranSearchNormalizer.normalize(ch.englishName);

        if (ch.number == queryNum ||
            normName.contains(normalizedQuery) ||
            normEnName.contains(normalizedQuery) ||
            normName == 'ال$normalizedQuery' ||
            'ال$normName' == normalizedQuery) {
          matchedSurahs.add(ch);
        }
      }
    }

    // 3. Ayah Text Matching (if filter permits)
    final matchedAyahs = <QuranAyahSearchResult>[];
    if ((filter == QuranSearchFilter.all ||
            filter == QuranSearchFilter.ayahs) &&
        normalizedQuery.isNotEmpty) {
      for (final item in index) {
        if (item.normalizedText.contains(normalizedQuery)) {
          final ranges = QuranSearchNormalizer.findMatchRanges(
            originalText: item.originalText,
            normalizedQuery: normalizedQuery,
            precomputedNormalized: item.normalizedText,
            precomputedIndexMap: item.indexMap,
          );

          // Calculate relevance score
          var score = 0;
          if (item.normalizedText.startsWith(normalizedQuery)) {
            score += 20;
          }
          if (item.normalizedText == normalizedQuery) {
            score += 50;
          }

          matchedAyahs.add(
            QuranAyahSearchResult(
              globalAyah: item.globalAyah,
              surah: item.surah,
              surahName: item.surahName,
              ayah: item.ayah,
              page: item.page,
              originalText: item.originalText,
              normalizedText: item.normalizedText,
              matchRanges: ranges,
              relevanceScore: score,
            ),
          );

          if (matchedAyahs.length >= limit) break;
        }
      }
    }

    final totalCount =
        (directRef != null ? 1 : 0) +
        matchedSurahs.length +
        matchedAyahs.length;

    return QuranSearchResults(
      query: rawTrimmed,
      directReference: directRef,
      matchedSurahs: matchedSurahs,
      matchedAyahs: matchedAyahs,
      totalMatches: totalCount,
    );
  }

  // ==========================================
  // Recent Searches Persistence
  // ==========================================

  List<String> getRecentSearches() {
    final s = storage;
    if (s == null) return const [];
    return s
        .readList(_historyKey)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .take(_maxHistoryEntries)
        .toList();
  }

  Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    final s = storage;
    if (trimmed.isEmpty || s == null) return;

    final current = getRecentSearches();
    final updated = [
      trimmed,
      ...current.where((item) => item != trimmed),
    ].take(_maxHistoryEntries).toList();

    await s.writeList(_historyKey, updated);
  }

  Future<void> removeRecentSearch(String query) async {
    final s = storage;
    if (s == null) return;
    final current = getRecentSearches();
    final updated = current.where((item) => item != query.trim()).toList();
    await s.writeList(_historyKey, updated);
  }

  Future<void> clearRecentSearches() async {
    final s = storage;
    if (s == null) return;
    await s.writeList(_historyKey, const []);
  }
}
