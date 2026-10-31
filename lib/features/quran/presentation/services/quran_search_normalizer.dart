import '../../data/models/quran_search_models.dart';

/// Service providing Arabic text normalization and character-level match mapping
/// between normalized search queries and authentic Uthmani Quran text.
class QuranSearchNormalizer {
  const QuranSearchNormalizer._();

  static final RegExp _diacriticsRegex = RegExp(
    r'[\u064B-\u065F\u06D6-\u06ED]',
  );
  static final RegExp _whitespace = RegExp(r'\s');
  static final RegExp _formattingMarks = RegExp(
    r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  /// Converts Eastern Arabic numerals (٠-٩) to ASCII digits (0-9).
  static String convertArabicDigits(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);
      if (codeUnit >= 0x0660 && codeUnit <= 0x0669) {
        buffer.write(codeUnit - 0x0660);
      } else if (codeUnit >= 0x06F0 && codeUnit <= 0x06F9) {
        buffer.write(codeUnit - 0x06F0);
      } else {
        buffer.writeCharCode(codeUnit);
      }
    }
    return buffer.toString();
  }

  static final _divineNamePrefix = RegExp(r'^[وفبكل]{0,2}ال(?:ل)?$');
  static final _demonstrativePrefix = RegExp(r'^[اوفبكل]{0,2}ه$');
  static final _dhalPrefix = RegExp(r'^[اوفبكل]{0,2}ذ$');
  static final _butPrefix = RegExp(r'^[وف]?ل(?:ك)?$');

  static bool _isOmittedDaggerAlef(List<String> normChars, String next) {
    final word = normChars.skip(normChars.lastIndexOf(' ') + 1).join();
    // These words omit the superscript alef in ordinary Arabic spelling.
    // Scope the rule to the word: a blanket rule after ه also breaks شهادة.
    if (word.endsWith('رحم') && next == 'ن') return true;
    if (_divineNamePrefix.hasMatch(word) && next == 'ه') return true;
    if (_demonstrativePrefix.hasMatch(word) &&
        const ['ذ', 'ؤ', 'ك'].contains(next)) {
      return true;
    }
    if (_dhalPrefix.hasMatch(word) && next == 'ل') return true;
    if (_butPrefix.hasMatch(word) && const ['ك', 'ن'].contains(next)) {
      return true;
    }
    return false;
  }

  static String _nextLetter(String original, int index) {
    while (index < original.length &&
        (_diacriticsRegex.hasMatch(original[index]) ||
            original[index] == 'ـ')) {
      index++;
    }
    return index < original.length ? original[index] : '';
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
    int? leadingHamzaIndex;

    for (var origIdx = 0; origIdx < original.length; origIdx++) {
      var char = original[origIdx];

      // Convert line breaks and tabs to space
      if (_whitespace.hasMatch(char)) {
        char = ' ';
      }

      // Skip Tatweel and diacritics (excluding dagger alef)
      if (char == 'ـ' ||
          _diacriticsRegex.hasMatch(char) ||
          _formattingMarks.hasMatch(char)) {
        continue;
      }

      if (char == '\u0670') {
        // Dagger alef: convert to alef unless in common words like الرحمن, هذا, ذلك
        if (_isOmittedDaggerAlef(
              normalizedChars,
              _nextLetter(original, origIdx + 1),
            ) ||
            (indexMap.isNotEmpty && original[indexMap.last] == 'ى')) {
          continue;
        }
        normalizedChars.add('ا');
        indexMap.add(origIdx);
        continue;
      }

      var normChar = char;
      // The Uthmani spelling ءَامَنُوا and the typed spelling آمنوا share a key.
      if (char == 'ء' && _nextLetter(original, origIdx + 1) == 'ا') {
        leadingHamzaIndex = origIdx;
        continue;
      }
      if (normChar == 'أ' ||
          normChar == 'إ' ||
          normChar == 'آ' ||
          normChar == 'ٱ') {
        normChar = 'ا';
      } else if (normChar == 'ؤ') {
        normChar = 'و';
      } else if (normChar == 'ئ' || normChar == 'ى' || normChar == 'ی') {
        normChar = 'ي';
      } else if (normChar == 'ک') {
        normChar = 'ك';
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
      indexMap.add(leadingHamzaIndex ?? origIdx);
      leadingHamzaIndex = null;
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
          if (nextChar == 'ـ' ||
              nextChar == '\u0670' ||
              _diacriticsRegex.hasMatch(nextChar)) {
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
