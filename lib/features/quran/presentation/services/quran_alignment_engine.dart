import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/models/oral_recitation_models.dart';
import '../../data/models/quran_models.dart';
import 'quran_search_normalizer.dart';

/// The calculated alignment output of an oral recitation session at a specific point in time.
class QuranAlignmentResult {
  const QuranAlignmentResult({
    required this.alignedWords,
    required this.currentGlobalAyah,
    required this.currentWordIndex,
    required this.discrepancies,
    required this.totalWords,
    required this.matchedWordsCount,
    required this.omissionsCount,
    required this.substitutionsCount,
    required this.uncertainCount,
    required this.progressPercentage,
    required this.isCompleted,
    required this.completedGlobalAyahs,
    this.committedTargetIndex = 0,
    this.candidateStartIndex = 0,
    this.candidateEndIndex = 0,
    this.alignmentReason = '',
    this.rejectedBackwardCandidate,
  });

  /// The full list of target words with their current alignment status.
  final List<RecitationWordAlignment> alignedWords;

  /// Global Ayah currently being recited.
  final int currentGlobalAyah;

  /// Index of the word currently being recited within the target range.
  final int currentWordIndex;

  /// All detected recitation discrepancies (omissions, substitutions, uncertainties).
  final List<RecitationDiscrepancy> discrepancies;

  /// Total number of words in the target passage.
  final int totalWords;

  /// Count of words correctly matched.
  final int matchedWordsCount;

  /// Count of words omitted/skipped.
  final int omissionsCount;

  /// Count of words substituted.
  final int substitutionsCount;

  /// Count of words with uncertain/low-confidence recognition.
  final int uncertainCount;

  /// Percentage of target passage completed (0.0 .. 100.0).
  final double progressPercentage;

  /// Whether the entire target passage has been recited.
  final bool isCompleted;

  /// Set of global Ayahs that have been fully recited.
  final Set<int> completedGlobalAyahs;

  /// Confirmed monotonic committed target index.
  final int committedTargetIndex;

  /// Diagnostic: Candidate search start index.
  final int candidateStartIndex;

  /// Diagnostic: Candidate search end index.
  final int candidateEndIndex;

  /// Diagnostic: Reason for the selected alignment step.
  final String alignmentReason;

  /// Diagnostic: Any candidate that fell behind the committed cursor and was safely rejected.
  final String? rejectedBackwardCandidate;
}

/// Pure Dart, deterministic alignment engine for matching spoken Arabic transcripts
/// against canonical Uthmani Quranic text.
class QuranAlignmentEngine {
  const QuranAlignmentEngine();

  static const String basmalahNormalized = 'بسم الله الرحمن الرحيم';

  /// Tokenizes a list of Ayahs into authoritative word tokens with dual representations:
  /// canonical Uthmani text with diacritics, and stripped normalized text for comparison.
  List<AuthoritativeWord> prepareTargetTokens({
    required List<QuranChapter> chapters,
    required int startGlobalAyah,
    required int endGlobalAyah,
  }) {
    final tokens = <AuthoritativeWord>[];
    final start = min(startGlobalAyah, endGlobalAyah);
    final end = max(startGlobalAyah, endGlobalAyah);

    var globalIndex = 1;
    var sequenceWordIdx = 0;

    for (final chapter in chapters) {
      for (var aIdx = 0; aIdx < chapter.ayahs.length; aIdx++) {
        final currentGlobal = globalIndex;
        globalIndex++;

        if (currentGlobal < start || currentGlobal > end) {
          continue;
        }

        final ayahText = chapter.ayahs[aIdx];
        final words = _splitAyahIntoWords(ayahText);

        for (final word in words) {
          final normalized = QuranSearchNormalizer.normalize(word);
          if (normalized.isEmpty) continue;

          tokens.add(
            AuthoritativeWord(
              globalAyah: currentGlobal,
              surah: chapter.number,
              ayahInSurah: aIdx + 1,
              wordIndex: sequenceWordIdx,
              uthmaniText: word,
              normalizedText: normalized,
            ),
          );
          sequenceWordIdx++;
        }
      }
    }

    return List.unmodifiable(tokens);
  }

  /// Aligns a raw transcript string from the speech recognizer against [targetWords]
  /// with monotonic progress tracking and repeated-phrase disambiguation.
  QuranAlignmentResult align({
    required List<AuthoritativeWord> targetWords,
    required String transcript,
    double confidence = 1.0,
    int committedTargetIndex = 0,
    List<RecitationWordAlignment>? committedAlignedWords,
    List<RecitationDiscrepancy>? committedDiscrepancies,
    bool isFinal = true,
  }) {
    if (targetWords.isEmpty) {
      return const QuranAlignmentResult(
        alignedWords: [],
        currentGlobalAyah: 1,
        currentWordIndex: 0,
        discrepancies: [],
        totalWords: 0,
        matchedWordsCount: 0,
        omissionsCount: 0,
        substitutionsCount: 0,
        uncertainCount: 0,
        progressPercentage: 0.0,
        isCompleted: false,
        completedGlobalAyahs: {},
      );
    }

    // 1. Tokenize and normalize recognized words
    final rawTokens = _splitTranscript(transcript);
    final recTokens = <String>[];
    for (final raw in rawTokens) {
      final norm = QuranSearchNormalizer.normalize(raw);
      if (norm.isNotEmpty) {
        recTokens.add(norm);
      }
    }

    // 2. Determine uncommitted recognized tokens:
    var recStartIdx = 0;
    if (committedTargetIndex == 0) {
      // Handle optional Basmalah preamble:
      // If user recites Basmalah before Surah verses (and target doesn't already start with Basmalah)
      if (recTokens.length >= 4 &&
          recTokens[0] == 'بسم' &&
          recTokens[1] == 'الله' &&
          recTokens[2] == 'الرحمن' &&
          recTokens[3] == 'الرحيم') {
        final targetStartsBasmalah =
            targetWords.length >= 4 &&
            targetWords[0].normalizedText == 'بسم' &&
            targetWords[1].normalizedText == 'الله';
        if (!targetStartsBasmalah) {
          recStartIdx = 4; // Skip preamble Basmalah from alignment
        }
      }
    } else {
      // When committedTargetIndex > 0, check if recTokens is a cumulative transcript
      // extending from the beginning of the target sequence.
      if (recTokens.length >= committedTargetIndex) {
        var prefixMatches = 0;
        for (var i = 0; i < committedTargetIndex; i++) {
          if (_isMatch(targetWords[i].normalizedText, recTokens[i])) {
            prefixMatches++;
          }
        }
        if (prefixMatches >= (committedTargetIndex * 0.75).ceil()) {
          recStartIdx = committedTargetIndex;
        }
      }
    }

    final activeRecTokens = recTokens.sublist(
      min(recStartIdx, recTokens.length),
    );

    // 3. Pre-fill already committed alignments and discrepancies
    final alignedWords = <RecitationWordAlignment>[];
    final discrepancies = <RecitationDiscrepancy>[];

    var matchedWordsCount = 0;
    var omissionsCount = 0;
    var substitutionsCount = 0;
    var uncertainCount = 0;

    final safeCommittedIndex = committedTargetIndex.clamp(
      0,
      targetWords.length,
    );

    if (safeCommittedIndex > 0) {
      if (committedAlignedWords != null &&
          committedAlignedWords.length >= safeCommittedIndex) {
        for (var i = 0; i < safeCommittedIndex; i++) {
          final word = committedAlignedWords[i];
          alignedWords.add(word);
          switch (word.status) {
            case WordAlignmentStatus.matched:
              matchedWordsCount++;
              break;
            case WordAlignmentStatus.omission:
              omissionsCount++;
              break;
            case WordAlignmentStatus.substitution:
              substitutionsCount++;
              break;
            case WordAlignmentStatus.uncertain:
              uncertainCount++;
              break;
            default:
              break;
          }
        }
      } else {
        // Fallback pre-fill confirmed committed prefix as matched
        for (var i = 0; i < safeCommittedIndex; i++) {
          alignedWords.add(
            RecitationWordAlignment(
              authoritativeWord: targetWords[i],
              status: WordAlignmentStatus.matched,
            ),
          );
          matchedWordsCount++;
        }
      }

      if (committedDiscrepancies != null) {
        for (final d in committedDiscrepancies) {
          if (d.wordIndex < safeCommittedIndex) {
            discrepancies.add(d);
          }
        }
      }
    }

    // 4. Sequential Monotonic Alignment Starting From committedTargetIndex
    var targetPtr = safeCommittedIndex;
    var recPtr = 0;
    String? rejectedBackwardCandidate;

    while (targetPtr < targetWords.length && recPtr < activeRecTokens.length) {
      final targetWord = targetWords[targetPtr];
      final recWord = activeRecTokens[recPtr];

      // A. Check for Exact or Close Phonetic Match on current target word
      final matchQuality = _compareWords(targetWord.normalizedText, recWord);

      if (matchQuality == _MatchQuality.exact ||
          matchQuality == _MatchQuality.close) {
        final isUncertain =
            (confidence < 0.65) ||
            (matchQuality == _MatchQuality.close && confidence < 0.8);
        final status = isUncertain
            ? WordAlignmentStatus.uncertain
            : WordAlignmentStatus.matched;

        if (status == WordAlignmentStatus.matched) {
          matchedWordsCount++;
        } else {
          uncertainCount++;
          discrepancies.add(
            RecitationDiscrepancy(
              id: 'disc_unc_${targetWord.globalAyah}_${targetWord.wordIndex}',
              globalAyah: targetWord.globalAyah,
              surah: targetWord.surah,
              ayahInSurah: targetWord.ayahInSurah,
              wordIndex: targetWord.wordIndex,
              expectedUthmani: targetWord.uthmaniText,
              expectedNormalized: targetWord.normalizedText,
              recognizedWord: recWord,
              status: WordAlignmentStatus.uncertain,
              explanation:
                  'التقاط صوتي غير مؤكد للكلمة القرآنية "${targetWord.uthmaniText}".',
            ),
          );
        }

        alignedWords.add(
          RecitationWordAlignment(
            authoritativeWord: targetWord,
            status: status,
            recognizedWord: recWord,
            confidence: confidence,
          ),
        );

        targetPtr++;
        recPtr++;
        continue;
      }

      // B. Check for Recitation Repetition (Tardid / Self-Correction)
      // Check if user repeated a word they recently recited in the current attempt
      if (targetPtr > 0 &&
          _compareWords(targetWords[targetPtr - 1].normalizedText, recWord) ==
              _MatchQuality.exact) {
        // Repeated previous word; consume recWord without advancing targetPtr
        recPtr++;
        continue;
      }

      // Check if recWord matches an earlier occurrence (e.g. earlier Basmalah)
      // Log as rejected backward candidate rather than jumping backwards
      for (var back = 0; back < safeCommittedIndex; back++) {
        if (_isMatch(targetWords[back].normalizedText, recWord)) {
          rejectedBackwardCandidate =
              'Rejected backward match "$recWord" at target index $back (current cursor: $targetPtr >= committed: $safeCommittedIndex)';
          break;
        }
      }

      // C. Lookahead Window Search:
      // Bounded forward search up to 4 words strictly ahead of current targetPtr
      int? foundTargetAhead;
      for (
        var look = 1;
        look <= 4 && (targetPtr + look) < targetWords.length;
        look++
      ) {
        if (_isMatch(targetWords[targetPtr + look].normalizedText, recWord)) {
          foundTargetAhead = targetPtr + look;
          break;
        }
      }

      int? foundRecAhead;
      for (
        var look = 1;
        look <= 4 && (recPtr + look) < activeRecTokens.length;
        look++
      ) {
        if (_isMatch(
          targetWord.normalizedText,
          activeRecTokens[recPtr + look],
        )) {
          foundRecAhead = recPtr + look;
          break;
        }
      }

      if (foundTargetAhead != null &&
          (foundRecAhead == null ||
              (foundTargetAhead - targetPtr) <= (foundRecAhead - recPtr))) {
        // Reciter skipped target words (Omission)
        // Ambiguity guard: If skipping multiple words and confidence is low, do not produce false multi-word omissions
        final skipCount = foundTargetAhead - targetPtr;
        if (skipCount > 1 && confidence < 0.65) {
          uncertainCount++;
          alignedWords.add(
            RecitationWordAlignment(
              authoritativeWord: targetWord,
              status: WordAlignmentStatus.uncertain,
              recognizedWord: recWord,
              confidence: confidence,
            ),
          );
          targetPtr++;
          recPtr++;
        } else {
          for (var i = targetPtr; i < foundTargetAhead; i++) {
            final omittedWord = targetWords[i];
            omissionsCount++;
            discrepancies.add(
              RecitationDiscrepancy(
                id: 'disc_omi_${omittedWord.globalAyah}_${omittedWord.wordIndex}',
                globalAyah: omittedWord.globalAyah,
                surah: omittedWord.surah,
                ayahInSurah: omittedWord.ayahInSurah,
                wordIndex: omittedWord.wordIndex,
                expectedUthmani: omittedWord.uthmaniText,
                expectedNormalized: omittedWord.normalizedText,
                recognizedWord: null,
                status: WordAlignmentStatus.omission,
                explanation:
                    'سقط في التلاوة: لم تُسمع كلمة "${omittedWord.uthmaniText}".',
              ),
            );
            alignedWords.add(
              RecitationWordAlignment(
                authoritativeWord: omittedWord,
                status: WordAlignmentStatus.omission,
              ),
            );
          }
          targetPtr = foundTargetAhead;
        }
      } else if (foundRecAhead != null) {
        // Reciter inserted an unexpected filler word before resuming target
        recPtr = foundRecAhead;
      } else {
        // Substitution mismatch on current word
        substitutionsCount++;
        discrepancies.add(
          RecitationDiscrepancy(
            id: 'disc_sub_${targetWord.globalAyah}_${targetWord.wordIndex}',
            globalAyah: targetWord.globalAyah,
            surah: targetWord.surah,
            ayahInSurah: targetWord.ayahInSurah,
            wordIndex: targetWord.wordIndex,
            expectedUthmani: targetWord.uthmaniText,
            expectedNormalized: targetWord.normalizedText,
            recognizedWord: recWord,
            status: WordAlignmentStatus.substitution,
            explanation:
                'خطأ أو استبدال: سُمعت "$recWord" بدلاً من "${targetWord.uthmaniText}".',
          ),
        );
        alignedWords.add(
          RecitationWordAlignment(
            authoritativeWord: targetWord,
            status: WordAlignmentStatus.substitution,
            recognizedWord: recWord,
            confidence: confidence,
          ),
        );
        targetPtr++;
        recPtr++;
      }
    }

    // 5. Fill remaining unrecited target words as 'upcoming'
    for (var i = targetPtr; i < targetWords.length; i++) {
      alignedWords.add(
        RecitationWordAlignment(
          authoritativeWord: targetWords[i],
          status: WordAlignmentStatus.upcoming,
        ),
      );
    }

    // 6. Compute Ayah completion set
    final completedGlobals = <int>{};
    final ayahsMap = <int, List<RecitationWordAlignment>>{};
    for (final word in alignedWords) {
      ayahsMap
          .putIfAbsent(word.authoritativeWord.globalAyah, () => [])
          .add(word);
    }

    for (final entry in ayahsMap.entries) {
      final ayahWords = entry.value;
      final allDone = ayahWords.every((w) => !w.status.isUpcoming);
      if (allDone) {
        completedGlobals.add(entry.key);
      }
    }

    // 7. Monotonic committed cursor update:
    // A. If isFinal, advance committed cursor up to targetPtr.
    // B. If streaming partial (!isFinal), advance committed cursor up to the boundary of completed Ayahs!
    var newCommittedIndex = safeCommittedIndex;
    if (isFinal) {
      newCommittedIndex = max(safeCommittedIndex, targetPtr);
    } else if (completedGlobals.isNotEmpty) {
      var maxCompletedWordIdx = safeCommittedIndex;
      for (final globalAyah in completedGlobals) {
        final lastWordOfAyah = targetWords.lastWhere(
          (w) => w.globalAyah == globalAyah,
        );
        final nextWordIndex = lastWordOfAyah.wordIndex + 1;
        if (nextWordIndex > maxCompletedWordIdx) {
          maxCompletedWordIdx = nextWordIndex;
        }
      }
      newCommittedIndex = max(safeCommittedIndex, maxCompletedWordIdx);
    }

    // 8. Compute current position
    final safeCurrentWordIdx = (targetPtr < targetWords.length)
        ? targetPtr
        : (targetWords.length - 1);
    final currentGlobal = targetWords[safeCurrentWordIdx].globalAyah;

    final totalWords = targetWords.length;
    final progress = totalWords > 0
        ? (matchedWordsCount / totalWords) * 100.0
        : 0.0;
    final isCompleted = targetPtr >= targetWords.length;

    if (kDebugMode) {
      debugPrint(
        '[Q14_ENGINE_ALIGN] inCommitted=$committedTargetIndex '
        'safeCommitted=$safeCommittedIndex isFinal=$isFinal '
        'targetPtr=$targetPtr newCommitted=$newCommittedIndex '
        'matched=$matchedWordsCount omi=$omissionsCount '
        'completedAyahs=$completedGlobals '
        'discCount=${discrepancies.length}',
      );
      if (rejectedBackwardCandidate != null) {
        debugPrint('[Q14_ENGINE_REJECTED] $rejectedBackwardCandidate');
      }
    }

    return QuranAlignmentResult(
      alignedWords: List.unmodifiable(alignedWords),
      currentGlobalAyah: currentGlobal,
      currentWordIndex: safeCurrentWordIdx,
      discrepancies: List.unmodifiable(discrepancies),
      totalWords: totalWords,
      matchedWordsCount: matchedWordsCount,
      omissionsCount: omissionsCount,
      substitutionsCount: substitutionsCount,
      uncertainCount: uncertainCount,
      progressPercentage: progress.clamp(0.0, 100.0),
      isCompleted: isCompleted,
      completedGlobalAyahs: completedGlobals,
      committedTargetIndex: newCommittedIndex,
      candidateStartIndex: safeCommittedIndex,
      candidateEndIndex: min(targetWords.length, targetPtr + 4),
      alignmentReason: isFinal
          ? 'Finalized alignment at target cursor $targetPtr (committed: $newCommittedIndex)'
          : (newCommittedIndex > safeCommittedIndex
                ? 'Streaming partial committed Ayah boundary to $newCommittedIndex (target cursor $targetPtr)'
                : 'Provisional partial hypothesis up to target cursor $targetPtr (committed remains $safeCommittedIndex)'),
      rejectedBackwardCandidate: rejectedBackwardCandidate,
    );
  }

  static List<String> _splitAyahIntoWords(String ayahText) {
    return ayahText
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _splitTranscript(String transcript) {
    return transcript
        .split(RegExp(r'[\s،.؟!]+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  static bool _isMatch(String target, String recognized) {
    final quality = _compareWords(target, recognized);
    return quality == _MatchQuality.exact || quality == _MatchQuality.close;
  }

  static _MatchQuality _compareWords(String target, String recognized) {
    if (target == recognized) return _MatchQuality.exact;

    // Prefix/particle matching:
    // Quranic tokens frequently attach 'و' (waw) or 'ف' (faa) or 'ب' (baa) or 'ل' (laam)
    if (recognized.length > target.length &&
        recognized.startsWith('و') &&
        recognized.substring(1) == target) {
      return _MatchQuality.close;
    }
    if (target.length > recognized.length &&
        target.startsWith('و') &&
        target.substring(1) == recognized) {
      return _MatchQuality.close;
    }

    // Dagger Alef / Alif normalization differences:
    // e.g. "مالك" vs "ملك", "الرحمن" vs "الرحمان"
    if ((target == 'مالك' && recognized == 'ملك') ||
        (target == 'ملك' && recognized == 'مالك')) {
      return _MatchQuality.close;
    }
    if ((target == 'الرحمن' && recognized == 'الرحمان') ||
        (target == 'الرحمان' && recognized == 'الرحمن')) {
      return _MatchQuality.close;
    }

    // Levenshtein edit distance check:
    final dist = _levenshtein(target, recognized);
    if (dist <= 1 && target.length >= 4 && recognized.length >= 4) {
      return _MatchQuality.close;
    }

    return _MatchQuality.mismatch;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    var v0 = List<int>.generate(t.length + 1, (i) => i);
    var v1 = List<int>.filled(t.length + 1, 0);

    for (var i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (var j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }
}

enum _MatchQuality { exact, close, mismatch }
