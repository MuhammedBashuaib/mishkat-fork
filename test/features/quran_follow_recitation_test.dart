import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_alignment_engine.dart';

void main() {
  const engine = QuranAlignmentEngine();
  List<AuthoritativeWord> target(List<String> ayahs) =>
      engine.prepareTargetTokens(
        chapters: [
          QuranChapter(
            number: 78,
            name: 'النبأ',
            englishName: 'An-Naba',
            revelationType: 'Meccan',
            page: 582,
            globalStart: 1,
            ayahs: ayahs,
          ),
        ],
        startGlobalAyah: 1,
        endGlobalAyah: ayahs.length,
      );
  final naba = target([
    'عَمَّ يَتَسَآءَلُونَ',
    'عَنِ ٱلنَّبَإِ ٱلْعَظِيمِ',
    'ٱلَّذِى هُمْ فِيهِ مُخْتَلِفُونَ',
    'كَلَّا سَيَعْلَمُونَ',
    'ثُمَّ كَلَّا سَيَعْلَمُونَ',
  ]);
  QuranAlignmentResult read(
    List<AuthoritativeWord> words,
    String text, {
    QuranAlignmentResult? after,
    bool isFinal = true,
    double confidence = 1,
  }) => engine.align(
    targetWords: words,
    transcript: text,
    committedTargetIndex: after?.committedTargetIndex ?? 0,
    committedAlignedWords: after?.alignedWords,
    committedDiscrepancies: after?.discrepancies,
    isFinal: isFinal,
    confidence: confidence,
    followRecitation: true,
  );

  test(
    'substitution remains fixed while following correctly recited next ayah',
    () {
      final first = read(
        naba,
        'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون',
      );
      expect(first.committedTargetIndex, 9);
      expect(first.alignedWords[8].status, WordAlignmentStatus.substitution);
      expect(first.alignedWords[8].recognizedWord, 'يختلفون');
      expect(first.completedGlobalAyahs, {1, 2});
      expect(
        first.alignedWords.skip(9).every((w) => w.status.isUpcoming),
        isTrue,
      );
      final second = read(naba, 'كلا سيعلمون', after: first);
      expect(second.committedTargetIndex, 11);
      expect(second.completedGlobalAyahs, {1, 2, 4});
      expect(second.alignedWords[8], first.alignedWords[8]);
      expect(second.discrepancies.single.recognizedWord, 'يختلفون');
      expect(second.correctionWordIndex, 8);
      expect(
        second.alignedWords.skip(11).every((w) => w.status.isUpcoming),
        isTrue,
      );
      final last = read(naba, 'ثم كلا سيعلمون', after: second);
      expect(last.committedTargetIndex, 14);
      expect(last.substitutionsCount, 1);
      expect(last.matchedWordsCount, 13);
    },
  );

  test(
    'isolated close inflection mismatch is a substitution in known context',
    () {
      final words = target([
        'إِنَّ رَبَّكَ يَقْضِي بَيْنَهُمْ يَوْمَ الْقِيَامَةِ فِيمَا كَانُوا فِيهِ يَخْتَلِفُونَ',
      ]);
      final first = read(words, 'إن ربك يقضي بينهم يوم القيامة فيما كانوا فيه');
      final wrong = read(words, 'مختلفين', after: first);
      expect(wrong.substitutionsCount, 1);
      expect(
        wrong.alignedWords.last.authoritativeWord.uthmaniText,
        'يَخْتَلِفُونَ',
      );
      expect(wrong.alignedWords.last.recognizedWord, 'مختلفين');
      expect(wrong.committedTargetIndex, words.length);
    },
  );

  test('isolated correction repairs prior error without moving frontier or double counting', () {
    final wrong = read(
      naba,
      'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون كلا سيعلمون',
    );
    expect(wrong.committedTargetIndex, 11);
    final fixed = read(naba, 'مختلفون', after: wrong);
    expect(fixed.committedTargetIndex, 11);
    expect(fixed.matchedWordsCount, 11);
    expect(fixed.discrepancies, isEmpty);
    expect(fixed.correctionWordIndex, isNull);
    expect(fixed.completedGlobalAyahs, {1, 2, 3, 4});
    final twice = read(naba, 'مختلفون', after: fixed);
    expect(twice.committedTargetIndex, 11);
    expect(twice.matchedWordsCount, 11);
    expect(twice.discrepancies, isEmpty);
  });

  test('complete recent ayah can be reread to repair its mistake', () {
    final wrong = read(
      naba,
      'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون كلا سيعلمون',
    );
    final fixed = read(naba, 'الذي هم فيه مختلفون', after: wrong);
    expect(fixed.committedTargetIndex, 11);
    expect(fixed.discrepancies, isEmpty);
    expect(fixed.matchedWordsCount, 11);
  });

  test(
    'outstanding error remains repairable after later ayahs and passage end',
    () {
      final wrong = read(
        naba,
        'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون كلا سيعلمون ثم كلا سيعلمون',
      );
      expect(wrong.committedTargetIndex, 14);
      for (final text in ['مختلفون', 'الذي هم فيه مختلفون']) {
        final fixed = read(naba, text, after: wrong);
        expect(fixed.committedTargetIndex, 14);
        expect(fixed.matchedWordsCount, 14);
        expect(fixed.discrepancies, isEmpty);
        expect(fixed.correctionWordIndex, isNull);
      }
    },
  );

  test('partial correction never rewrites a saved final mistake', () {
    final wrong = read(naba, 'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون');
    for (final text in ['مختلفون', 'الذي هم فيه مختلفون']) {
      final partial = read(naba, text, after: wrong, isFinal: false);
      expect(partial.committedTargetIndex, 9);
      expect(partial.alignedWords[8], wrong.alignedWords[8]);
      expect(partial.substitutionsCount, 1);
      expect(partial.completedGlobalAyahs, {1, 2});
    }
  });

  test(
    'silence and unrelated speech cannot remove or replace final errors',
    () {
      final wrong = read(
        naba,
        'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون',
      );
      for (final text in ['', '[صمت]', 'السيارة في الشارع مزدحم']) {
        final next = read(naba, text, after: wrong);
        expect(next.committedTargetIndex, 9);
        expect(next.alignedWords[8], wrong.alignedWords[8]);
        expect(next.substitutionsCount, 1);
        expect(next.completedGlobalAyahs, {1, 2});
        expect(
          next.alignedWords.skip(10).every((w) => w.status.isUpcoming),
          isTrue,
        );
      }
    },
  );

  test('does not erase an unrecited ayah to jump to repeated common words', () {
    final first = read(naba, 'عم يتساءلون');
    for (final text in ['كلا', 'كلا سيعلمون', 'ثم كلا سيعلمون', 'الله']) {
      final next = read(naba, text, after: first);
      expect(next.committedTargetIndex, 2, reason: text);
      expect(next.omissionsCount, 0, reason: text);
      expect(
        next.alignedWords.skip(3).every((w) => w.status.isUpcoming),
        isTrue,
        reason: text,
      );
    }
  });

  test(
    'common anchor across ayah boundary cannot skip preceding complete ayah',
    () {
      final words = target([
        'قُلْ هُوَ اللَّهُ أَحَدٌ',
        'اللَّهُ الصَّمَدُ',
        'لَمْ يَلِدْ وَلَمْ يُولَدْ',
      ]);
      final next = read(words, 'الله الصمد');
      expect(next.committedTargetIndex, 0);
      expect(next.omissionsCount, 0);
      expect(next.matchedWordsCount, 0);
      expect(
        next.alignedWords.skip(1).every((w) => w.status.isUpcoming),
        isTrue,
      );
    },
  );

  test('next ayah remains entirely upcoming until actually spoken', () {
    final result = read(
      naba,
      'عم يتساءلون عن النبإ العظيم الذي هم فيه مختلفون',
    );
    expect(result.committedTargetIndex, 9);
    expect(result.displayWordIndex, 8);
    expect(
      result.alignedWords.skip(9).every((w) => w.status.isUpcoming),
      isTrue,
    );
    final partial = read(naba, 'كلا', after: result, isFinal: false);
    expect(partial.alignedWords[9].status, WordAlignmentStatus.matched);
    expect(partial.alignedWords[10].status, WordAlignmentStatus.upcoming);
    expect(
      partial.alignedWords.skip(11).every((w) => w.status.isUpcoming),
      isTrue,
    );
    expect(partial.completedGlobalAyahs, {1, 2, 3});
    expect(partial.committedTargetIndex, 9);
    expect(partial.displayWordIndex, 9);
  });

  test('partial revisions are deterministic and do not alter the committed history', () {
    final first = read(naba, 'عم يتساءلون عن النبإ العظيم');
    final long = read(
      naba,
      'الذي هم فيه مختلفون كلا',
      after: first,
      isFinal: false,
    );
    final short = read(naba, 'الذي هم فيه', after: first, isFinal: false);
    final again = read(
      naba,
      'الذي هم فيه مختلفون كلا',
      after: first,
      isFinal: false,
    );
    expect(long.alignedWords, again.alignedWords);
    expect(long.committedTargetIndex, 5);
    expect(short.committedTargetIndex, 5);
    expect(
      short.alignedWords.skip(8).every((w) => w.status.isUpcoming),
      isTrue,
    );
    final finalResult = read(naba, 'الذي هم فيه مختلفون كلا', after: first);
    expect(finalResult.alignedWords, long.alignedWords);
    expect(finalResult.committedTargetIndex, 10);
  });

  test('a nearby omission needs an actual same-ayah continuation', () {
    final words = target([
      'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      'الرَّحْمَنِ الرَّحِيمِ',
    ]);
    final result = read(words, 'الحمد لله العالمين');
    expect(result.alignedWords[2].status, WordAlignmentStatus.omission);
    expect(result.alignedWords[3].status, WordAlignmentStatus.matched);
    expect(result.committedTargetIndex, 4);
    expect(
      result.alignedWords.skip(4).every((w) => w.status.isUpcoming),
      isTrue,
    );
    final fixed = read(words, 'رب', after: result);
    expect(fixed.discrepancies, isEmpty);
    expect(fixed.committedTargetIndex, 4);
  });

  test('unfinished speech never invents trailing omissions', () {
    for (final text in ['عم', 'عم يتساءلون عن', 'عم يتساءلون عن النبإ']) {
      final result = read(naba, text);
      expect(result.omissionsCount, 0);
      expect(result.discrepancies, isEmpty);
      expect(
        result.alignedWords
            .skip(result.committedTargetIndex)
            .every((w) => w.status.isUpcoming),
        isTrue,
      );
    }
  });

  test(
    'a complete one-word ayah can anchor continuation after a known ayah',
    () {
      final words = target([
        'هُدًى لِلْمُتَّقِينَ',
        'الٓمٓ',
        'ذَلِكَ الْكِتَابُ',
      ]);
      final result = read(words, 'هدى للمؤمنين ألف لام ميم');
      expect(result.committedTargetIndex, 3);
      expect(result.alignedWords[1].status, WordAlignmentStatus.substitution);
      expect(result.alignedWords[2].status, WordAlignmentStatus.matched);
      expect(
        result.alignedWords.skip(3).every((w) => w.status.isUpcoming),
        isTrue,
      );
    },
  );

  test('ambiguous isolated repair needs context instead of clearing a random error', () {
    final words = target([
      'عَمَّ يَتَسَآءَلُونَ',
      'عَمَّ يَتَسَآءَلُونَ',
      'عَنِ النَّبَإِ الْعَظِيمِ',
    ]);
    final first = read(words, 'عم يتكلمون');
    final second = read(words, 'عم يتكلمون', after: first);
    final wrong = read(words, 'عن النبإ العظيم', after: second);
    expect(wrong.substitutionsCount, 2);
    final ambiguous = read(words, 'يتساءلون', after: wrong);
    expect(ambiguous.substitutionsCount, 2);
    expect(ambiguous.committedTargetIndex, wrong.committedTargetIndex);
  });

  test(
    'an exact contextual repair wins over a later already-correct repeat',
    () {
      final words = target([
        'عَمَّ يَتَسَآءَلُونَ',
        'عَمَّ يَتَسَآءَلُونَ',
        'عَنِ النَّبَإِ الْعَظِيمِ',
      ]);
      final first = read(words, 'عم يتكلمون');
      final second = read(words, 'عم يتساءلون', after: first);
      final finished = read(words, 'عن النبإ العظيم', after: second);
      final fixed = read(words, 'عم يتساءلون', after: finished);
      expect(fixed.substitutionsCount, 0);
      expect(fixed.committedTargetIndex, 7);
      expect(fixed.matchedWordsCount, 7);
    },
  );

  test(
    'wrong word followed by an immediate correct retry keeps the correction',
    () {
      final result = read(
        naba,
        'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون مختلفون',
      );
      expect(result.committedTargetIndex, 9);
      expect(result.discrepancies, isEmpty);
    },
  );

  test(
    'restarting the ayah inside the same utterance replaces the wrong attempt',
    () {
      final result = read(
        naba,
        'عم يتساءلون عن النبإ العظيم الذي هم فيه يختلفون الذي هم فيه مختلفون',
      );
      expect(result.committedTargetIndex, 9);
      expect(result.discrepancies, isEmpty);
    },
  );

  test('repeated correct words do not consume the next expected position', () {
    final result = read(naba, 'عم عم يتساءلون عن النبإ النبإ العظيم');
    expect(result.committedTargetIndex, 5);
    expect(result.discrepancies, isEmpty);
  });

  test(
    'low confidence and unclear recognition never become definite mistakes',
    () {
      final first = read(naba, 'عم يتساءلون عن النبإ العظيم الذي هم فيه');
      final quiet = read(naba, 'يختلفون', after: first, confidence: .4);
      expect(quiet.committedTargetIndex, 8);
      expect(quiet.substitutionsCount, 0);
      final unclear = read(naba, '…', after: first);
      expect(unclear.committedTargetIndex, 8);
      expect(unclear.substitutionsCount, 0);
    },
  );

  test(
    'an unclear slot stays uncertain while its clear continuation follows',
    () {
      final result = read(
        naba,
        'عم يتساءلون عن النبإ العظيم الذي هم … مختلفون كلا سيعلمون',
      );
      expect(result.committedTargetIndex, 11);
      expect(result.substitutionsCount, 0);
      expect(result.omissionsCount, 0);
      expect(result.alignedWords[7].status, WordAlignmentStatus.uncertain);
      expect(result.alignedWords[8].status, WordAlignmentStatus.matched);
      expect(result.completedGlobalAyahs, {1, 2, 4});
      final next = read(naba, 'ثم كلا سيعلمون', after: result);
      final fixed = read(naba, 'فيه', after: next);
      expect(fixed.uncertainCount, 0);
      expect(fixed.matchedWordsCount, 14);
    },
  );

  test(
    'an unclear final frontier does not become an omission on continuation',
    () {
      final first = read(naba, 'عم يتساءلون عن النبإ العظيم الذي هم فيه');
      final unclear = read(naba, '…', after: first);
      expect(unclear.committedTargetIndex, 8);
      final next = read(naba, 'كلا سيعلمون', after: unclear);
      expect(next.committedTargetIndex, 11);
      expect(next.alignedWords[8].status, WordAlignmentStatus.uncertain);
      expect(next.omissionsCount, 0);
      expect(next.substitutionsCount, 0);
    },
  );

  test('nearby repeated word cannot steal the position of a substitution', () {
    final words = target([
      'قَالَ هَذِهِ نَاقَةٌ لَهَا شِرْبٌ وَلَكُمْ شِرْبُ يَوْمٍ مَعْلُومٍ',
    ]);
    final result = read(words, 'قال هذه ناقة لها ضرب ولكم شرب يوم معلوم');
    expect(result.committedTargetIndex, 9);
    expect(result.substitutionsCount, 1);
    expect(result.alignedWords[4].status, WordAlignmentStatus.substitution);
    expect(result.alignedWords[6].status, WordAlignmentStatus.matched);
    expect(result.omissionsCount, 0);
    expect(result.matchedWordsCount, 8);
  });

  test(
    'attached particles, merged words and muqattaat retain exact positions',
    () {
      for (final pair in [
        ('وَالَّذِينَ يُؤْمِنُونَ', 'و الذين يؤمنون'),
        ('بِسْمِ اللَّهِ', 'بسمالله'),
        ('الٓمٓ ذَلِكَ الْكِتَابُ', 'ألف لام ميم ذلك الكتاب'),
      ]) {
        final words = target([pair.$1]);
        final result = read(words, pair.$2);
        expect(result.matchedWordsCount, words.length, reason: pair.$2);
        expect(result.discrepancies, isEmpty, reason: pair.$2);
      }
    },
  );
}
