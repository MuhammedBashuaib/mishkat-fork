import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _Quran extends QuranRepository {
  @override
  Future<QuranData> load() async => QuranData(
    chapters: [
      QuranChapter(
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
        ],
      ),
    ],
    juz: const [],
    pages: const [],
  );
}

class _OfflineSpeech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics {
  final levels = StreamController<double>.broadcast();
  final processing = StreamController<bool>.broadcast();
  String? tail;
  Completer<void>? stopBarrier;

  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => levels.stream;
  @override
  Stream<bool> get processingStream => processing.stream;

  @override
  Future<void> stopListening() async {
    await stopBarrier?.future;
    if (tail != null) {
      emitTranscript(tail!, isFinal: true);
      tail = null;
    }
    await super.stopListening();
  }

  @override
  Future<void> dispose() async {
    await levels.close();
    await processing.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _OfflineSpeech speech;
  late QuranMemorizationCubit memory;
  late QuranOralRecitationCubit cubit;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mishkat-recite-test-');
    final storage = LocalStorageService(directory: temp);
    await storage.init();
    memory = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memory.load();
    speech = _OfflineSpeech();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _Quran(),
      memorizationCubit: memory,
    );
    await cubit.prepareSession(surahNumber: 1, planId: 'practice-plan');
  });

  tearDown(() async {
    await cubit.close();
    await speech.dispose();
    await memory.close();
    await temp.delete(recursive: true);
  });

  test(
    'offline capture never sends expected Quran words as recognition prompts',
    () async {
      await cubit.startRecitation();
      expect(cubit.state.isOfflineEngine, isTrue);
      expect(speech.lastContextualPhrases, isEmpty);
      speech.levels.add(.6);
      speech.processing.add(true);
      await pumpEventQueue();
      expect(cubit.state.audioLevel, .6);
      expect(cubit.state.isProcessingSpeech, isTrue);
    },
  );

  test(
    'pause drains the last spoken phrase before freezing progress',
    () async {
      await cubit.startRecitation();
      speech.tail = 'بسم الله الرحمن الرحيم';
      await cubit.pauseRecitation();
      expect(cubit.state.isPaused, isTrue);
      expect(cubit.state.isDraining, isFalse);
      expect(cubit.state.committedTargetIndex, 4);
      expect(cubit.state.matchedWordsCount, 4);
      expect(cubit.state.completedGlobalAyahs, {1});
      speech.emitTranscript('الحمد لله رب العالمين', isFinal: true);
      await pumpEventQueue();
      expect(
        cubit.state.matchedWordsCount,
        4,
        reason: 'late post-stop events are ignored',
      );
    },
  );

  test(
    'finish waits for final decoding and distinguishes coverage from accuracy',
    () async {
      await cubit.startRecitation();
      speech.tail = 'بسم الله الرحمن الرحيم';
      speech.stopBarrier = Completer<void>();
      final finishing = cubit.finishSession();
      await pumpEventQueue();
      expect(cubit.state.isDraining, isTrue);
      expect(cubit.state.summary, isNull);
      speech.stopBarrier!.complete();
      await finishing;
      final summary = cubit.state.summary!;
      expect(summary.matchedWords, 4);
      expect(summary.attemptedWords, 4);
      expect(summary.unrecitedWords, 6);
      expect(summary.accuracyPercentage, 100);
      expect(summary.coveragePercentage, 40);
      expect(
        summary.omissionsCount,
        0,
        reason: 'unread tail is not an omission',
      );
    },
  );

  test(
    'unconfirmed partials cannot complete an ayah or survive a canceled phrase',
    () async {
      await cubit.startRecitation();
      speech.emitTranscript('بسم الله الرحمن الرحيم');
      await pumpEventQueue();
      expect(cubit.state.matchedWordsCount, 4);
      expect(cubit.state.committedTargetIndex, 0);
      expect(cubit.state.completedGlobalAyahs, isEmpty);
      await cubit.pauseRecitation();
      expect(cubit.state.matchedWordsCount, 0);
      expect(cubit.state.completedGlobalAyahs, isEmpty);
    },
  );

  test(
    'two live hypotheses reveal an Ayah without awarding final progress',
    () async {
      await cubit.startRecitation();
      speech.emitTranscript('بسم الله الرحمن الرحيم');
      await pumpEventQueue();
      expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
      speech.emitTranscript('بسم الله الرحمن الرحيم');
      await pumpEventQueue();
      expect(cubit.state.previewCompletedGlobalAyahs, {1});
      expect(cubit.state.completedGlobalAyahs, isEmpty);
      expect(cubit.state.committedTargetIndex, 0);
      expect(cubit.state.isListening, isTrue);
      speech.emitTranscript('بسم الله');
      await pumpEventQueue();
      expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
      await cubit.finishSession();
      expect(cubit.state.summary!.matchedWords, 0);
      expect(cubit.state.summary!.matchedAyahs, 0);
    },
  );

  test(
    'final live speech confirms a preview without stopping the session',
    () async {
      await cubit.startRecitation();
      speech.emitTranscript('بسم الله الرحمن الرحيم');
      await pumpEventQueue();
      speech.emitTranscript('بسم الله الرحمن الرحيم');
      await pumpEventQueue();
      expect(cubit.state.previewCompletedGlobalAyahs, {1});
      speech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await pumpEventQueue();
      expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
      expect(cubit.state.completedGlobalAyahs, {1});
      expect(cubit.state.committedTargetIndex, 4);
      expect(cubit.state.isListening, isTrue);
    },
  );

  test(
    'a finalized omission preserves later speech and can be corrected in place',
    () async {
      await cubit.startRecitation();
      speech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await pumpEventQueue();
      speech.emitTranscript('الحمد لله العالمين', isFinal: true);
      await pumpEventQueue();
      expect(cubit.state.correctionWordIndex, 6);
      expect(cubit.state.committedTargetIndex, 8);
      expect(cubit.state.alignedWords[7].status, WordAlignmentStatus.matched);
      speech.emitTranscript('رب العالمين', isFinal: true);
      await pumpEventQueue();
      expect(cubit.state.correctionWordIndex, isNull);
      expect(cubit.state.committedTargetIndex, 8);
      expect(cubit.state.omissionsCount, 0);
      expect(cubit.state.completedGlobalAyahs, {1, 2});
      expect(cubit.state.mistakeWordIndices, {6});
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
    },
  );

  test(
    'manual bypass remains uncertain and never awards memorization credit',
    () async {
      await cubit.startRecitation();
      speech.emitTranscript(
        'بسم الله الرحمن الرحيم الحمد لله العالمين',
        isFinal: true,
      );
      await pumpEventQueue();
      expect(cubit.state.correctionWordIndex, 6);
      await cubit.skipCurrentWord();
      expect(cubit.state.assistedWordIndices, {6});
      expect(cubit.state.alignedWords[6].status, WordAlignmentStatus.uncertain);
      expect(cubit.state.currentWordIndex, 8);
      speech.emitTranscript('العالمين الرحمن الرحيم', isFinal: true);
      await pumpEventQueue();
      await cubit.finishSession();
      expect(cubit.state.summary!.assistedWords, 1);
      expect(cubit.state.completedGlobalAyahs, isNot(contains(2)));
    },
  );

  test(
    'hints are recorded and weak-only retry retains the plan and chosen mode',
    () async {
      cubit.setMode(OralRecitationMode.hidden);
      await cubit.startRecitation();
      cubit.hintCurrentWord();
      cubit.hintCurrentWord();
      expect(cubit.state.hintCount, 1);
      speech.emitTranscript(
        'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم',
        isFinal: true,
      );
      await pumpEventQueue();
      await cubit.finishSession();
      final oldSession = cubit.state.sessionId;
      expect(cubit.state.summary!.hintCount, 1);
      await cubit.retrySession(onlyWeakAyahs: true);
      expect(cubit.state.targetWords.map((w) => w.globalAyah).toSet(), {1});
      expect(cubit.state.planId, 'practice-plan');
      expect(cubit.state.mode, OralRecitationMode.hidden);
      expect(cubit.state.sessionId, isNot(oldSession));
      expect(cubit.state.summary, isNull);
      expect(cubit.state.hintCount, 0);
    },
  );

  test(
    'offline done event pauses safely instead of restarting the microphone',
    () async {
      await cubit.startRecitation();
      speech.emitStatus('done');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(speech.startListeningCount, 1);
      expect(cubit.state.isPaused, isTrue);
    },
  );
}
