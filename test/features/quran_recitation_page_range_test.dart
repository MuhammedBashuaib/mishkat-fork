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

class _Speech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics {
  Completer<void>? stopping;
  String? finalTail;
  int stops = 0;

  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();

  @override
  Future<void> stopListening() async {
    stops++;
    await stopping?.future;
    if (finalTail case final tail?) {
      finalTail = null;
      emitTranscript(tail, isFinal: true);
    }
    await super.stopListening();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = QuranRepository();
  late QuranData quran;
  late Directory directory;
  late QuranMemorizationCubit memory;
  late _Speech speech;
  late QuranOralRecitationCubit cubit;

  setUpAll(() async => quran = await repository.load());

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mishkat-recite-pages-');
    final storage = LocalStorageService(directory: directory);
    await storage.init();
    memory = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    await memory.load();
    speech = _Speech();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: repository,
      memorizationCubit: memory,
    );
  });

  tearDown(() async {
    if (speech.stopping case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    await cubit.close();
    await speech.dispose();
    await memory.close();
    await directory.delete(recursive: true);
  });

  String targetTranscript() =>
      cubit.state.targetWords.map((word) => word.uthmaniText).join(' ');

  Future<void> hear(String text, {bool isFinal = true}) async {
    speech.emitTranscript(text, isFinal: isFinal);
    await pumpEventQueue();
  }

  test('pages 1–2 span Al-Fatiha and the first five Baqarah verses', () async {
    await cubit.prepareSession(surahNumber: 114, startPage: 1, endPage: 2);
    expect(cubit.state.startGlobalAyah, 1);
    expect(cubit.state.endGlobalAyah, 12);
    expect(cubit.state.startPage, 1);
    expect(cubit.state.endPage, 2);
    expect(cubit.state.surahNumber, 1);
    expect(cubit.state.surahName, 'الفاتحة – البقرة');
    expect(cubit.state.targetWords.map((word) => word.surah).toSet(), {1, 2});
    expect(
      cubit.state.targetWords.map((word) => word.globalAyah).toSet(),
      Set<int>.from(List.generate(12, (index) => index + 1)),
    );
  });

  test(
    'a single last page contains all three Surahs, through global 6236',
    () async {
      await cubit.prepareSession(surahNumber: 1, startPage: 604);
      expect(cubit.state.startPage, 604);
      expect(cubit.state.endPage, 604);
      expect(cubit.state.startGlobalAyah, quran.page(604).first.global);
      expect(cubit.state.endGlobalAyah, 6236);
      expect(cubit.state.targetWords.map((word) => word.surah).toSet(), {
        112,
        113,
        114,
      });
      expect(cubit.state.targetWords.last.globalAyah, 6236);
    },
  );

  test(
    'invalid and reversed page ranges report an error without a session',
    () async {
      for (final range in [(0, 1), (604, 605), (5, 4), (-1, -1)]) {
        await cubit.prepareSession(
          surahNumber: 1,
          startPage: range.$1,
          endPage: range.$2,
        );
        expect(cubit.state.lifecycle, OralRecitationLifecycle.error);
        expect(cubit.state.errorMessage, contains('نطاق صفحات صحيحًا'));
        expect(cubit.state.targetWords, isEmpty);
        expect(cubit.state.sessionId, isNull);
      }
      expect(speech.initializeCount, 0);
    },
  );

  test('verse selection remains constrained to the chosen Surah', () async {
    await cubit.prepareSession(
      surahNumber: 1,
      startGlobalAyah: 0,
      endGlobalAyah: 6236,
    );
    expect(cubit.state.startGlobalAyah, 1);
    expect(cubit.state.endGlobalAyah, 7);
    expect(cubit.state.targetWords.map((word) => word.surah).toSet(), {1});
    expect(cubit.state.startPage, isNull);
    expect(cubit.state.endPage, isNull);
  });

  test(
    'live preview cannot finish; final page completion creates a report',
    () async {
      await cubit.prepareSession(surahNumber: 1, startPage: 604);
      await cubit.startRecitation();
      final text = targetTranscript();
      await hear(text, isFinal: false);
      await hear(text, isFinal: false);
      expect(cubit.state.isListening, isTrue);
      expect(cubit.state.summary, isNull);
      expect(cubit.state.committedTargetIndex, 0);

      await hear(text);
      expect(cubit.state.isCompleted, isTrue);
      expect(speech.isListening, isFalse);
      final summary = cubit.state.summary!;
      expect(summary.startPage, 604);
      expect(summary.endPage, 604);
      expect(summary.endGlobalAyah, 6236);
      expect(summary.totalAyahs, 15);
      expect(summary.matchedAyahs, 15);
      expect(summary.coveragePercentage, 100);
      expect(summary.unrecitedWords, 0);

      await cubit.commitToMemorization();
      await cubit.commitToMemorization();
      expect(memory.state.history, hasLength(15));
      expect(
        memory.state.items.keys.toSet(),
        Set<int>.from(List.generate(15, (index) => 6222 + index)),
      );
    },
  );

  test(
    'full coverage reports remaining mistakes instead of waiting forever',
    () async {
      await cubit.prepareSession(
        surahNumber: 78,
        startGlobalAyah: 5673,
        endGlobalAyah: 5677,
      );
      await cubit.startRecitation();
      await hear(
        'عم يتساءلون عن النبأ العظيم الذي هم فيه مختلفين كلا سيعلمون ثم كلا سيعلمون',
      );
      expect(cubit.state.isCompleted, isTrue);
      expect(cubit.state.unresolvedMistakeWordIndices, {8});
      expect(cubit.state.summary!.substitutionsCount, 1);
      expect(cubit.state.summary!.coveragePercentage, 100);
      expect(cubit.state.summary!.accuracyPercentage, lessThan(100));
    },
  );

  test(
    'automatic and manual finish share one drain/report and ignore late speech',
    () async {
      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 1,
      );
      var reports = 0;
      final subscription = cubit.stream.listen((state) {
        if (state.isCompleted) reports++;
      });
      await cubit.startRecitation();
      speech.stopping = Completer<void>();
      await hear(targetTranscript());
      expect(cubit.state.isDraining, isTrue);
      final first = cubit.finishSession();
      final second = cubit.finishSession();
      speech.stopping!.complete();
      await Future.wait([first, second]);
      await pumpEventQueue();
      final summary = cubit.state.summary;
      await hear('كلمات متأخرة لا تنتمي إلى الجلسة');
      await cubit.finishSession();
      expect(cubit.state.summary, same(summary));
      expect(reports, 1);
      expect(speech.stops, 1);
      await subscription.cancel();
    },
  );

  test(
    'a final utterance flushed during pause opens the completed report',
    () async {
      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 1,
      );
      await cubit.startRecitation();
      speech.finalTail = targetTranscript();
      await cubit.pauseRecitation();
      expect(cubit.state.isCompleted, isTrue);
      expect(cubit.state.summary!.coveragePercentage, 100);
      expect(speech.stops, 1);
    },
  );

  test('weak and individual retries work in later Surahs; full retry restores pages', () async {
    await cubit.prepareSession(surahNumber: 1, startPage: 604);
    final fullCount = cubit.state.targetWords.length;
    final hinted = quran.globalFor(113, 1);
    cubit.revealAyah(hinted);
    await cubit.startRecitation();
    await hear(targetTranscript());
    await cubit.retrySession(onlyWeakAyahs: true);
    expect(cubit.state.targetWords.map((word) => word.globalAyah).toSet(), {
      hinted,
    });
    expect(cubit.state.startPage, 604);
    expect(cubit.state.endPage, 604);
    await cubit.retrySession(globalAyah: 6236);
    expect(cubit.state.targetWords.map((word) => word.globalAyah).toSet(), {
      6236,
    });
    await cubit.retrySession();
    expect(cubit.state.targetWords, hasLength(fullCount));
    expect(cubit.state.targetWords.map((word) => word.surah).toSet(), {
      112,
      113,
      114,
    });
  });

  test(
    'a replacement session invalidates an old automatic completion in flight',
    () async {
      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 1,
      );
      await cubit.startRecitation();
      speech.stopping = Completer<void>();
      await hear(targetTranscript());
      var reports = 0;
      final subscription = cubit.stream.listen((state) {
        if (state.isCompleted) reports++;
      });
      final preparing = cubit.prepareSession(surahNumber: 1, startPage: 604);
      speech.stopping!.complete();
      await preparing;
      await pumpEventQueue();
      expect(reports, 0);
      expect(cubit.state.lifecycle, OralRecitationLifecycle.ready);
      expect(cubit.state.startPage, 604);
      expect(cubit.state.summary, isNull);
      await subscription.cancel();
    },
  );
}
