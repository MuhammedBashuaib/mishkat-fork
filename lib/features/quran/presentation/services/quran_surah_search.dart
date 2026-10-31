import '../../data/models/quran_models.dart';
import 'quran_search_normalizer.dart';

/// Shared matching for the index, search results, bookmarks and memorization.
/// Only search keys are normalized; displayed names keep their correct spelling.
class QuranSurahSearch {
  const QuranSurahSearch._();

  static final _prefix = RegExp(r'^(?:ال)?(?:سوره|سور)(?:\s+|$)');
  static final _separators = RegExp(r"[\s\-'’]+");

  static String normalizeQuery(String query) => QuranSearchNormalizer.normalize(
    QuranSearchNormalizer.convertArabicDigits(query),
  );

  static bool hasSurahPrefix(String query) =>
      _prefix.hasMatch(normalizeQuery(query));

  static String nameQuery(String query) =>
      normalizeQuery(query).replaceFirst(_prefix, '').trim();

  static String _key(String text) =>
      normalizeQuery(text).replaceAll(_separators, '');

  static bool isExact(QuranChapter chapter, String query) {
    final key = _key(nameQuery(query));
    if (key.isEmpty) return false;
    return _names(chapter.name, chapter.englishName).any((name) => name == key);
  }

  static Iterable<String> _names(String name, String englishName) sync* {
    final arabic = _key(name);
    yield arabic;
    if (arabic.startsWith('ال')) yield arabic.substring(2);
    if (englishName.isNotEmpty) {
      final english = _key(englishName);
      yield english;
      if (english.startsWith('al')) yield english.substring(2);
    }
  }

  /// Exact, prefix, substring, then a single missing/extra/substituted letter.
  /// Short queries never use typo matching, to avoid unrelated short names.
  static int? score({
    required String query,
    required String name,
    required int number,
    String englishName = '',
  }) {
    final normalized = nameQuery(query);
    if (normalized.isEmpty) {
      return normalizeQuery(query).isEmpty || hasSurahPrefix(query) ? 0 : null;
    }
    final numeric = int.tryParse(normalized);
    if (numeric != null) return numeric == number ? 0 : null;
    final key = _key(normalized);
    if (key.isEmpty) return null;
    int? best;
    for (final candidate in _names(name, englishName)) {
      final int? rank;
      if (candidate == key) {
        rank = 0;
      } else if (candidate.startsWith(key)) {
        rank = 1;
      } else if (candidate.contains(key)) {
        rank = 2;
      } else if (key.length >= 4 && _oneEditApart(candidate, key)) {
        rank = 3;
      } else {
        rank = null;
      }
      if (rank != null && (best == null || rank < best)) best = rank;
    }
    return best;
  }

  static List<QuranChapter> findChapters(
    Iterable<QuranChapter> chapters,
    String query, {
    bool includeRevelationType = false,
  }) {
    final matches = <({QuranChapter chapter, int rank})>[];
    final normalized = normalizeQuery(query);
    for (final chapter in chapters) {
      final rank = score(
        query: query,
        name: chapter.name,
        englishName: chapter.englishName,
        number: chapter.number,
      );
      if (rank != null) {
        matches.add((chapter: chapter, rank: rank));
      } else if (includeRevelationType &&
          normalizeQuery(chapter.revelationType).contains(normalized)) {
        matches.add((chapter: chapter, rank: 2));
      }
    }
    final hasLiteralMatch = matches.any((match) => match.rank < 3);
    if (hasLiteralMatch) matches.removeWhere((match) => match.rank == 3);
    matches.sort((a, b) {
      final rankOrder = a.rank.compareTo(b.rank);
      return rankOrder != 0
          ? rankOrder
          : a.chapter.number.compareTo(b.chapter.number);
    });
    return matches.map((match) => match.chapter).toList(growable: false);
  }

  static bool _oneEditApart(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
      } else {
        if (++edits > 1) return false;
        if (a.length >= b.length) i++;
        if (b.length >= a.length) j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}
