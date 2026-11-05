import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _ReviewQuran extends QuranRepository {
  _ReviewQuran(this.ayahs);
  final List<String> ayahs;

  @override
  Future<QuranData> load() async => QuranData(
    chapters: [
      QuranChapter(
        number: 1,
        name: 'الاختبار',
        englishName: 'Test',
        revelationType: 'Meccan',
        page: 1,
        globalStart: 1,
        ayahs: ayahs,
      ),
    ],
    juz: const [],
    pages: const [],
  );
}

class _ReviewSpeech extends MockSpeechRecognitionService {
  Completer<void>? startBarrier;
  Completer<void>? stopBarrier;

  @override
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  }) async {
    await startBarrier?.future;
    return super.startListening(
      localeId: localeId,
      contextualPhrases: contextualPhrases,
    );
  }

  @override
  Future<void> stopListening() async {
    await stopBarrier?.future;
    return super.stopListening();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _ReviewSpeech speech;
  late QuranMemorizationCubit memory;
  QuranOralRecitationCubit? cubit;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mishkat-adversarial-');
    final storage = LocalStorageService(directory: temp);
    await storage.init();
    memory = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memory.load();
    speech = _ReviewSpeech();
  });

  tearDown(() async {
    await cubit?.close();
    cubit = null;
    await speech.dispose();
    await memory.close();
    await temp.delete(recursive: true);
  });

  Future<QuranOralRecitationCubit> prepare(List<String> ayahs) async {
    final current = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _ReviewQuran(ayahs),
      memorizationCubit: memory,
    );
    cubit = current;
    await current.prepareSession(surahNumber: 1);
    return current;
  }

  test(
    'an unresolved last-word confidence gate never awards memorization',
    () async {
      final current = await prepare([
        'صراط الذين أنعمت عليهم غير المغضوب عليهم ولا الضالين',
      ]);
      current.setMode(OralRecitationMode.hidden);
      await current.startRecitation();
      speech.emitTranscript(
        'صراط الذين أنعمت عليهم غير المغضوب عليهم ولا',
        isFinal: true,
      );
      await pumpEventQueue();
      expect(current.state.committedTargetIndex, 8);
      speech.emitTranscript('الضالين', isFinal: true, confidence: .4);
      await pumpEventQueue();
      expect(current.state.committedTargetIndex, 8);
      expect(current.state.correctionWordIndex, 8);
      expect(current.state.completedGlobalAyahs, isEmpty);
      await current.finishSession();
      await current.commitToMemorization();
      expect(
        memory.state.getItem(1).status,
        isNot(MemorizationStatus.memorized),
      );
    },
  );

  test(
    'switching from reading to hidden after pause retains assistance history',
    () async {
      final current = await prepare([
        'بسم الله الرحمن الرحيم',
        'الحمد لله رب العالمين',
      ]);
      current.setMode(OralRecitationMode.reading);
      await current.startRecitation();
      speech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await pumpEventQueue();
      await current.pauseRecitation();
      current.setMode(OralRecitationMode.hidden);
      await current.finishSession();
      await current.commitToMemorization();
      expect(
        memory.state.getItem(1).status,
        isNot(MemorizationStatus.memorized),
      );
    },
  );

  test(
    'late native startup is released after a pause during startup',
    () async {
      final current = await prepare(['بسم الله الرحمن الرحيم']);
      speech.startBarrier = Completer<void>();
      final starting = current.startRecitation();
      await pumpEventQueue();
      expect(current.state.isListening, isTrue);
      await current.pauseRecitation();
      expect(current.state.isPaused, isTrue);
      speech.startBarrier!.complete();
      await starting;
      expect(current.state.isPaused, isTrue);
      expect(speech.isListening, isFalse);
    },
  );

  test(
    'a previous finish cannot complete the newly prepared session',
    () async {
      final current = await prepare([
        'بسم الله الرحمن الرحيم',
        'الحمد لله رب العالمين',
      ]);
      final priorSession = current.state.sessionId;
      await current.startRecitation();
      speech.stopBarrier = Completer<void>();
      final finishing = current.finishSession();
      await pumpEventQueue();
      expect(current.state.isDraining, isTrue);
      final preparing = current.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 2,
        endGlobalAyah: 2,
      );
      await pumpEventQueue();
      speech.stopBarrier!.complete();
      await Future.wait([finishing, preparing]);
      expect(current.state.sessionId, isNot(priorSession));
      expect(current.state.lifecycle, OralRecitationLifecycle.ready);
      expect(current.state.currentGlobalAyah, 2);
      expect(current.state.matchedWordsCount, 0);
      expect(current.state.summary, isNull);
    },
  );
}
