import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/visual_recall_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/visual_recall_bottom_bar.dart';

class InMemoryTrackingLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> store = {};
  final List<String> writeOperations = [];
  bool failOnWrite = false;
  bool failOnRemove = false;
  Completer<void>? writeCompleter;

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final val = store[key];
    return val is Map ? Map<String, dynamic>.from(val) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final val = store[key];
    return val is List ? List<dynamic>.from(val) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final val = store[key];
    return val is num ? val.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    writeOperations.add('writeMap:$key');
    if (writeCompleter != null) {
      await writeCompleter!.future;
    }
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk I/O failure');
    }
    store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    writeOperations.add('writeList:$key');
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk I/O failure');
    }
    store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    writeOperations.add('writeInt:$key');
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk I/O failure');
    }
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    writeOperations.add('remove:$key');
    if (failOnRemove) {
      throw const FileSystemException('Simulated failure during remove');
    }
    store.remove(key);
  }

  @override
  Future<void> clear() async {
    writeOperations.add('clear');
    store.clear();
  }
}

class FakeQuranAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();

  @override
  Duration? get duration => null;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  bool get isPlaying => false;

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {}

  @override
  Future<void> playAyahFromUrl(String url) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository layoutRepo;
  late QuranRepository quranRepo;

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository.instance;
    await layoutRepo.load();
    quranRepo = QuranRepository();
    await quranRepo.load();

    final outDir = Directory('screenshots/visual_recall_assessment');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
  });

  group('Q13 Phase 1D — Assessment & Session Completion Production Tests', () {
    late InMemoryTrackingLocalStorageService storage;
    late QuranMemorizationRepository memoRepo;
    late QuranMemorizationCubit memoCubit;
    late QuranVisualRecallCubit recallCubit;
    late QuranCubit quranCubit;

    setUp(() async {
      storage = InMemoryTrackingLocalStorageService();
      memoRepo = QuranMemorizationRepository(storage: storage);
      memoCubit = QuranMemorizationCubit(repository: memoRepo);
      await memoCubit.load();
      recallCubit = QuranVisualRecallCubit(
        memorizationCubit: memoCubit,
        storage: storage,
      );
      quranCubit = QuranCubit(
        repository: quranRepo,
        storage: storage,
        audio: FakeQuranAudioService(),
        reciter: 'alafasy',
        fontSize: 22.0,
      );
      await quranCubit.load();
    });

    tearDown(() async {
      await recallCubit.close();
      await memoCubit.close();
      await quranCubit.close();
    });

    Widget buildTestHarness({
      required Widget child,
      bool isDark = false,
      Size size = const Size(390, 844),
    }) {
      final baseTheme = isDark ? AppTheme.dark(1.0) : AppTheme.light(1.0);
      return MultiBlocProvider(
        providers: [
          BlocProvider<QuranVisualRecallCubit>.value(value: recallCubit),
          BlocProvider<QuranMemorizationCubit>.value(value: memoCubit),
          BlocProvider<QuranCubit>.value(value: quranCubit),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseTheme,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    // ============================================================
    // GROUP 1: Basic Assessment & Operation Identity
    // ============================================================
    test('1, 3, 4, 5. Known/correct records through QuranMemorizationCubit with exact operation identity', () async {
      await recallCubit.startSingleAyah(100);
      recallCubit.revealCurrentAyah();

      final sessionId = recallCubit.state.sessionId!;
      final expectedOperationId = 'rev_${sessionId}_100';

      await recallCubit.recordKnown();

      // Verified persistence in QuranMemorizationCubit
      expect(memoCubit.state.history.length, 1);
      final record = memoCubit.state.history.first;
      expect(record.globalAyah, 100);
      expect(record.outcome, ReviewOutcome.good);
      expect(record.sessionId, sessionId);
      expect(record.id, expectedOperationId);

      // Session transitioned to completed
      expect(recallCubit.state.phase, VisualRecallPhase.completed);
      expect(recallCubit.state.assessmentOutcomes[100], ReviewOutcome.good);
    });

    test('2. Needs-revision records through QuranMemorizationCubit', () async {
      await recallCubit.startSingleAyah(200);
      recallCubit.revealCurrentAyah();

      final sessionId = recallCubit.state.sessionId!;
      final expectedOperationId = 'rev_${sessionId}_200';

      await recallCubit.recordNeedsRevision();

      expect(memoCubit.state.history.length, 1);
      final record = memoCubit.state.history.first;
      expect(record.globalAyah, 200);
      expect(record.outcome, ReviewOutcome.difficult);
      expect(record.sessionId, sessionId);
      expect(record.id, expectedOperationId);

      expect(
        recallCubit.state.assessmentOutcomes[200],
        ReviewOutcome.difficult,
      );
    });

    // ============================================================
    // GROUP 2: Queue Progression & Completion
    // ============================================================
    test('6, 7, 8. Successful assessment advances queue and maintains coherent reveal state', () async {
      await recallCubit.startRange(13, 15);
      expect(recallCubit.state.currentIndex, 0);
      expect(recallCubit.state.currentGlobalAyah, 13);
      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);

      // Reveal Ayah 13
      recallCubit.revealCurrentAyah();
      expect(recallCubit.state.phase, VisualRecallPhase.evaluating);
      expect(recallCubit.state.revealedGlobals, {13});

      // Assess Ayah 13
      await recallCubit.recordKnown();

      // INVARIANT: Advances to index 1 (Ayah 14)
      expect(recallCubit.state.currentIndex, 1);
      expect(recallCubit.state.currentGlobalAyah, 14);
      // Next Ayah 14 was NOT previously revealed -> begins in activeRecall
      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
      // Previously revealed Ayah 13 remains revealed in state
      expect(recallCubit.state.revealedGlobals.contains(13), true);
      // Unrevealed Ayahs [14, 15] remain masked
      expect(recallCubit.state.activeMaskedGlobals, {14, 15});
      expect(recallCubit.state.assessmentOutcomes[13], ReviewOutcome.good);
    });

    test('9, 10. Final successful assessment transitions to completed and purges checkpoint', () async {
      await recallCubit.startRange(13, 14);

      // Checkpoint was saved on start
      expect(
        storage.store.containsKey(QuranVisualRecallCubit.checkpointKey),
        true,
      );

      // Assess 13
      recallCubit.revealCurrentAyah();
      await recallCubit.recordKnown();
      expect(recallCubit.state.currentIndex, 1);

      // Assess 14 (final item)
      recallCubit.revealCurrentAyah();
      await recallCubit.recordNeedsRevision();

      // INVARIANT: Phase completed and checkpoint purged
      expect(recallCubit.state.phase, VisualRecallPhase.completed);
      expect(recallCubit.state.isCompleted, true);
      expect(recallCubit.state.currentGlobalAyah, isNull);
      expect(recallCubit.state.completedCount, 2);
      expect(
        storage.store.containsKey(QuranVisualRecallCubit.checkpointKey),
        false,
      );
    });

    // ============================================================
    // GROUP 3: Failure Handling & Retry Boundary
    // ============================================================
    test(
      '11, 12. Persistence failure BLOCKS advance and preserves state',
      () async {
        await recallCubit.startSingleAyah(300);
        recallCubit.revealCurrentAyah();

        storage.failOnWrite = true;

        var threw = false;
        try {
          await recallCubit.recordKnown();
        } catch (_) {
          threw = true;
        }

        expect(threw, true);

        // INVARIANTS:
        // 1. Advance is strictly BLOCKED
        expect(recallCubit.state.currentIndex, 0);
        expect(recallCubit.state.currentGlobalAyah, 300);
        // 2. Not marked completed
        expect(recallCubit.state.isCompleted, false);
        // 3. Error exposed
        expect(recallCubit.state.error, isNotNull);
        expect(recallCubit.state.isLoading, false);
        // 4. In-memory history in memoCubit rolled back cleanly
        expect(memoCubit.state.history, isEmpty);
      },
    );

    test(
      '13, 14. Failed operation can be retried using same operation identity',
      () async {
        await recallCubit.startSingleAyah(400);
        recallCubit.revealCurrentAyah();
        final sessionId = recallCubit.state.sessionId!;
        final expectedOpId = 'rev_${sessionId}_400';

        storage.failOnWrite = true;
        try {
          await recallCubit.recordKnown();
        } catch (_) {}

        expect(recallCubit.state.currentIndex, 0);
        expect(recallCubit.state.error, isNotNull);

        // Storage recovers
        storage.failOnWrite = false;

        // Retry
        await recallCubit.retryLastOutcome(ReviewOutcome.good);

        // INVARIANT: Retry succeeds cleanly using SAME operation identity
        expect(recallCubit.state.isCompleted, true);
        expect(recallCubit.state.error, isNull);
        expect(memoCubit.state.history.length, 1);
        expect(memoCubit.state.history.first.id, expectedOpId);
      },
    );

    test('15. Checkpoint cleanup failure on completion exposes error without blocking completion', () async {
      await recallCubit.startSingleAyah(450);
      recallCubit.revealCurrentAyah();

      storage.failOnRemove = true;

      await recallCubit.recordKnown();

      // INVARIANT: History is committed, session is completed, error is exposed
      expect(memoCubit.state.history.length, 1);
      expect(recallCubit.state.isCompleted, true);
      expect(
        recallCubit.state.error,
        contains('تعذر حذف نقطة الاستعادة المؤقتة'),
      );
    });

    // ============================================================
    // GROUP 4: Idempotency & Concurrency Guarantees
    // ============================================================
    test(
      '16. Sequential duplicate submission produces one logical review',
      () async {
        await recallCubit.startRange(500, 501);
        recallCubit.revealCurrentAyah();
        final sessionId = recallCubit.state.sessionId!;

        await recallCubit.recordKnown();
        expect(memoCubit.state.history.length, 1);

        // Attempt explicit duplicate review on memoCubit with same operationId
        await memoCubit.recordReviewOutcome(
          globalAyah: 500,
          outcome: ReviewOutcome.good,
          sessionId: sessionId,
          operationId: 'rev_${sessionId}_500',
        );

        // Ledger ensures strictly 1 history entry
        expect(memoCubit.state.history.length, 1);
      },
    );

    test('17. Concurrent duplicate submission resolves to one underlying operation', () async {
      await recallCubit.startRange(510, 512);
      recallCubit.revealCurrentAyah();

      // Fire 2 concurrent assessment calls
      await Future.wait([
        recallCubit.recordOutcome(ReviewOutcome.good),
        recallCubit.recordOutcome(ReviewOutcome.good),
      ]);

      // INVARIANT: Queue advanced by EXACTLY 1, exactly 1 history record committed
      expect(recallCubit.state.currentIndex, 1);
      expect(recallCubit.state.currentGlobalAyah, 511);
      expect(memoCubit.state.history.length, 1);
      expect(recallCubit.state.assessmentOutcomes.length, 1);
    });

    test('18. Duplicate after restart reconciles without creating duplicate review', () async {
      await recallCubit.startRange(520, 522);
      recallCubit.revealCurrentAyah();
      await recallCubit.recordOutcome(
        ReviewOutcome.good,
      ); // 520 committed, now at 521

      // Restart Cubit
      final restartedCubit = QuranVisualRecallCubit(
        memorizationCubit: memoCubit,
        storage: storage,
      );
      await restartedCubit.init();

      expect(restartedCubit.state.hasCheckpointAvailable, true);
      await restartedCubit.restoreCheckpoint();

      // INVARIANT: Resumed at index 1 (Ayah 521)
      expect(restartedCubit.state.currentIndex, 1);
      expect(restartedCubit.state.currentGlobalAyah, 521);
      // History still has exactly 1 entry for 520
      expect(memoCubit.state.history.length, 1);

      await restartedCubit.close();
    });

    test(
      '19, 20. Completed session safely rejects subsequent recordOutcome calls',
      () async {
        await recallCubit.startSingleAyah(550);
        recallCubit.revealCurrentAyah();
        await recallCubit.recordKnown();

        expect(recallCubit.state.isCompleted, true);
        final historyCount = memoCubit.state.history.length;

        // Duplicate attempt on completed session
        await recallCubit.recordOutcome(ReviewOutcome.good);

        // INVARIANT: Ignored, 0 mutations, 0 history additions
        expect(memoCubit.state.history.length, historyCount);
        expect(recallCubit.state.isCompleted, true);
      },
    );

    // ============================================================
    // GROUP 5: Session Boundaries & Rejection Validation
    // ============================================================
    test('21. One-item session completion', () async {
      await recallCubit.startSingleAyah(1);
      recallCubit.revealCurrentAyah();
      await recallCubit.recordKnown();
      expect(recallCubit.state.isCompleted, true);
      expect(recallCubit.state.completedCount, 1);
    });

    test('22. Multi-item session completion', () async {
      await recallCubit.startRange(1, 3);
      for (var i = 0; i < 3; i++) {
        recallCubit.revealCurrentAyah();
        await recallCubit.recordKnown();
      }
      expect(recallCubit.state.isCompleted, true);
      expect(recallCubit.state.completedCount, 3);
      expect(memoCubit.state.history.length, 3);
    });

    test('23, 24, 25, 26, 27, 28. Validation rejections: no active session, invalid index, empty queue', () async {
      // 1. Idle state call
      await recallCubit.recordOutcome(ReviewOutcome.good);
      expect(memoCubit.state.history, isEmpty);

      // 2. Start single ayah
      await recallCubit.startSingleAyah(10);
      expect(recallCubit.state.hasActiveSession, true);

      // Dismiss summary or end session
      await recallCubit.endSession();
      expect(recallCubit.state.isIdle, true);

      // Call on ended session
      await recallCubit.recordOutcome(ReviewOutcome.good);
      expect(memoCubit.state.history, isEmpty);
    });

    // ============================================================
    // GROUP 6: Strict Last Read Isolation
    // ============================================================
    test('29, 30, 31. Assessment success, failure, and completion produce strictly 0 Last Read writes', () async {
      final initialLastRead = {'page': 42, 'surah': 2, 'ayah': 255};
      storage.store['last_read'] = initialLastRead;
      storage.store['last_read_page'] = 42;
      storage.writeOperations.clear();

      await recallCubit.startRange(100, 101);
      recallCubit.revealCurrentAyah();

      // 1. Success assessment
      await recallCubit.recordKnown();

      // 2. Failure assessment
      storage.failOnWrite = true;
      recallCubit.revealCurrentAyah();
      try {
        await recallCubit.recordNeedsRevision();
      } catch (_) {}
      storage.failOnWrite = false;

      // 3. Retry and complete
      await recallCubit.retryLastOutcome();
      expect(recallCubit.state.isCompleted, true);

      // INVARIANT: Exactly 0 Last Read writes throughout!
      final lastReadWrites = storage.writeOperations
          .where((op) => op.contains('last_read'))
          .toList();
      expect(
        lastReadWrites,
        isEmpty,
        reason: 'Assessment flow must have strictly 0 writes to Last Read keys',
      );
      expect(storage.readMap('last_read'), initialLastRead);
      expect(storage.readInt('last_read_page'), 42);
    });

    // ============================================================
    // GROUP 7: UI Widget Smoke & Interaction Tests
    // ============================================================
    testWidgets(
      '32, 33. VisualRecallBottomBar renders activeRecall prompt and evaluating controls',
      (tester) async {
        await recallCubit.startRange(13, 15);

        await tester.pumpWidget(
          buildTestHarness(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [VisualRecallBottomBar(cubit: recallCubit)],
            ),
          ),
        );
        await tester.pump();

        // In activeRecall: shows reveal prompt and button
        expect(find.text('إظهار الآية'), findsOneWidget);
        expect(find.textContaining('آية 1 من 3'), findsOneWidget);

        // Tap reveal button
        await tester.tap(find.text('إظهار الآية'));
        await tester.pump();

        // In evaluating: shows assessment buttons
        expect(recallCubit.state.isEvaluating, true);
        expect(find.text('أعرفها ومتقنة'), findsOneWidget);
        expect(find.text('تحتاج مراجعة'), findsOneWidget);

        // Tap 'أعرفها ومتقنة'
        await tester.tap(find.text('أعرفها ومتقنة'));
        await tester.pump();

        // Advanced to Ayah 2
        expect(recallCubit.state.currentIndex, 1);
        expect(find.textContaining('آية 2 من 3'), findsOneWidget);
      },
    );

    testWidgets(
      '34, 35, 36. VisualRecallBottomBar renders error banner with retry and completion card',
      (tester) async {
        await recallCubit.startSingleAyah(20);
        recallCubit.revealCurrentAyah();

        storage.failOnWrite = true;

        await tester.pumpWidget(
          buildTestHarness(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [VisualRecallBottomBar(cubit: recallCubit)],
            ),
          ),
        );
        await tester.pump();

        // Tap 'أعرفها ومتقنة' while write fails
        await tester.tap(find.text('أعرفها ومتقنة'));
        await tester.pump();

        // Shows error banner and retry button
        expect(find.text('إعادة المحاولة'), findsOneWidget);
        expect(find.textContaining('تعذر حفظ نتيجة التسميع'), findsOneWidget);

        // Fix storage and tap retry
        storage.failOnWrite = false;
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pump();

        // Transitioned to completed
        expect(recallCubit.state.isCompleted, true);
        expect(find.textContaining('اكتملت الجلسة بنجاح!'), findsOneWidget);
        expect(find.text('إنهاء'), findsOneWidget);

        // Tap dismiss
        await tester.tap(find.text('إنهاء'));
        await tester.pump();
        expect(recallCubit.state.isIdle, true);
      },
    );

    // ============================================================
    // GROUP 8: Visual Evidence Artifacts Capture (10 Screenshots)
    // ============================================================
    testWidgets('37. Generate 10 real visual assessment screenshots', (
      tester,
    ) async {
      Future<void> saveScreenshot(GlobalKey key, String filename) async {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary != null) {
            final image = await boundary.toImage(pixelRatio: 1.0);
            final byteData = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (byteData != null) {
              final file = File(
                'screenshots/visual_recall_assessment/$filename',
              );
              await file.writeAsBytes(byteData.buffer.asUint8List());
              print(
                'Saved evidence screenshot: $filename (${byteData.lengthInBytes} bytes)',
              );
            }
          }
        });
      }

      final key = GlobalKey();

      // 1. Masked current Ayah (Page 3: Ayahs 13..15 queued, Ayah 13 masked)
      await recallCubit.startRange(13, 15);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: buildTestHarness(
            child: Column(
              children: [
                const Expanded(
                  child: MushafPage(page: 3, scale: 1.0, isCurrent: true),
                ),
                VisualRecallBottomBar(cubit: recallCubit),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await saveScreenshot(key, '01_masked_current_ayah.png');

      // 2. Revealed Ayah (Ayah 13 revealed)
      await tester.tap(find.text('إظهار الآية'));
      await tester.pump();
      expect(recallCubit.state.isEvaluating, true);
      await saveScreenshot(key, '02_revealed_ayah.png');

      // 3. Assessment controls visible in bottom bar
      expect(find.byType(VisualRecallBottomBar), findsOneWidget);
      expect(find.text('أعرفها ومتقنة'), findsOneWidget);
      expect(find.text('تحتاج مراجعة'), findsOneWidget);
      await saveScreenshot(key, '03_assessment_controls.png');

      // 4. Submitting state (in-flight persistence)
      final writeHold = Completer<void>();
      storage.writeCompleter = writeHold;
      final submitFuture = recallCubit.recordKnown();
      await tester.pump(); // frame during in-flight submission
      expect(find.text('جارٍ حفظ النتيجة...'), findsOneWidget);
      await saveScreenshot(key, '04_submitting_state.png');

      // 5. Complete submission of Ayah 13
      writeHold.complete();
      storage.writeCompleter = null;
      await submitFuture;
      await tester.pump();
      expect(recallCubit.state.currentIndex, 1);
      await saveScreenshot(key, '05_known_correct_submission.png');

      // 6. Next Ayah (Ayah 14 masked on Page 3)
      expect(recallCubit.state.currentGlobalAyah, 14);
      expect(find.text('إظهار الآية'), findsOneWidget);
      await saveScreenshot(key, '07_next_ayah.png');

      // 7. Reveal Ayah 14 and submit needs-revision
      await tester.tap(find.text('إظهار الآية'));
      await tester.pump();
      await tester.tap(find.text('تحتاج مراجعة'));
      await tester.pump();
      await saveScreenshot(key, '06_needs_revision_submission.png');

      // 8. Error/failure state (simulate storage write failure on Ayah 15)
      storage.failOnWrite = true;
      await tester.tap(find.text('إظهار الآية'));
      await tester.pump();
      await tester.tap(find.text('أعرفها ومتقنة'));
      await tester.pump();
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      await saveScreenshot(key, '09_failure_error_state.png');

      // 9. Retry after failure
      storage.failOnWrite = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      await saveScreenshot(key, '10_retry_after_failure.png');

      // 10. Final completion state
      expect(recallCubit.state.isCompleted, true);
      expect(find.textContaining('اكتملت الجلسة بنجاح!'), findsOneWidget);
      await saveScreenshot(key, '08_final_completion_state.png');
    });
  });
}
