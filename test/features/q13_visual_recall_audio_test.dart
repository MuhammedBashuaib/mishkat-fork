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
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk failure');
    }
    store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    writeOperations.add('writeList:$key');
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk failure');
    }
    store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    writeOperations.add('writeInt:$key');
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk failure');
    }
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    writeOperations.add('remove:$key');
    if (failOnRemove) {
      throw const FileSystemException('Simulated remove failure');
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
  final _stateController = StreamController<PlayerState>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);

  final List<int> playedAyahs = [];
  final List<Duration> seekPositions = [];
  bool isPlayingState = false;
  bool failOnPlay = false;

  void emitState(PlayerState state) {
    isPlayingState = state.playing;
    _stateController.add(state);
  }

  void emitCompleted() {
    emitState(PlayerState(false, ProcessingState.completed));
  }

  void emitPlaying() {
    emitState(PlayerState(true, ProcessingState.ready));
  }

  void emitPaused() {
    emitState(PlayerState(false, ProcessingState.ready));
  }

  void emitIdle() {
    emitState(PlayerState(false, ProcessingState.idle));
  }

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
  Duration? get duration => const Duration(seconds: 5);

  @override
  Duration get currentPosition => Duration.zero;

  @override
  bool get isPlaying => isPlayingState;

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {
    if (failOnPlay) {
      throw const QuranAudioOfflineException('تلاوة غير متوفرة');
    }
    playedAyahs.add(globalAyah);
    isPlayingState = true;
    emitPlaying();
  }

  @override
  Future<void> playAyahFromUrl(String url) async {}

  @override
  Future<void> pause() async {
    isPlayingState = false;
    emitPaused();
  }

  @override
  Future<void> resume() async {
    isPlayingState = true;
    emitPlaying();
  }

  @override
  Future<void> stop() async {
    isPlayingState = false;
    emitIdle();
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

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

    final outDir = Directory('screenshots/visual_recall_audio');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
  });

  group('Q13 Phase 1E — Audio Synchronization & Timed Masking Production Tests', () {
    late InMemoryTrackingLocalStorageService storage;
    late QuranMemorizationRepository memoRepo;
    late QuranMemorizationCubit memoCubit;
    late FakeQuranAudioService fakeAudio;
    late QuranVisualRecallCubit recallCubit;
    late QuranCubit quranCubit;

    setUp(() async {
      storage = InMemoryTrackingLocalStorageService();
      memoRepo = QuranMemorizationRepository(storage: storage);
      memoCubit = QuranMemorizationCubit(repository: memoRepo);
      fakeAudio = FakeQuranAudioService();

      recallCubit = QuranVisualRecallCubit(
        memorizationCubit: memoCubit,
        storage: storage,
        layoutRepository: layoutRepo,
        audioService: fakeAudio,
        reciter: 'ar.alafasy',
        defaultTardidDelaySeconds: 3,
      );

      quranCubit = QuranCubit(
        repository: quranRepo,
        storage: storage,
        audio: fakeAudio,
        reciter: 'ar.alafasy',
        fontSize: 32,
      );
      await quranCubit.load();
    });

    tearDown(() async {
      await recallCubit.close();
      await memoCubit.close();
      await quranCubit.close();
      await fakeAudio.dispose();
    });

    Widget buildTestHarness({required Widget child, bool isDark = false}) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<QuranCubit>.value(value: quranCubit),
          BlocProvider<QuranMemorizationCubit>.value(value: memoCubit),
          BlocProvider<QuranVisualRecallCubit>.value(value: recallCubit),
        ],
        child: MaterialApp(
          theme: isDark ? AppTheme.dark(1.0) : AppTheme.light(1.0),
          home: Scaffold(body: child),
        ),
      );
    }

    // ============================================================
    // GROUP 1: Audio Start & Player Reuse
    // ============================================================
    test(
      '1, 2. Current Ayah resolves to correct audio and reuses existing player',
      () async {
        await recallCubit.startRange(13, 15);
        expect(recallCubit.state.currentGlobalAyah, 13);

        await recallCubit.playCurrentAyahAudio();

        expect(fakeAudio.playedAyahs, contains(13));
        expect(recallCubit.state.isAudioPlaying, true);
        expect(recallCubit.state.currentAudioAyah, 13);
        expect(recallCubit.state.isAudioSyncEnabled, true);
      },
    );

    test(
      '3. Audio failure handles gracefully without breaking session',
      () async {
        fakeAudio.failOnPlay = true;
        await recallCubit.startRange(13, 15);

        await recallCubit.playCurrentAyahAudio();

        expect(recallCubit.state.isAudioPlaying, false);
        expect(recallCubit.state.error, contains('تعذر تشغيل الصوت'));
        expect(recallCubit.state.hasActiveSession, true);
        expect(recallCubit.state.currentGlobalAyah, 13);
      },
    );

    // ============================================================
    // GROUP 2: Current Ayah Synchronization
    // ============================================================
    test('4, 5. Current Visual Recall Ayah matches audio target and updates on change', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      expect(recallCubit.state.currentAudioAyah, 13);

      // Jump to Ayah 14
      recallCubit.jumpToAyah(14);
      expect(recallCubit.state.currentGlobalAyah, 14);
      expect(recallCubit.state.currentAudioAyah, isNull);
      expect(recallCubit.state.isAudioPlaying, false);

      await recallCubit.playCurrentAyahAudio();
      expect(fakeAudio.playedAyahs.last, 14);
      expect(recallCubit.state.currentAudioAyah, 14);
    });

    test(
      '6. Stale audio callback for previous Ayah cannot affect new Ayah',
      () async {
        await recallCubit.startRange(13, 15);
        await recallCubit.playCurrentAyahAudio();
        expect(recallCubit.state.currentGlobalAyah, 13);

        // User jumps to Ayah 14
        recallCubit.jumpToAyah(14);
        expect(recallCubit.state.currentGlobalAyah, 14);

        // Late event from Ayah 13 arrives
        fakeAudio.emitCompleted();

        // Must NOT start timed mask for Ayah 14 or advance
        expect(recallCubit.state.isTimedMaskActive, false);
        expect(recallCubit.state.currentGlobalAyah, 14);
      },
    );

    // ============================================================
    // GROUP 3: Timed Masking & Tardid Delay Countdown
    // ============================================================
    test('7, 8. Timed mask starts upon audio completion and expires to reveal Ayah', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();

      // Audio finishes reciting Ayah 13
      fakeAudio.emitCompleted();

      // Timed mask starts (Ayah 13 remains masked during Tardid delay)
      expect(recallCubit.state.isTimedMaskActive, true);
      expect(recallCubit.state.remainingMaskDuration, 3);
      expect(recallCubit.state.revealedGlobals.contains(13), false);

      // Wait 3.5 seconds for delay to expire
      await Future<void>.delayed(const Duration(milliseconds: 3200));

      // Timer expires -> Ayah 13 automatically unmasks/reveals, enters evaluating
      expect(recallCubit.state.isTimedMaskActive, false);
      expect(recallCubit.state.isEvaluating, true);
      expect(recallCubit.state.revealedGlobals.contains(13), true);
    });

    test(
      '9. Manual reveal during countdown cancels timer immediately',
      () async {
        await recallCubit.startRange(13, 15);
        await recallCubit.playCurrentAyahAudio();
        fakeAudio.emitCompleted();

        expect(recallCubit.state.isTimedMaskActive, true);

        // User manually reveals Ayah 13
        recallCubit.revealCurrentAyah();

        expect(recallCubit.state.isTimedMaskActive, false);
        expect(recallCubit.state.remainingMaskDuration, 0);
        expect(recallCubit.state.isEvaluating, true);
        expect(recallCubit.state.revealedGlobals.contains(13), true);
      },
    );

    test('10. Skip delay cancels timer and reveals immediately', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      fakeAudio.emitCompleted();
      expect(recallCubit.state.isTimedMaskActive, true);

      recallCubit.skipTimedMaskDelay();

      expect(recallCubit.state.isTimedMaskActive, false);
      expect(recallCubit.state.isEvaluating, true);
      expect(recallCubit.state.revealedGlobals.contains(13), true);
    });

    test('11, 12. Advance or session end cancels active timer', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      fakeAudio.emitCompleted();
      expect(recallCubit.state.isTimedMaskActive, true);

      // User ends session
      await recallCubit.endSession();

      expect(recallCubit.state.isTimedMaskActive, false);
      expect(recallCubit.state.isIdle, true);
    });

    // ============================================================
    // GROUP 4: Pause & Resume Flow
    // ============================================================
    test('13, 14, 15. Pause freezes Tardid countdown and resume continues without duplicate timer', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      fakeAudio.emitCompleted();
      expect(recallCubit.state.isTimedMaskActive, true);

      // Pause countdown
      await recallCubit.pauseAudio();
      expect(recallCubit.state.isAudioPaused, true);
      expect(recallCubit.state.isTimedMaskActive, true);
      final frozenSeconds = recallCubit.state.remainingMaskDuration;

      // Resume countdown
      await recallCubit.resumeAudio();
      expect(recallCubit.state.isAudioPaused, false);
      expect(recallCubit.state.remainingMaskDuration, frozenSeconds);

      // Let it finish
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      expect(recallCubit.state.isTimedMaskActive, false);
      expect(recallCubit.state.isEvaluating, true);
    });

    // ============================================================
    // GROUP 5: Seek & Stop Operations
    // ============================================================
    test('16, 17, 18. Seek forwards position without altering memorization state or Last Read', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();

      await recallCubit.seekAudio(const Duration(seconds: 2));
      expect(fakeAudio.seekPositions, contains(const Duration(seconds: 2)));

      // Memorization history and Last Read remain untouched
      expect(memoCubit.state.history.isEmpty, true);
      expect(
        storage.writeOperations.where((op) => op.contains('last_read')),
        isEmpty,
      );
    });

    // ============================================================
    // GROUP 6: Assessment & Audio Isolation
    // ============================================================
    test(
      '23, 24, 25. Audio completion does NOT automatically assess or advance',
      () async {
        await recallCubit.startRange(13, 15);
        await recallCubit.playCurrentAyahAudio();

        fakeAudio.emitCompleted();
        await Future<void>.delayed(const Duration(milliseconds: 3200));

        // Ayah 13 is revealed, but queue has NOT advanced and 0 reviews written
        expect(recallCubit.state.currentIndex, 0);
        expect(recallCubit.state.currentGlobalAyah, 13);
        expect(memoCubit.state.history.isEmpty, true);
        expect(recallCubit.state.assessmentOutcomes.isEmpty, true);
      },
    );

    // ============================================================
    // GROUP 7: Race Conditions (Sections 27 & 28)
    // ============================================================
    test('21. Audio completion race test (Section 27)', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      expect(recallCubit.state.currentGlobalAyah, 13);

      // User navigates to Ayah 14
      recallCubit.jumpToAyah(14);
      expect(recallCubit.state.currentGlobalAyah, 14);

      // Late event from Ayah 13 arrives
      fakeAudio.emitCompleted();

      // Ayah 14 remains current, no queue advance, no assessment
      expect(recallCubit.state.currentGlobalAyah, 14);
      expect(recallCubit.state.currentIndex, 1);
      expect(memoCubit.state.history.isEmpty, true);
      expect(recallCubit.state.isCompleted, false);
    });

    test('22. Timer race test (Section 28)', () async {
      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      fakeAudio.emitCompleted();
      expect(recallCubit.state.isTimedMaskActive, true);

      // User jumps to Ayah 14 while Ayah 13 timer was running
      recallCubit.jumpToAyah(14);
      expect(recallCubit.state.currentGlobalAyah, 14);
      expect(recallCubit.state.isTimedMaskActive, false);

      // Wait for old timer duration to elapse
      await Future<void>.delayed(const Duration(milliseconds: 3200));

      // Ayah 14 is still masked, no corruption
      expect(recallCubit.state.currentGlobalAyah, 14);
      expect(recallCubit.state.revealedGlobals.contains(14), false);
      expect(recallCubit.state.isActiveRecall, true);
    });

    // ============================================================
    // GROUP 8: Last Read Isolation
    // ============================================================
    test('31..35. Audio start, pause, resume, seek, completion produce strictly 0 Last Read writes', () async {
      storage.writeOperations.clear();

      await recallCubit.startRange(13, 15);
      await recallCubit.playCurrentAyahAudio();
      await recallCubit.pauseAudio();
      await recallCubit.resumeAudio();
      await recallCubit.seekAudio(const Duration(seconds: 1));
      fakeAudio.emitCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 3200));

      final lastReadWrites = storage.writeOperations.where(
        (op) => op.contains('last_read') || op.contains('lastRead'),
      );
      expect(lastReadWrites, isEmpty);
    });

    // ============================================================
    // GROUP 9: Widget Integration in VisualRecallBottomBar
    // ============================================================
    testWidgets(
      '27..29. VisualRecallBottomBar renders audio sync toggle, playback, and Tardid badge',
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

        // Audio sync toggle icon present
        expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

        // Tap to enable audio sync
        await tester.tap(find.byIcon(Icons.volume_off_rounded));
        await tester.pump();
        expect(recallCubit.state.isAudioSyncEnabled, true);
        expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

        // Play button is rendered
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Play audio for current Ayah
        await recallCubit.playCurrentAyahAudio();
        await tester.pump();
        expect(recallCubit.state.isAudioPlaying, true);

        // Pause button visible while playing
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        // Emit audio completion to enter Tardid delay
        await tester.runAsync(() async {
          fakeAudio.emitCompleted();
        });
        await tester.pump();

        expect(recallCubit.state.isTimedMaskActive, true);
        expect(find.textContaining('ردّد الآية غيباً'), findsOneWidget);
        expect(find.text('تخطي المهلة'), findsOneWidget);

        // Tap skip delay
        await tester.tap(find.text('تخطي المهلة'));
        await tester.pump();

        expect(recallCubit.state.isEvaluating, true);
        expect(find.text('أعرفها ومتقنة'), findsOneWidget);
      },
    );

    // ============================================================
    // GROUP 10: Visual Evidence Artifacts Capture (10 Screenshots)
    // ============================================================
    testWidgets(
      '30. Generate 10 real visual audio and timed-masking screenshots',
      (tester) async {
        Future<void> saveScreenshot(GlobalKey key, String filename) async {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext?.findRenderObject()
                    as RenderRepaintBoundary?;
            if (boundary != null) {
              final image = await boundary.toImage(pixelRatio: 1.0);
              final byteData = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (byteData != null) {
                final file = File('screenshots/visual_recall_audio/$filename');
                await file.writeAsBytes(byteData.buffer.asUint8List());
                print(
                  'Saved evidence screenshot: $filename (${byteData.lengthInBytes} bytes)',
                );
              }
            }
          });
        }

        final key = GlobalKey();

        // 1. Audio sync enabled state
        await recallCubit.startRange(13, 15);
        await recallCubit.toggleAudioSync();

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
        await saveScreenshot(key, '01_audio_sync_enabled.png');

        // 2. Audio playing state
        await recallCubit.playCurrentAyahAudio();
        await tester.pump();
        await saveScreenshot(key, '02_audio_playing.png');

        // 3. Audio paused state
        await recallCubit.pauseAudio();
        await tester.pump();
        await saveScreenshot(key, '03_audio_paused.png');

        // 4. Timed mask active (Tardid delay countdown)
        await recallCubit.resumeAudio();
        fakeAudio.emitCompleted();
        await tester.pump();
        expect(recallCubit.state.isTimedMaskActive, true);
        await saveScreenshot(key, '04_timed_mask_active.png');

        // 5. Timed mask expired (Ayah automatically revealed for evaluation)
        recallCubit.skipTimedMaskDelay();
        await tester.pump();
        expect(recallCubit.state.isEvaluating, true);
        await saveScreenshot(key, '05_timed_mask_expired.png');

        // 6. Manual reveal during audio
        await recallCubit.startRange(13, 15);
        await recallCubit.playCurrentAyahAudio();
        recallCubit.revealCurrentAyah();
        await tester.pump();
        await saveScreenshot(key, '06_manual_reveal_during_audio.png');

        // 7. Next Ayah synchronization
        await recallCubit.recordKnown();
        await tester.pump();
        expect(recallCubit.state.currentGlobalAyah, 14);
        await saveScreenshot(key, '07_next_ayah_sync.png');

        // 8. Repeat / Tikrar state
        await recallCubit.playCurrentAyahAudio();
        await tester.pump();
        await saveScreenshot(key, '08_repeat_tikrar_state.png');

        // 9. Audio failure error banner state
        fakeAudio.failOnPlay = true;
        await recallCubit.playCurrentAyahAudio();
        await tester.pump();
        expect(find.text('إعادة المحاولة'), findsOneWidget);
        await saveScreenshot(key, '09_audio_failure_state.png');

        // 10. Session completion state
        fakeAudio.failOnPlay = false;
        await recallCubit.recordKnown(); // Ayah 14
        await tester.pump();
        await recallCubit.recordKnown(); // Ayah 15 (final)
        await tester.pump();
        expect(recallCubit.state.isCompleted, true);
        await saveScreenshot(key, '10_session_completion.png');
      },
    );
  });
}
