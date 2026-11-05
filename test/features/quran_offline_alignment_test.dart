import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_alignment_engine.dart';
import 'package:mishkat_app/features/quran/presentation/services/quran_recitation_text.dart';

void main() {
  const engine = QuranAlignmentEngine();
  final chapter = QuranChapter(
    number: 1,
    name: 'الفاتحة',
    englishName: 'Al-Fatiha',
    revelationType: 'Meccan',
    page: 1,
    globalStart: 1,
    ayahs: const [
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
      'مَٰلِكِ يَوْمِ ٱلدِّينِ',
    ],
  );
  final fatiha = engine.prepareTargetTokens(
    chapters: [chapter],
    startGlobalAyah: 1,
    endGlobalAyah: 4,
  );
  List<AuthoritativeWord> passage(String text) => text
      .split(' ')
      .asMap()
      .entries
      .map(
        (entry) => AuthoritativeWord(
          globalAyah: 1,
          surah: 1,
          ayahInSurah: 1,
          wordIndex: entry.key,
          uthmaniText: entry.value,
          normalizedText: QuranRecitationText.normalize(entry.value),
        ),
      )
      .toList();

  QuranAlignmentResult follow(
    QuranAlignmentResult previous,
    String text, {
    bool isFinal = true,
  }) => engine.align(
    targetWords: fatiha,
    transcript: text,
    committedTargetIndex: previous.committedTargetIndex,
    committedAlignedWords: previous.alignedWords,
    committedDiscrepancies: previous.discrepancies,
    stopAtFirstMistake: true,
    isFinal: isFinal,
  );

  group('strict orthographic equivalence', () {
    test('expands only alefs present in the Uthmani source', () {
      expect(QuranRecitationText.sameWord('ٱلْعَٰلَمِينَ', 'العالمين'), isTrue);
      expect(QuranRecitationText.sameWord('مَٰلِكِ', 'مالك'), isTrue);
      expect(QuranRecitationText.sameWord('ٱلصَّلَوٰةَ', 'الصلاة'), isTrue);
      expect(QuranRecitationText.sameWord('مُوسَىٰ', 'موسى'), isTrue);
      expect(QuranRecitationText.sameWord('قُلْ', 'قال'), isFalse);
    });

    test(
      'does not accept changed person, conjunction or pronunciation as correct',
      () {
        for (final pair in [
          ('يَعْلَمُونَ', 'تعلمون'),
          ('وَإِنْ', 'إن'),
          ('فَإِنْ', 'وإن'),
          ('قَالُوا', 'قال'),
          ('ٱلضَّآلِّينَ', 'الظالين'),
          ('بَصِيرٌ', 'نصير'),
          ('ٱلَّذِينَ', 'اللذين'),
        ]) {
          expect(
            QuranRecitationText.sameWord(pair.$1, pair.$2),
            isFalse,
            reason: '${pair.$1} ≠ ${pair.$2}',
          );
        }
      },
    );

    test(
      'a near match locates a substitution rather than awarding success',
      () {
        final result = engine.align(
          targetWords: passage('إن يعلمون هو'),
          transcript: 'إن تعلمون هو',
        );
        expect(result.alignedWords[1].status, WordAlignmentStatus.substitution);
        expect(result.matchedWordsCount, 2);
      },
    );
  });

  group('segment alignment and correction', () {
    test(
      'correct finalized segments advance across repeated Fatiha phrases',
      () {
        var result = engine.align(
          targetWords: fatiha,
          transcript: 'بسم الله الرحمن الرحيم',
          stopAtFirstMistake: true,
        );
        result = follow(result, 'الحمد لله رب العالمين');
        result = follow(result, 'الرحمن الرحيم');
        expect(result.committedTargetIndex, 10);
        expect(result.currentGlobalAyah, 4);
        expect(result.discrepancies, isEmpty);
        result = follow(result, 'مالك يوم الدين');
        expect(result.isCompleted, isTrue);
        expect(result.matchedWordsCount, 13);
      },
    );

    test('the first mistake gates progress and hides subsequent words', () {
      final result = engine.align(
        targetWords: fatiha,
        transcript:
            'بسم الله الرحمن الرحيم الحمد لله رب المؤمنين الرحمن الرحيم',
        stopAtFirstMistake: true,
      );
      expect(result.committedTargetIndex, 7);
      expect(result.correctionWordIndex, 7);
      expect(result.substitutionsCount, 1);
      expect(
        result.alignedWords.skip(8).every((word) => word.status.isUpcoming),
        isTrue,
      );
      expect(result.completedGlobalAyahs, {1});
    });

    test('retrying an ayah from its beginning corrects the gate without double counting', () {
      var result = engine.align(
        targetWords: fatiha,
        transcript: 'بسم الله الرحمن الرحيم الحمد لله رب المؤمنين',
        stopAtFirstMistake: true,
      );
      result = follow(result, 'الحمد لله رب العالمين');
      expect(result.committedTargetIndex, 8);
      expect(result.matchedWordsCount, 8);
      expect(result.discrepancies, isEmpty);
      expect(result.correctionWordIndex, isNull);
    });

    test(
      'a skipped word is corrected by repeating that word and continuing',
      () {
        var result = engine.align(
          targetWords: fatiha,
          transcript: 'بسم الله الرحمن الرحيم الحمد لله العالمين',
          stopAtFirstMistake: true,
        );
        expect(result.correctionWordIndex, 6);
        expect(result.omissionsCount, 1);
        result = follow(result, 'رب العالمين');
        expect(result.committedTargetIndex, 8);
        expect(result.omissionsCount, 0);
      },
    );

    test('self-correction within one segment replaces the wrong attempt', () {
      final result = engine.align(
        targetWords: fatiha,
        transcript: 'بسم الله الرحمن الرحيم الحمد لله رب المؤمنين الحمد لله رب العالمين',
        stopAtFirstMistake: true,
      );
      expect(result.committedTargetIndex, 8);
      expect(result.discrepancies, isEmpty);
    });

    test('stutters and repeated correct words have no penalty', () {
      final result = engine.align(
        targetWords: fatiha,
        transcript: 'بسم بسم الله الرحمن الرحمن الرحيم',
        stopAtFirstMistake: true,
      );
      expect(result.committedTargetIndex, 4);
      expect(result.discrepancies, isEmpty);
    });

    test(
      'an earlier repeated utterance cannot move the frontier backwards',
      () {
        final first = engine.align(
          targetWords: fatiha,
          transcript: 'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
          stopAtFirstMistake: true,
        );
        final second = follow(first, 'بسم الله');
        expect(second.committedTargetIndex, 8);
        expect(second.matchedWordsCount, 8);
        expect(second.discrepancies, isEmpty);
        expect(
          second.rejectedBackwardCandidate,
          contains('Rejected backward match'),
        );
      },
    );

    test(
      'supports a cumulative recognizer without replaying the committed prefix',
      () {
        final first = engine.align(
          targetWords: fatiha,
          transcript: 'بسم الله الرحمن الرحيم',
          stopAtFirstMistake: true,
        );
        final second = follow(
          first,
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
        );
        expect(second.committedTargetIndex, 8);
        expect(second.matchedWordsCount, 8);
      },
    );

    test('partial hypotheses never commit or finish a passage by default', () {
      final target = fatiha.sublist(0, 4);
      final partial = engine.align(
        targetWords: target,
        transcript: 'بسم الله الرحمن الرحيم',
        isFinal: false,
        stopAtFirstMistake: true,
      );
      expect(partial.committedTargetIndex, 0);
      expect(partial.isCompleted, isFalse);
      expect(partial.completedGlobalAyahs, isEmpty);
      expect(partial.matchedWordsCount, 4);
      final revised = engine.align(
        targetWords: target,
        transcript: 'بسم الله',
        isFinal: false,
        stopAtFirstMistake: true,
      );
      expect(revised.matchedWordsCount, 2);
      expect(revised.alignedWords[2].status, WordAlignmentStatus.upcoming);
    });

    test('a partial mismatch is uncertain and becomes correct after final revision', () {
      final partial = engine.align(
        targetWords: fatiha,
        transcript: 'بسم الله الرحمن الرحمة',
        isFinal: false,
        stopAtFirstMistake: true,
      );
      expect(partial.substitutionsCount, 0);
      expect(partial.committedTargetIndex, 0);
      expect(partial.uncertainCount, 1);
      final finalResult = engine.align(
        targetWords: fatiha,
        transcript: 'بسم الله الرحمن الرحيم',
        stopAtFirstMistake: true,
      );
      expect(finalResult.committedTargetIndex, 4);
      expect(finalResult.uncertainCount, 0);
    });

    test('low confidence cannot consume words or finish a session', () {
      final result = engine.align(
        targetWords: fatiha.sublist(0, 4),
        transcript: 'بسم الله الرحمن الرحيم',
        confidence: 0.4,
        stopAtFirstMistake: true,
      );
      expect(result.committedTargetIndex, 0);
      expect(result.isCompleted, isFalse);
      expect(result.hasReliableSpeech, isFalse);
      expect(result.substitutionsCount, 0);
      expect(result.uncertainCount, 1);
    });

    test(
      'unrelated speech does not become a series of memorization errors',
      () {
        final result = engine.align(
          targetWords: fatiha,
          transcript: 'السيارة في الشارع مزدحم',
          stopAtFirstMistake: true,
        );
        expect(result.committedTargetIndex, 0);
        expect(result.hasReliableSpeech, isFalse);
        expect(result.substitutionsCount, 0);
        expect(result.omissionsCount, 0);
        expect(result.uncertainCount, 1);
      },
    );

    test('an unclear slot is never scored as correct or a definite error', () {
      final result = engine.align(
        targetWords: fatiha,
        transcript: 'بسم … الرحمن الرحيم',
        stopAtFirstMistake: true,
      );
      expect(result.committedTargetIndex, 1);
      expect(result.correctionWordIndex, 1);
      expect(result.uncertainCount, 1);
      expect(result.substitutionsCount, 0);
    });

    test('silence and known hallucinations do not move the cursor', () {
      for (final text in [
        '',
        '[صمت]',
        'اشتركوا في القناة',
        'شكرا لكم على المشاهدة',
      ]) {
        final result = engine.align(
          targetWords: fatiha,
          transcript: text,
          stopAtFirstMistake: true,
        );
        expect(result.committedTargetIndex, 0, reason: text);
        expect(result.discrepancies, isEmpty, reason: text);
        expect(result.hasReliableSpeech, isFalse);
      }
    });

    test('unrecited suffix remains upcoming, not omitted', () {
      final result = engine.align(
        targetWords: fatiha,
        transcript: 'بسم الله',
        stopAtFirstMistake: true,
      );
      expect(result.omissionsCount, 0);
      expect(result.committedTargetIndex, 2);
      expect(
        result.alignedWords.skip(2).every((word) => word.status.isUpcoming),
        isTrue,
      );
    });

    test(
      'split attached particles and merged tokens retain word positions',
      () {
        final split = engine.align(
          targetWords: passage('والذين يؤمنون'),
          transcript: 'و الذين يؤمنون',
          stopAtFirstMistake: true,
        );
        expect(split.matchedWordsCount, 2);
        expect(split.discrepancies, isEmpty);
        final merged = engine.align(
          targetWords: passage('بسم الله'),
          transcript: 'بسمالله',
          stopAtFirstMistake: true,
        );
        expect(merged.matchedWordsCount, 2);
        expect(merged.isCompleted, isTrue);
      },
    );

    test(
      'spoken letter names align muqattaat without taking neighboring words',
      () {
        final result = engine.align(
          targetWords: passage('الٓمٓ ذلك الكتاب'),
          transcript: 'ألف لام ميم ذلك الكتاب',
          stopAtFirstMistake: true,
        );
        expect(result.matchedWordsCount, 3);
        expect(result.isCompleted, isTrue);
      },
    );

    test('recognizer may join the muqattaat letter names', () {
      final result = engine.align(
        targetWords: passage('يسٓ والقرآن'),
        transcript: 'ياسين والقرآن',
        stopAtFirstMistake: true,
      );
      expect(result.isCompleted, isTrue);
      expect(result.matchedWordsCount, 2);
    });

    test('optional introductory phrases do not consume the target', () {
      final result = engine.align(
        targetWords: passage('قُلْ هُوَ ٱللَّهُ أَحَدٌ'),
        transcript: 'أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم قل هو الله أحد',
        stopAtFirstMistake: true,
      );
      expect(result.matchedWordsCount, 4);
      expect(result.discrepancies, isEmpty);
    });

    test(
      'token preparation uses chapter global positions and excludes stop marks',
      () {
        final other = QuranChapter(
          number: 112,
          name: 'الإخلاص',
          englishName: 'Al-Ikhlas',
          revelationType: 'Meccan',
          page: 604,
          globalStart: 6222,
          ayahs: const ['قُلْ هُوَ ٱللَّهُ أَحَدٌ ۞'],
        );
        final tokens = engine.prepareTargetTokens(
          chapters: [other],
          startGlobalAyah: 6222,
          endGlobalAyah: 6222,
        );
        expect(tokens.length, 4);
        expect(tokens.first.globalAyah, 6222);
        expect(tokens.last.wordIndex, 3);
      },
    );
  });
}
