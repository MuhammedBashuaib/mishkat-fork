import 'dart:math';

import 'dart:typed_data';

import '../../data/models/oral_recitation_models.dart';
import '../../data/models/quran_models.dart';
import 'quran_search_normalizer.dart';
import 'quran_recitation_text.dart';

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
    this.correctionWordIndex,
    this.hasReliableSpeech = true,
    this.displayWordIndex,
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

  /// First position requiring a retry in guided recitation.
  final int? correctionWordIndex;

  /// False for silence, discarded hallucinations, unrelated speech or low confidence.
  final bool hasReliableSpeech;

  /// Last word supported by the current utterance, rather than the next unread
  /// word. Follow-mode views use this to avoid opening the next page early.
  final int? displayWordIndex;
}

/// Aligns speech segments against the Quran without treating fuzzy similarity as
/// correctness. The uncommitted suffix can be retried; committed words never
/// move backwards. Partial hypotheses are replaceable until a segment is final.
class QuranAlignmentEngine {
  const QuranAlignmentEngine();

  static const basmalahNormalized = 'بسم الله الرحمن الرحيم';

  List<AuthoritativeWord> prepareTargetTokens({
    required List<QuranChapter> chapters,
    required int startGlobalAyah,
    required int endGlobalAyah,
  }) {
    final tokens = <AuthoritativeWord>[];
    final start = min(startGlobalAyah, endGlobalAyah);
    final end = max(startGlobalAyah, endGlobalAyah);
    for (final chapter in chapters) {
      for (var ayah = 0; ayah < chapter.ayahs.length; ayah++) {
        final global = chapter.globalStart + ayah;
        if (global < start || global > end) continue;
        for (final word in chapter.ayahs[ayah].split(RegExp(r'\s+'))) {
          if (!QuranRecitationText.hasArabicLetter(word)) continue;
          tokens.add(
            AuthoritativeWord(
              globalAyah: global,
              surah: chapter.number,
              ayahInSurah: ayah + 1,
              wordIndex: tokens.length,
              uthmaniText: word,
              normalizedText: QuranSearchNormalizer.normalize(word),
            ),
          );
        }
      }
    }
    return List.unmodifiable(tokens);
  }

  QuranAlignmentResult align({
    required List<AuthoritativeWord> targetWords,
    required String transcript,
    double confidence = 1.0,
    int committedTargetIndex = 0,
    List<RecitationWordAlignment>? committedAlignedWords,
    List<RecitationDiscrepancy>? committedDiscrepancies,
    bool isFinal = true,
    bool stopAtFirstMistake = false,
    bool commitCompleteAyahsOnPartial = false,
    bool followRecitation = false,
  }) {
    if (followRecitation) {
      return _alignFollowing(
        targetWords: targetWords,
        transcript: transcript,
        confidence: confidence,
        committedTargetIndex: committedTargetIndex,
        committedAlignedWords: committedAlignedWords,
        committedDiscrepancies: committedDiscrepancies,
        isFinal: isFinal,
      );
    }
    final committed = committedTargetIndex.clamp(0, targetWords.length);
    final words = <RecitationWordAlignment>[
      for (var i = 0; i < targetWords.length; i++)
        i < committed && (committedAlignedWords?.length ?? 0) > i
            ? committedAlignedWords![i]
            : RecitationWordAlignment(
                authoritativeWord: targetWords[i],
                status: i < committed
                    ? WordAlignmentStatus.matched
                    : WordAlignmentStatus.upcoming,
              ),
    ];
    var spoken = QuranRecitationText.transcriptWords(transcript);
    if (committed == 0) spoken = _stripIntroduction(spoken, targetWords);

    String? rejectedBackward;
    if (committed > 0 && spoken.isNotEmpty) {
      final history = _stripHistory(spoken, targetWords, committed);
      spoken = spoken.sublist(history);
      if (history > 0) {
        rejectedBackward =
            'Rejected backward match: ignored $history already committed words';
      }
    }

    // VAD produces short utterances. Bound work even if a misbehaving recognizer
    // emits a looping transcript; excess words never invent target progress.
    spoken = spoken.take(256).toList(growable: false);
    final end = min(targetWords.length, committed + spoken.length + 24);
    var cursor = committed;
    var reliable = false;
    int? correction;
    if (spoken.isNotEmpty && committed < targetWords.length) {
      final path = _alignWindow(targetWords.sublist(committed, end), spoken);
      reliable = path.matches > 0 && confidence.isFinite && confidence >= 0.65;
      cursor = committed + path.end;
      if (path.matches == 0) {
        // No Quranic anchor: environmental speech is not a sequence of mistakes.
        cursor = committed;
        words[committed] = RecitationWordAlignment(
          authoritativeWord: targetWords[committed],
          status: WordAlignmentStatus.uncertain,
          recognizedWord: spoken.first == QuranRecitationText.unclearWord
              ? null
              : spoken.first,
          confidence: confidence.isFinite ? confidence.clamp(0, 1) : 0,
        );
        correction = committed;
      } else {
        for (var i = 0; i < path.end; i++) {
          final step = path.words[i];
          if (step == null) continue;
          final status = !reliable || (!isFinal && !step.status.isMatched)
              ? WordAlignmentStatus.uncertain
              : step.status;
          words[committed + i] = RecitationWordAlignment(
            authoritativeWord: targetWords[committed + i],
            status: status,
            recognizedWord: step.recognized,
            confidence: confidence.isFinite ? confidence.clamp(0, 1) : 0,
          );
        }
      }

      if (stopAtFirstMistake) {
        for (var i = committed; i < words.length; i++) {
          if (!words[i].status.isMatched && !words[i].status.isUpcoming) {
            correction = i;
            cursor = i;
            for (var later = i + 1; later < words.length; later++) {
              words[later] = RecitationWordAlignment(
                authoritativeWord: targetWords[later],
                status: WordAlignmentStatus.upcoming,
              );
            }
            break;
          }
        }
      }
    }

    var nextCommitted = committed;
    if (isFinal && reliable) {
      nextCommitted = max(committed, cursor);
    } else if (!isFinal && reliable && commitCompleteAyahsOnPartial) {
      // Explicit legacy opt-in only; the offline guided flow never uses this.
      for (var i = committed; i < cursor; i++) {
        if (!words[i].status.isMatched) break;
        final atBoundary =
            i + 1 == words.length ||
            targetWords[i + 1].globalAyah != targetWords[i].globalAyah;
        if (atBoundary) nextCommitted = i + 1;
      }
    }
    final discrepancies = <RecitationDiscrepancy>[];
    final committedByIndex = <int, RecitationDiscrepancy>{
      for (final d in committedDiscrepancies ?? <RecitationDiscrepancy>[])
        if (d.wordIndex < committed) d.wordIndex: d,
    };
    final ayahs = <int, List<RecitationWordAlignment>>{};
    var matched = 0;
    var omissions = 0;
    var substitutions = 0;
    var uncertain = 0;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      ayahs.putIfAbsent(word.authoritativeWord.globalAyah, () => []).add(word);
      switch (word.status) {
        case WordAlignmentStatus.matched:
          matched++;
        case WordAlignmentStatus.omission:
          omissions++;
        case WordAlignmentStatus.substitution:
          substitutions++;
        case WordAlignmentStatus.uncertain:
          uncertain++;
        case WordAlignmentStatus.repetition:
        case WordAlignmentStatus.upcoming:
          break;
      }
      if (word.status.isOmission ||
          word.status.isSubstitution ||
          word.status.isUncertain) {
        discrepancies.add(
          committedByIndex[word.authoritativeWord.wordIndex] ??
              _discrepancy(word),
        );
      }
    }
    final completedAyahs = <int>{
      for (final entry in ayahs.entries)
        if (entry.value.every((word) => word.status.isMatched) &&
            (isFinal ||
                entry.value.every(
                  (word) => word.authoritativeWord.wordIndex < committed,
                )))
          entry.key,
    };
    final current = targetWords.isEmpty
        ? 0
        : min(cursor, targetWords.length - 1);
    return QuranAlignmentResult(
      alignedWords: List.unmodifiable(words),
      currentGlobalAyah: targetWords.isEmpty
          ? 1
          : targetWords[current].globalAyah,
      currentWordIndex: current,
      discrepancies: List.unmodifiable(discrepancies),
      totalWords: targetWords.length,
      matchedWordsCount: matched,
      omissionsCount: omissions,
      substitutionsCount: substitutions,
      uncertainCount: uncertain,
      progressPercentage: targetWords.isEmpty
          ? 0
          : matched * 100 / targetWords.length,
      isCompleted:
          isFinal &&
          targetWords.isNotEmpty &&
          nextCommitted >= targetWords.length,
      completedGlobalAyahs: Set.unmodifiable(completedAyahs),
      committedTargetIndex: nextCommitted,
      candidateStartIndex: committed,
      candidateEndIndex: end,
      correctionWordIndex: correction,
      hasReliableSpeech: reliable,
      alignmentReason: correction != null
          ? 'Retry target word $correction; committed prefix $nextCommitted'
          : '${isFinal ? 'Final' : 'Provisional'} segment: cursor $cursor, committed $nextCommitted',
      rejectedBackwardCandidate: rejectedBackward,
    );
  }

  /// Local, anchored following. A finalized mistake records an attempted word
  /// and does not erase correct words that follow it. Unlike the legacy global
  /// edit-distance search, this path never searches ahead into a later ayah.
  QuranAlignmentResult _alignFollowing({
    required List<AuthoritativeWord> targetWords,
    required String transcript,
    required double confidence,
    required int committedTargetIndex,
    required List<RecitationWordAlignment>? committedAlignedWords,
    required List<RecitationDiscrepancy>? committedDiscrepancies,
    required bool isFinal,
  }) {
    final committed = committedTargetIndex.clamp(0, targetWords.length);
    final words = <RecitationWordAlignment>[
      for (var i = 0; i < targetWords.length; i++)
        (i < committed ||
                    (i == committed &&
                        (committedAlignedWords?.length ?? 0) > i &&
                        committedAlignedWords![i].status.isUncertain)) &&
                (committedAlignedWords?.length ?? 0) > i
            ? committedAlignedWords![i]
            : RecitationWordAlignment(
                authoritativeWord: targetWords[i],
                status: i < committed
                    ? WordAlignmentStatus.matched
                    : WordAlignmentStatus.upcoming,
              ),
    ];
    var spoken = QuranRecitationText.transcriptWords(transcript);
    if (committed == 0) spoken = _stripIntroduction(spoken, targetWords);
    spoken = spoken.take(256).toList(growable: false);
    var cursor = committed;
    var heard = 0;
    var display = committed > 0 ? committed - 1 : 0;
    var reliable = false;
    final validConfidence = confidence.isFinite && confidence >= .65;

    void mark(int index, WordAlignmentStatus status, String? recognized) {
      words[index] = RecitationWordAlignment(
        authoritativeWord: targetWords[index],
        status: status,
        recognizedWord: recognized,
        confidence: confidence.isFinite ? confidence.clamp(0, 1) : 0,
      );
      display = max(display, index);
    }

    if (spoken.isNotEmpty && validConfidence) {
      // Prefer the live frontier over an identical historical phrase. History
      // may repair errors only on a final result, never on a partial hypothesis.
      final history = _followingHistory(targetWords, words, spoken, committed);
      if (history != null) {
        heard = history.$2;
        reliable = true;
        if (isFinal) {
          for (var i = history.$1; i < history.$3; i++) {
            if (!words[i].status.isMatched) {
              mark(i, WordAlignmentStatus.matched, targetWords[i].uthmaniText);
            }
          }
        }
      }

      while (heard < spoken.length && cursor < targetWords.length) {
        // A page range can continue into the next Surah. Its unnumbered
        // basmala is optional spoken context, never a scored Quran word.
        // Check only the first word of that Surah; never search through speech
        // or consume the Fatiha's numbered basmala (or add one to Tawba).
        final basmala = _boundaryBasmalaLength(
          targetWords,
          cursor,
          spoken,
          heard,
          isFinal: isFinal,
        );
        if (basmala > 0) {
          heard += basmala;
          continue;
        }
        final exact = _followingMatch(targetWords, cursor, spoken, heard);
        if (exact != null) {
          final recognized = spoken.sublist(heard, heard + exact.$2).join(' ');
          for (var count = 0; count < exact.$1; count++) {
            mark(cursor + count, WordAlignmentStatus.matched, recognized);
          }
          cursor += exact.$1;
          heard += exact.$2;
          reliable = true;
          continue;
        }

        // Repeating a word just read is harmless, but must not search forward
        // for an occurrence of it in an unrelated later ayah.
        if (cursor > 0 &&
            QuranRecitationText.sameWord(
              targetWords[cursor - 1].uthmaniText,
              spoken[heard],
            )) {
          heard++;
          continue;
        }

        final anchoredAyah = _followingHasAyahAnchor(
          targetWords,
          words,
          cursor,
        );
        final nextIsSameAyah =
            cursor + 1 < targetWords.length &&
            targetWords[cursor + 1].globalAyah ==
                targetWords[cursor].globalAyah;

        // A nearby, actually spoken continuation anchors a substitution. At an
        // ayah boundary require the next ayah's complete opening (two words).
        if (cursor + 1 < targetWords.length &&
            heard + 1 < spoken.length &&
            _followingAnchor(
              targetWords,
              cursor + 1,
              spoken,
              heard + 1,
              allowSingleAtEnd: anchoredAyah && nextIsSameAyah,
            ) &&
            (nextIsSameAyah || anchoredAyah)) {
          mark(
            cursor,
            isFinal && spoken[heard] != QuranRecitationText.unclearWord
                ? WordAlignmentStatus.substitution
                : WordAlignmentStatus.uncertain,
            spoken[heard],
          );
          cursor++;
          heard++;
          reliable = true;
          continue;
        }

        // A wrong attempt immediately followed by the correct word is a
        // self-correction, not a substitution plus a second word.
        var retry = -1;
        for (
          var offset = 1;
          offset <= 2 && heard + offset < spoken.length;
          offset++
        ) {
          if (_followingMatch(targetWords, cursor, spoken, heard + offset) !=
              null) {
            retry = heard + offset;
            break;
          }
        }
        if (retry >= 0) {
          heard = retry;
          continue;
        }

        // The reader can restart the current ayah to correct its last word in
        // one breath. Only an exact prefix returning to this position qualifies.
        final restart = _followingRestart(targetWords, cursor, spoken, heard);
        if (restart != null) {
          heard = restart;
          continue;
        }

        // A skip needs close, explicit continuation. Never fill a whole missed
        // ayah or bridge more than two words just to reach a common phrase.
        var skipped = 0;
        for (
          var gap = 1;
          gap <= 2 && cursor + gap < targetWords.length;
          gap++
        ) {
          final anchor = cursor + gap;
          final sameAyah =
              targetWords[anchor].globalAyah == targetWords[cursor].globalAyah;
          final lastWordOfKnownAyah = gap == 1 && anchoredAyah && !sameAyah;
          if (!sameAyah && !lastWordOfKnownAyah) break;
          if (_followingAnchor(
            targetWords,
            anchor,
            spoken,
            heard,
            allowSingleAtEnd: anchoredAyah && sameAyah,
          )) {
            skipped = gap;
            break;
          }
        }
        if (skipped > 0) {
          for (var count = 0; count < skipped; count++) {
            mark(
              cursor + count,
              isFinal && !words[cursor + count].status.isUncertain
                  ? WordAlignmentStatus.omission
                  : WordAlignmentStatus.uncertain,
              null,
            );
          }
          cursor += skipped;
          reliable = true;
          continue;
        }

        // A single final word within an established ayah can be located from
        // that context. For an isolated new segment require lexical proximity;
        // unrelated room speech is never promoted to a definite error.
        final trailing = heard + 1 == spoken.length;
        final near =
            QuranRecitationText.similarity(
              targetWords[cursor].uthmaniText,
              spoken[heard],
            ) >=
            .5;
        if (trailing &&
            anchoredAyah &&
            spoken[heard] != QuranRecitationText.unclearWord &&
            (heard > 0 || near)) {
          mark(
            cursor,
            isFinal
                ? WordAlignmentStatus.substitution
                : WordAlignmentStatus.uncertain,
            spoken[heard],
          );
          cursor++;
          heard++;
          reliable = true;
          continue;
        }

        mark(
          cursor,
          WordAlignmentStatus.uncertain,
          spoken[heard] == QuranRecitationText.unclearWord
              ? null
              : spoken[heard],
        );
        break;
      }
    } else if (spoken.isNotEmpty && cursor < targetWords.length) {
      mark(cursor, WordAlignmentStatus.uncertain, spoken.first);
    }

    final nextCommitted = isFinal && reliable
        ? max(committed, cursor)
        : committed;
    final discrepancies = <RecitationDiscrepancy>[];
    final previousDiscrepancies = {
      for (final d in committedDiscrepancies ?? <RecitationDiscrepancy>[])
        d.wordIndex: d,
    };
    final ayahs = <int, List<RecitationWordAlignment>>{};
    var matched = 0;
    var omissions = 0;
    var substitutions = 0;
    var uncertain = 0;
    int? correction;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      (ayahs[word.authoritativeWord.globalAyah] ??= []).add(word);
      if (word.status.isMatched) matched++;
      if (word.status.isOmission) omissions++;
      if (word.status.isSubstitution) substitutions++;
      if (word.status.isUncertain) uncertain++;
      if (word.status.isOmission ||
          word.status.isSubstitution ||
          word.status.isUncertain) {
        correction ??= i;
        final previous = previousDiscrepancies[i];
        discrepancies.add(
          previous != null &&
                  previous.status == word.status &&
                  previous.recognizedWord == word.recognizedWord
              ? previous
              : _discrepancy(word),
        );
      }
    }
    final completed = <int>{
      for (final entry in ayahs.entries)
        if (entry.value.every((word) => word.status.isMatched) &&
            (isFinal ||
                entry.value.every(
                  (word) => word.authoritativeWord.wordIndex < committed,
                )))
          entry.key,
    };
    final current = targetWords.isEmpty
        ? 0
        : min(cursor, targetWords.length - 1);
    return QuranAlignmentResult(
      alignedWords: List.unmodifiable(words),
      currentGlobalAyah: targetWords.isEmpty
          ? 1
          : targetWords[current].globalAyah,
      currentWordIndex: current,
      displayWordIndex: targetWords.isEmpty
          ? 0
          : display.clamp(0, targetWords.length - 1),
      discrepancies: List.unmodifiable(discrepancies),
      totalWords: words.length,
      matchedWordsCount: matched,
      omissionsCount: omissions,
      substitutionsCount: substitutions,
      uncertainCount: uncertain,
      progressPercentage: words.isEmpty ? 0 : matched * 100 / words.length,
      isCompleted: isFinal && words.isNotEmpty && nextCommitted >= words.length,
      completedGlobalAyahs: Set.unmodifiable(completed),
      committedTargetIndex: nextCommitted,
      candidateStartIndex: committed,
      candidateEndIndex: cursor,
      correctionWordIndex: correction,
      hasReliableSpeech: reliable,
      alignmentReason:
          'Anchored following: cursor $cursor, committed $nextCommitted',
    );
  }

  static int _boundaryBasmalaLength(
    List<AuthoritativeWord> target,
    int cursor,
    List<String> spoken,
    int heard, {
    required bool isFinal,
  }) {
    if (cursor <= 0 || cursor >= target.length) return 0;
    final next = target[cursor];
    if (next.surah == 1 ||
        next.surah == 9 ||
        next.ayahInSurah != 1 ||
        target[cursor - 1].surah == next.surah) {
      return 0;
    }
    const basmala = ['بسم', 'الله', 'الرحمن', 'الرحيم'];
    final count = min(basmala.length, spoken.length - heard);
    if (count < basmala.length && isFinal) return 0;
    for (var i = 0; i < count; i++) {
      if (!QuranRecitationText.sameWord(spoken[heard + i], basmala[i])) {
        return 0;
      }
    }
    // A live prefix may wait for the remaining words without creating a
    // provisional Quran error. Neither it nor a full basmala advances cursor.
    return count;
  }

  /// Returns (target word count, transcript token count) for exact orthography.
  static (int, int)? _followingMatch(
    List<AuthoritativeWord> target,
    int at,
    List<String> spoken,
    int heard,
  ) {
    if (at >= target.length || heard >= spoken.length) return null;
    final forms = QuranRecitationText.spellings(target[at].uthmaniText);
    final key = QuranRecitationText.normalize(spoken[heard]);
    if (forms.contains(key)) return (1, 1);
    for (var count = 2; count <= 3 && heard + count <= spoken.length; count++) {
      final joined = spoken
          .sublist(heard, heard + count)
          .map(QuranRecitationText.normalize)
          .join();
      if (forms.contains(joined)) return (1, count);
    }
    if (target[at].ayahInSurah <= 2) {
      final names = QuranRecitationText
          .letterNames[QuranRecitationText.normalize(target[at].uthmaniText)];
      if (names != null) {
        if (key.replaceAll('ء', '') == names.join()) return (1, 1);
        if (heard + names.length <= spoken.length &&
            spoken
                    .sublist(heard, heard + names.length)
                    .map(QuranRecitationText.normalize)
                    .join()
                    .replaceAll('ء', '') ==
                names.join()) {
          return (1, names.length);
        }
      }
    }
    if (at + 1 < target.length &&
        target[at + 1].globalAyah == target[at].globalAyah) {
      final next = QuranRecitationText.spellings(target[at + 1].uthmaniText);
      if (forms.any((a) => next.any((b) => a + b == key))) return (2, 1);
    }
    return null;
  }

  static bool _followingAnchor(
    List<AuthoritativeWord> target,
    int at,
    List<String> spoken,
    int heard, {
    required bool allowSingleAtEnd,
  }) {
    final ayah = target[at].globalAyah;
    var count = 0;
    var cursor = at;
    var input = heard;
    while (cursor < target.length &&
        target[cursor].globalAyah == ayah &&
        input < spoken.length) {
      final match = _followingMatch(target, cursor, spoken, input);
      if (match == null) break;
      count += match.$1;
      cursor += match.$1;
      input += match.$2;
      if (count >= 2) return true;
    }
    final completeAyah =
        cursor == target.length || target[cursor].globalAyah != ayah;
    final entireSingleWordAyah =
        (at == 0 || target[at - 1].globalAyah != ayah) && completeAyah;
    return count == 1 &&
        completeAyah &&
        (allowSingleAtEnd || entireSingleWordAyah);
  }

  static bool _followingHasAyahAnchor(
    List<AuthoritativeWord> target,
    List<RecitationWordAlignment> words,
    int cursor,
  ) {
    for (
      var i = cursor - 1;
      i >= 0 && target[i].globalAyah == target[cursor].globalAyah;
      i--
    ) {
      if (words[i].status.isMatched) return true;
    }
    return false;
  }

  /// Returns (history start, consumed speech tokens, history end). Ordinary
  /// repetition is restricted to the latest two ayahs; an outstanding error
  /// keeps its ayah available for an explicit repair even after finishing.
  static (int, int, int)? _followingHistory(
    List<AuthoritativeWord> target,
    List<RecitationWordAlignment> words,
    List<String> spoken,
    int committed,
  ) {
    if (committed == 0 ||
        spoken.isEmpty ||
        _followingMatch(target, committed, spoken, 0) != null) {
      return null;
    }
    var historyStart = committed - 1;
    var ayahsSeen = 1;
    while (historyStart > 0) {
      if (target[historyStart - 1].globalAyah !=
          target[historyStart].globalAyah) {
        if (++ayahsSeen > 2) break;
      }
      historyStart--;
    }
    final errorAyahs = <int>{
      for (var i = 0; i < committed; i++)
        if (words[i].status.isOmission ||
            words[i].status.isSubstitution ||
            words[i].status.isUncertain)
          target[i].globalAyah,
    };
    final isolatedRepairCandidates = <int>{};
    for (var i = 0; i < committed; i++) {
      if (!words[i].status.isOmission &&
          !words[i].status.isSubstitution &&
          !words[i].status.isUncertain) {
        continue;
      }
      final exact = _followingMatch(target, i, spoken, 0);
      if (exact != null && exact.$1 == 1 && exact.$2 == spoken.length) {
        isolatedRepairCandidates.add(i);
      }
    }
    (int, int, int)? best;
    var bestRepairsError = false;
    for (var start = 0; start < committed; start++) {
      if (start < historyStart &&
          !errorAyahs.contains(target[start].globalAyah)) {
        continue;
      }
      var cursor = start;
      var heard = 0;
      var repaired = false;
      while (cursor < committed && heard < spoken.length) {
        final match = _followingMatch(target, cursor, spoken, heard);
        if (match == null || cursor + match.$1 > committed) break;
        for (var count = 0; count < match.$1; count++) {
          repaired |=
              words[cursor + count].status.isOmission ||
              words[cursor + count].status.isSubstitution ||
              words[cursor + count].status.isUncertain;
        }
        cursor += match.$1;
        heard += match.$2;
      }
      if (heard == 0 || (heard != spoken.length && cursor != committed)) {
        continue;
      }
      // A one-word correction is accepted only at an existing error; other
      // one-word historical repeats are ignored, never treated as new progress.
      if (repaired && cursor - start == 1 && spoken.length != heard) continue;
      if (repaired &&
          cursor - start == 1 &&
          isolatedRepairCandidates.length != 1) {
        continue;
      }
      if (best == null ||
          (repaired && !bestRepairsError) ||
          (repaired == bestRepairsError &&
              (heard > best.$2 || (heard == best.$2 && start > best.$1)))) {
        best = (start, heard, cursor);
        bestRepairsError = repaired;
      }
    }
    return best;
  }

  static int? _followingRestart(
    List<AuthoritativeWord> target,
    int cursor,
    List<String> spoken,
    int heard,
  ) {
    var start = cursor;
    while (start > 0 &&
        target[start - 1].globalAyah == target[cursor].globalAyah) {
      start--;
    }
    if (cursor - start < 2) return null;
    for (
      var retry = heard + 1;
      retry < min(spoken.length, heard + 32);
      retry++
    ) {
      var at = start;
      var input = retry;
      while (at < cursor && input < spoken.length) {
        final match = _followingMatch(target, at, spoken, input);
        if (match == null || at + match.$1 > cursor) break;
        at += match.$1;
        input += match.$2;
      }
      if (at == cursor &&
          _followingMatch(target, cursor, spoken, input) != null) {
        return input;
      }
    }
    return null;
  }

  static List<String> _stripIntroduction(
    List<String> words,
    List<AuthoritativeWord> target,
  ) {
    if (words.isEmpty || target.isEmpty) return words;
    var offset = 0;
    const istiatha = ['اعوذ', 'بالله', 'من', 'الشيطان', 'الرجيم'];
    const basmala = ['بسم', 'الله', 'الرحمن', 'الرحيم'];
    final keys = words.map(QuranRecitationText.normalize).toList();
    if (_prefix(keys, istiatha)) {
      if (keys.length < istiatha.length) return const [];
      offset = istiatha.length;
    }
    final targetIsBasmala =
        target.length >= 4 &&
        QuranRecitationText.sameWord(target[0].uthmaniText, 'بسم') &&
        QuranRecitationText.sameWord(target[1].uthmaniText, 'الله');
    if (!targetIsBasmala && _prefix(keys.sublist(offset), basmala)) {
      offset += min(basmala.length, keys.length - offset);
    }
    return words.sublist(offset);
  }

  static bool _prefix(List<String> words, List<String> prefix) =>
      words.isNotEmpty &&
      List.generate(
        min(words.length, prefix.length),
        (i) => i,
      ).every((i) => words[i] == prefix[i]);

  /// Prefer the current frontier when the same phrase occurs twice (الفاتحة).
  /// Otherwise a reader may restart the recent ayah to correct the gated word.
  static int _stripHistory(
    List<String> spoken,
    List<AuthoritativeWord> target,
    int committed,
  ) {
    if (committed < target.length &&
        QuranRecitationText.sameWord(
          target[committed].uthmaniText,
          spoken.first,
        )) {
      return 0;
    }
    var best = 0;
    // Probe the complete cumulative prefix once, then only the recent ayah
    // context. A long surah must not trigger a scan of thousands of old words
    // on every microphone segment.
    final starts = <int>{
      0,
      for (var i = max(1, committed - 32); i < committed; i++) i,
    };
    for (final start in starts) {
      var count = 0;
      while (start + count < committed &&
          count < spoken.length &&
          QuranRecitationText.sameWord(
            target[start + count].uthmaniText,
            spoken[count],
          )) {
        count++;
      }
      // An entire older utterance is harmless repetition; a prefix ending at
      // the frontier is an intentional restart, not a new set of omissions.
      if ((count == spoken.length || start + count == committed) &&
          count > best) {
        best = count;
      }
    }
    return best;
  }

  static RecitationDiscrepancy _discrepancy(RecitationWordAlignment word) {
    final target = word.authoritativeWord;
    final explanation = switch (word.status) {
      WordAlignmentStatus.omission =>
        'سقط في التلاوة: لم تُسمع كلمة «${target.uthmaniText}». أعدها للتأكد.',
      WordAlignmentStatus.substitution =>
        'خطأ أو استبدال محتمل: سُمعت «${word.recognizedWord}» بدلاً من «${target.uthmaniText}». أعد الكلمة للتأكد.',
      _ =>
        'التقاط صوتي غير مؤكد. أعد «${target.uthmaniText}» بوضوح؛ لا تُحسب خطأً في الحفظ.',
    };
    return RecitationDiscrepancy(
      id: 'disc_${word.status.name}_${target.globalAyah}_${target.wordIndex}',
      globalAyah: target.globalAyah,
      surah: target.surah,
      ayahInSurah: target.ayahInSurah,
      wordIndex: target.wordIndex,
      expectedUthmani: target.uthmaniText,
      expectedNormalized: target.normalizedText,
      recognizedWord: word.recognizedWord,
      status: word.status,
      explanation: explanation,
    );
  }

  static _Path _alignWindow(
    List<AuthoritativeWord> target,
    List<String> spoken,
  ) {
    final n = target.length;
    final m = spoken.length;
    final scores = List.generate(
      n + 1,
      (_) => Float64List(m + 1)..fillRange(0, m + 1, double.negativeInfinity),
    );
    final operations = List.generate(n + 1, (_) => Uint8List(m + 1));
    final spans = List.generate(n + 1, (_) => Uint8List(m + 1));
    final forms = target
        .map((word) => QuranRecitationText.spellings(word.uthmaniText))
        .toList();
    for (var i = 0; i < target.length; i++) {
      if (target[i].ayahInSurah <= 2) {
        final names = QuranRecitationText
            .letterNames[QuranRecitationText.normalize(target[i].uthmaniText)];
        if (names != null) forms[i].add(names.join());
      }
    }
    final keys = spoken.map(QuranRecitationText.normalize).toList();
    final similarities = List.generate(
      n,
      (i) => List.generate(
        m,
        (j) => forms[i].contains(keys[j])
            ? 1.0
            : QuranRecitationText.similarity(target[i].uthmaniText, spoken[j]),
      ),
    );
    scores[0][0] = 0;
    for (var i = 0; i <= n; i++) {
      for (var j = 0; j <= m; j++) {
        if (i == 0 && j == 0) continue;
        var best = double.negativeInfinity;
        var op = 0;
        var span = 1;
        if (i > 0 && j > 0) {
          final unclear = spoken[j - 1] == QuranRecitationText.unclearWord;
          final similarity = similarities[i - 1][j - 1];
          best =
              scores[i - 1][j - 1] +
              (unclear
                  ? 0.2
                  : similarity == 1
                  ? 2
                  : 2 * similarity - 1.2);
          op = unclear ? 7 : 1;
        }
        if (i > 0 && scores[i - 1][j] - 0.6 > best) {
          best = scores[i - 1][j] - 0.6;
          op = 2;
        }
        if (j > 0) {
          final repeat = i > 0 && forms[i - 1].contains(keys[j - 1]);
          final extra =
              scores[i][j - 1] -
              (repeat || spoken[j - 1] == QuranRecitationText.unclearWord
                  ? 0.05
                  : 0.5);
          if (extra > best) {
            best = extra;
            op = repeat ? 4 : 3;
          }
        }
        if (i > 0) {
          // A recognizer may split a single Quranic word: و الذين / يا أيها.
          for (var count = 2; count <= 3 && count <= j; count++) {
            if (forms[i - 1].contains(keys.sublist(j - count, j).join()) &&
                scores[i - 1][j - count] + 2 > best) {
              best = scores[i - 1][j - count] + 2;
              op = 5;
              span = count;
            }
          }
          // Muqattaat are letter names, not approximate matches to prose words.
          if (target[i - 1].ayahInSurah <= 2) {
            final names =
                QuranRecitationText.letterNames[QuranRecitationText.normalize(
                  target[i - 1].uthmaniText,
                )];
            if (names != null && j >= names.length) {
              final joined = keys
                  .sublist(j - names.length, j)
                  .join()
                  .replaceAll('ء', '');
              if (joined == names.join() &&
                  scores[i - 1][j - names.length] + 2 > best) {
                best = scores[i - 1][j - names.length] + 2;
                op = 5;
                span = names.length;
              }
            }
          }
        }
        if (i >= 2 &&
            j > 0 &&
            target[i - 1].globalAyah == target[i - 2].globalAyah) {
          final joined = forms[i - 2].any(
            (a) => forms[i - 1].any((b) => a + b == keys[j - 1]),
          );
          if (joined && scores[i - 2][j - 1] + 4 > best) {
            best = scores[i - 2][j - 1] + 4;
            op = 6;
          }
        }
        scores[i][j] = best;
        operations[i][j] = op;
        spans[i][j] = span;
      }
    }
    var end = 0;
    for (var i = 1; i <= n; i++) {
      if (scores[i][m] > scores[end][m]) end = i;
    }
    final words = List<_Step?>.filled(n, null);
    var i = end;
    var j = m;
    var matches = 0;
    String? trailing;
    var atTail = true;
    while (i > 0 || j > 0) {
      final op = operations[i][j];
      if (op == 3 &&
          atTail &&
          spoken[j - 1] != QuranRecitationText.unclearWord) {
        trailing = spoken[j - 1];
      } else if (op != 4 && op != 3) {
        atTail = false;
      }
      switch (op) {
        case 1:
          final matched = similarities[i - 1][j - 1] == 1;
          words[i - 1] = _Step(
            matched
                ? WordAlignmentStatus.matched
                : WordAlignmentStatus.substitution,
            spoken[j - 1],
          );
          if (matched) matches++;
          i--;
          j--;
        case 2:
          words[i - 1] = const _Step(WordAlignmentStatus.omission, null);
          i--;
        case 3:
        case 4:
          j--;
        case 5:
          final count = spans[i][j];
          words[i - 1] = _Step(
            WordAlignmentStatus.matched,
            spoken.sublist(j - count, j).join(' '),
          );
          matches++;
          i--;
          j -= count;
        case 6:
          words[i - 1] = _Step(WordAlignmentStatus.matched, spoken[j - 1]);
          words[i - 2] = _Step(WordAlignmentStatus.matched, spoken[j - 1]);
          matches += 2;
          i -= 2;
          j--;
        case 7:
          words[i - 1] = const _Step(WordAlignmentStatus.uncertain, null);
          i--;
          j--;
        default:
          i = 0;
          j = 0;
      }
    }
    // Free target suffixes must stay upcoming; only an actually spoken trailing
    // mismatch can occupy the next position (never infer unrecited omissions).
    if (trailing != null && end < n) {
      words[end++] = _Step(WordAlignmentStatus.substitution, trailing);
    }
    return _Path(words, end, matches);
  }
}

class _Step {
  const _Step(this.status, this.recognized);
  final WordAlignmentStatus status;
  final String? recognized;
}

class _Path {
  const _Path(this.words, this.end, this.matches);
  final List<_Step?> words;
  final int end;
  final int matches;
}
