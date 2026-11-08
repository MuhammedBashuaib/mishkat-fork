import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _Quran extends QuranRepository {
  _Quran(this.data);

  final QuranData data;

  @override
  Future<QuranData> load() async => data;
}

class _OfflineSpeech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics {
  @override
  bool get isOffline => true;

  @override
  Stream<double> get soundLevelStream => const Stream.empty();

  @override
  Stream<bool> get processingStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranData quran;
  late Directory temp;
  late _OfflineSpeech speech;
  late QuranMemorizationCubit memorization;
  late QuranOralRecitationCubit cubit;

  // Use the bundled authoritative text, including the user's actual example
  // يختلفون in 16:39. No recognition result is used as display text.
  setUpAll(() async {
    final raw = jsonDecode(
      await rootBundle.loadString('assets/data/quran.json'),
    ) as Map<String, dynamic>;
    quran = QuranData(
      chapters: [
        for (final entry in raw['surahs'] as List)
          if (entry['n'] == 16 || entry['n'] == 78)
            QuranChapter.fromJson(Map<String, dynamic>.from(entry as Map)),
      ],
      juz: const [],
      pages: const [],
    );
  });

  Future<void> prepare({int surah = 78, int first = 1, int last = 5}) async {
    final chapter = quran.chapters.firstWhere((item) => item.number == surah);
    await cubit.prepareSession(
      surahNumber: surah,
      startGlobalAyah: chapter.globalStart + first - 1,
      endGlobalAyah: chapter.globalStart + last - 1,
      planId: 'follow-practice',
    );
  }

  Future<void> hear(String text, {bool finalResult = true}) async {
    speech.emitTranscript(text, isFinal: finalResult);
    await pumpEventQueue();
  }

  Set<int> firstWords(int count) =>
      Set<int>.from(List.generate(count, (i) => i));

  const throughMistake = 'عم يتساءلون عن النبأ العظيم الذي هم فيه مختلفين';
  const wholeRangeWithMistake = '$throughMistake كلا سيعلمون ثم كلا سيعلمون';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mishkat-follow-flow-');
    final storage = LocalStorageService(directory: temp);
    await storage.init();
    memorization = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memorization.load();
    speech = _OfflineSpeech();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _Quran(quran),
      memorizationCubit: memorization,
    );
    await prepare();
  });

  tearDown(() async {
    await cubit.close();
    await speech.dispose();
    await memorization.close();
    await temp.delete(recursive: true);
  });

  test(
    'context-backed live prefix reveals early without saved credit',
    () async {
      await cubit.startRecitation();
      await hear('عم يتساءلون عن', finalResult: false);
      expect(cubit.state.visibleWordIndices, {0, 1});
      expect(cubit.state.visibleWordIndices, isNot(contains(2)));

      await hear('عم يتساءلون عن', finalResult: false);
      expect(cubit.state.visibleWordIndices, {0, 1, 2});
      expect(cubit.state.visibleWordIndices, isNot(contains(3)));
      expect(cubit.state.completedGlobalAyahs, isEmpty);
      expect(cubit.state.committedTargetIndex, 0);
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.isListening, isTrue);

      await cubit.finishSession();
      expect(cubit.state.summary!.matchedWords, 0);
      expect(cubit.state.summary!.matchedAyahs, 0);
      expect(cubit.state.visibleWordIndices, isEmpty);
    },
  );

  test(
    'an old partial correction keeps the red mistake and cannot reveal ahead',
    () async {
      await cubit.startRecitation();
      await hear(throughMistake);
      final frontier = cubit.state.committedTargetIndex;
      await hear('مختلفون', finalResult: false);
      expect(cubit.state.visibleWordIndices, firstWords(9));
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.committedTargetIndex, frontier);
      expect(cubit.state.mistakeWordIndices, {8});
      expect(cubit.state.currentGlobalAyah, 5675);

      await hear('كلا سيعلمون ثم', finalResult: false);
      expect(cubit.state.visibleWordIndices, firstWords(11));
      expect(cubit.state.visibleWordIndices, isNot(contains(11)));
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.committedTargetIndex, frontier);
    },
  );

  test(
    'a provisional wrong word cannot become a permanent red mistake',
    () async {
      await cubit.startRecitation();
      await hear('عم يتساءلون عن النبأ الكبير', finalResult: false);
      await hear('عم يتساءلون عن النبأ الكبير', finalResult: false);
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
      expect(cubit.state.visibleWordIndices, isNot(contains(4)));

      await hear('عم يتساءلون عن النبأ العظيم');
      expect(cubit.state.visibleWordIndices, firstWords(5));
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.assistedWordIndices, isEmpty);
      expect(cubit.state.hintCount, 0);
      expect(cubit.state.completedGlobalAyahs, {5673, 5674});
    },
  );

  test(
    'يختلفون versus مختلفين reveals the authoritative correction only',
    () async {
      await prepare(surah: 16, first: 39, last: 40);
      final currentAyah = cubit.state.startGlobalAyah;
      await cubit.startRecitation();
      await hear(
        'ليبين لهم الذي مختلفين فيه وليعلم الذين كفروا أنهم كانوا كاذبين',
      );

      const wrongWord = 3;
      final correction = cubit.state.alignedWords[wrongWord];
      expect(correction.authoritativeWord.normalizedText, 'يختلفون');
      expect(correction.status, WordAlignmentStatus.substitution);
      expect(cubit.state.visibleWordIndices, contains(wrongWord));
      expect(cubit.state.mistakeWordIndices, {wrongWord});
      expect(cubit.state.unresolvedMistakeWordIndices, {wrongWord});
      expect(cubit.state.assistedWordIndices, contains(wrongWord));
      expect(cubit.state.currentGlobalAyah, currentAyah);
      expect(
        cubit.state.visibleWordIndices.every(
          (index) => cubit.state.targetWords[index].globalAyah == currentAyah,
        ),
        isTrue,
        reason: 'a correction must not reveal any unread word from 16:40',
      );
      expect(cubit.state.completedGlobalAyahs, isNot(contains(currentAyah)));
    },
  );

  test(
    'reading onward keeps the error and does not reveal the following ayah',
    () async {
      await cubit.startRecitation();
      await hear(throughMistake);
      expect(cubit.state.visibleWordIndices, firstWords(9));
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.currentGlobalAyah, 5675);
      expect(cubit.state.currentWordIndex, 9);

      await hear('كلا سيعلمون');
      expect(cubit.state.visibleWordIndices, firstWords(11));
      expect(cubit.state.visibleWordIndices, isNot(contains(11)));
      expect(cubit.state.currentGlobalAyah, 5676);
      expect(cubit.state.currentWordIndex, 11);
      expect(cubit.state.mistakeWordIndices, {8});
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.completedGlobalAyahs, contains(5676));
      expect(cubit.state.completedGlobalAyahs, isNot(contains(5675)));
      expect(cubit.state.isListening, isTrue);
    },
  );

  test(
    'correcting a previous word removes its underline without rewinding',
    () async {
      await cubit.startRecitation();
      await hear(throughMistake);
      await hear('كلا سيعلمون');
      final frontier = cubit.state.committedTargetIndex;

      await hear('مختلفون');
      expect(cubit.state.alignedWords[8].status, WordAlignmentStatus.matched);
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
      expect(cubit.state.mistakeWordIndices, {8});
      expect(cubit.state.assistedWordIndices, contains(8));
      expect(cubit.state.committedTargetIndex, frontier);
      expect(cubit.state.currentWordIndex, 11);
      expect(cubit.state.currentGlobalAyah, 5676);
      expect(cubit.state.visibleWordIndices, firstWords(11));
      expect(cubit.state.isListening, isTrue);
    },
  );

  test(
    'bypassing an earlier error never moves the reading position backward',
    () async {
      await cubit.startRecitation();
      await hear(throughMistake);
      await hear('كلا سيعلمون');
      final frontier = cubit.state.committedTargetIndex;
      expect(cubit.state.correctionWordIndex, 8);

      await cubit.skipCurrentWord();
      expect(cubit.state.committedTargetIndex, frontier);
      expect(cubit.state.currentWordIndex, 11);
      expect(cubit.state.alignedWords[8].status, WordAlignmentStatus.uncertain);
      expect(cubit.state.assistedWordIndices, contains(8));
      expect(cubit.state.mistakeWordIndices, contains(8));
      expect(cubit.state.completedGlobalAyahs, isNot(contains(5675)));
      expect(cubit.state.isListening, isTrue);
    },
  );

  test(
    'the last ayah does not end capture while an earlier mistake remains',
    () async {
      await cubit.startRecitation();
      await hear(wholeRangeWithMistake);
      expect(cubit.state.committedTargetIndex, cubit.state.targetWords.length);
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.isListening, isTrue);
      expect(speech.isListening, isTrue);
      expect(cubit.state.summary, isNull);

      await hear('مختلفون');
      expect(cubit.state.isCompleted, isTrue);
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
      expect(cubit.state.mistakeWordIndices, {8});
      expect(cubit.state.summary!.matchedWords, cubit.state.targetWords.length);
      expect(cubit.state.summary!.assistedWords, 1);
      expect(cubit.state.summary!.suggestedOutcome, ReviewOutcome.difficult);
    },
  );

  test(
    'manual finish retains a remaining mistake instead of awarding it credit',
    () async {
      await cubit.startRecitation();
      await hear(wholeRangeWithMistake);
      await cubit.finishSession();

      expect(cubit.state.isCompleted, isTrue);
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.mistakeWordIndices, {8});
      expect(
        cubit.state.summary!.matchedWords,
        cubit.state.targetWords.length - 1,
      );
      expect(cubit.state.summary!.substitutionsCount, 1);
      expect(cubit.state.summary!.assistedWords, 1);
      expect(cubit.state.summary!.suggestedOutcome, ReviewOutcome.difficult);
    },
  );

  test('empty hypotheses and repeated pauses preserve error history without extra hints', () async {
    await cubit.startRecitation();
    await hear(throughMistake);
    final hintCount = cubit.state.hintCount;
    final assisted = Set<int>.of(cubit.state.assistedWordIndices);
    final visible = Set<int>.of(cubit.state.visibleWordIndices);

    await hear('', finalResult: false);
    await hear('', finalResult: false);
    await cubit.pauseRecitation();
    await cubit.pauseRecitation();
    await cubit.resumeRecitation();
    await hear('', finalResult: false);

    expect(cubit.state.mistakeWordIndices, {8});
    expect(cubit.state.unresolvedMistakeWordIndices, {8});
    expect(cubit.state.assistedWordIndices, assisted);
    expect(cubit.state.hintCount, hintCount);
    expect(cubit.state.visibleWordIndices, visible);
    expect(cubit.state.completedGlobalAyahs, isNot(contains(5675)));
  });

  test(
    'weak retry includes a corrected red ayah but starts a clean attempt',
    () async {
      await cubit.startRecitation();
      await hear(wholeRangeWithMistake);
      await hear('مختلفون');
      expect(cubit.state.isCompleted, isTrue);
      expect(cubit.state.mistakeWordIndices, {8});
      final oldSession = cubit.state.sessionId;

      await cubit.retrySession(onlyWeakAyahs: true);
      expect(cubit.state.targetWords.map((word) => word.globalAyah).toSet(), {
        5675,
      });
      expect(cubit.state.sessionId, isNot(oldSession));
      expect(cubit.state.planId, 'follow-practice');
      expect(cubit.state.mode, OralRecitationMode.hidden);
      expect(cubit.state.visibleWordIndices, isEmpty);
      expect(cubit.state.mistakeWordIndices, isEmpty);
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
      expect(cubit.state.assistedWordIndices, isEmpty);
      expect(cubit.state.hintCount, 0);
      expect(cubit.state.summary, isNull);
      expect(cubit.state.committedTargetIndex, 0);
    },
  );

  test(
    'a hint after continuing past a mistake helps with the next unread word',
    () async {
      await cubit.startRecitation();
      await hear(throughMistake);
      await hear('كلا سيعلمون');
      expect(cubit.state.correctionWordIndex, 8);
      expect(cubit.state.currentWordIndex, 11);

      cubit.hintCurrentWord();
      expect(
        cubit.state.hintedWordIndices,
        {11},
        reason:
            'the old red correction is already visible; the reader needs ثم',
      );
      expect(cubit.state.hintedGlobalAyahs, {5677});
      expect(cubit.state.hintCount, 1);
      cubit.hintCurrentWord();
      expect(cubit.state.hintCount, 1);
      expect(cubit.state.mistakeWordIndices, {8});
    },
  );

  test('bypassing one old error at the end leaves another error available to correct', () async {
    await cubit.startRecitation();
    await hear(
      'عم يتساءلون عن النبأ الكبير الذي هم فيه مختلفين كلا سيعلمون ثم كلا سيعلمون',
    );
    expect(cubit.state.committedTargetIndex, cubit.state.targetWords.length);
    expect(cubit.state.unresolvedMistakeWordIndices, {4, 8});
    expect(cubit.state.correctionWordIndex, 4);

    await cubit.skipCurrentWord();
    expect(cubit.state.unresolvedMistakeWordIndices, {8});
    expect(cubit.state.alignedWords[4].status, WordAlignmentStatus.uncertain);
    expect(cubit.state.isListening, isTrue);
    expect(cubit.state.summary, isNull);
    expect(cubit.state.correctionWordIndex, 8);
  });
}
