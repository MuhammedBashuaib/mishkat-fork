import '../../data/models/quran_search_models.dart';

/// Service providing Arabic text normalization and character-level match mapping
/// between normalized search queries and authentic Uthmani Quran text.
class QuranSearchNormalizer {
  const QuranSearchNormalizer._();

  static final RegExp _diacriticsRegex = RegExp(
    r'[\u064B-\u065F\u06D6-\u06ED]',
  );

  /// Converts Eastern Arabic numerals (٠-٩) to ASCII digits (0-9).
  static String convertArabicDigits(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);
      if (codeUnit >= 0x0660 && codeUnit <= 0x0669) {
        buffer.write(codeUnit - 0x0660);
      } else {
        buffer.writeCharCode(codeUnit);
      }
    }
    return buffer.toString();
  }

  static bool _isOmittedDaggerAlef(List<String> normChars) {
    if (normChars.isEmpty) return false;
    final len = normChars.length;
    // Check for "رحم" (e.g. الرحمن, رحمن)
    if (len >= 3 &&
        normChars[len - 3] == 'ر' &&
        normChars[len - 2] == 'ح' &&
        normChars[len - 1] == 'م') {
      return true;
    }
    // Check for "ه" (e.g. هذا, هذه, هؤلاء)
    if (normChars[len - 1] == 'ه') {
      return true;
    }
    // Check for "ذ" (e.g. ذلك)
    if (normChars[len - 1] == 'ذ') {
      return true;
    }
    // Check for "لك" (e.g. لكن)
    if (len >= 2 && normChars[len - 2] == 'ل' && normChars[len - 1] == 'ك') {
      return true;
    }
    return false;
  }

  /// Normalizes Arabic text for flexible matching:
  /// - Converts dagger alef (\u0670) to standard alef (ا), except in words where modern spelling drops it
  /// - Strips diacritics / tashkeel (fatha, damma, kasra, sukun, shadda, tanwin)
  /// - Strips Tatweel/Kashida (ـ)
  /// - Normalizes Alef forms (أ, إ, آ, ٱ -> ا)
  /// - Normalizes Hamza variants (ؤ -> و, ئ -> ي)
  /// - Normalizes Alef Maqsura (ى -> ي)
  /// - Normalizes Ta Marbuta (ة -> ه)
  /// - Normalizes whitespace and trims
  static String normalize(String value) {
    return normalizeWithMap(value).normalized;
  }

  /// Normalizes [original] while simultaneously constructing a synchronized index map
  /// that tracks each character in the normalized output back to its 0-based index in [original].
  static ({String normalized, List<int> indexMap}) normalizeWithMap(
    String original,
  ) {
    if (original.isEmpty) {
      return (normalized: '', indexMap: const <int>[]);
    }

    final normalizedChars = <String>[];
    final indexMap = <int>[];

    for (var origIdx = 0; origIdx < original.length; origIdx++) {
      var char = original[origIdx];

      // Convert line breaks and tabs to space
      if (char == '\n' || char == '\r' || char == '\t') {
        char = ' ';
      }

      // Skip Tatweel and diacritics (excluding dagger alef)
      if (char == 'ـ' || _diacriticsRegex.hasMatch(char)) {
        continue;
      }

      if (char == '\u0670') {
        // Dagger alef: convert to alef unless in common words like الرحمن, هذا, ذلك
        if (_isOmittedDaggerAlef(normalizedChars)) {
          continue;
        }
        normalizedChars.add('ا');
        indexMap.add(origIdx);
        continue;
      }

      var normChar = char;
      if (normChar == 'أ' ||
          normChar == 'إ' ||
          normChar == 'آ' ||
          normChar == 'ٱ') {
        normChar = 'ا';
      } else if (normChar == 'ؤ') {
        normChar = 'و';
      } else if (normChar == 'ئ' || normChar == 'ى') {
        normChar = 'ي';
      } else if (normChar == 'ة') {
        normChar = 'ه';
      }

      normChar = normChar.toLowerCase();

      // Collapse multiple whitespace
      if (normChar == ' ' &&
          normalizedChars.isNotEmpty &&
          normalizedChars.last == ' ') {
        continue;
      }

      normalizedChars.add(normChar);
      indexMap.add(origIdx);
    }

    // Trim trailing space if any
    while (normalizedChars.isNotEmpty && normalizedChars.last == ' ') {
      normalizedChars.removeLast();
      indexMap.removeLast();
    }
    // Trim leading space if any
    while (normalizedChars.isNotEmpty && normalizedChars.first == ' ') {
      normalizedChars.removeAt(0);
      indexMap.removeAt(0);
    }

    return (normalized: normalizedChars.join(), indexMap: indexMap);
  }

  /// Finds all match ranges of [normalizedQuery] in [originalText] and maps them
  /// accurately to character ranges on [originalText] (including attached diacritics).
  static List<TextMatchRange> findMatchRanges({
    required String originalText,
    required String normalizedQuery,
    String? precomputedNormalized,
    List<int>? precomputedIndexMap,
  }) {
    if (normalizedQuery.isEmpty || originalText.isEmpty) {
      return const [];
    }

    final String normText;
    final List<int> indexMap;

    if (precomputedNormalized != null && precomputedIndexMap != null) {
      normText = precomputedNormalized;
      indexMap = precomputedIndexMap;
    } else {
      final result = normalizeWithMap(originalText);
      normText = result.normalized;
      indexMap = result.indexMap;
    }

    if (normText.isEmpty || indexMap.isEmpty) return const [];

    final ranges = <TextMatchRange>[];
    var searchStart = 0;

    while (searchStart < normText.length) {
      final matchIdx = normText.indexOf(normalizedQuery, searchStart);
      if (matchIdx == -1) break;

      final normEndIdx = matchIdx + normalizedQuery.length;
      if (matchIdx < indexMap.length && (normEndIdx - 1) < indexMap.length) {
        final origStart = indexMap[matchIdx];
        var origEnd = indexMap[normEndIdx - 1] + 1;

        // Absorb any trailing diacritics or tatweel attached to the final matched character
        while (origEnd < originalText.length) {
          final nextChar = originalText[origEnd];
          if (nextChar == 'ـ' || _diacriticsRegex.hasMatch(nextChar)) {
            origEnd++;
          } else {
            break;
          }
        }

        ranges.add(TextMatchRange(start: origStart, end: origEnd));
      }

      searchStart = matchIdx + 1;
    }

    return ranges;
  }
}
