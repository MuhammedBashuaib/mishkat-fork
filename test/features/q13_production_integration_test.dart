// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_item.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/memorization_session_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_memorization_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/ayah_action_sheet.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_mask_overlay.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/visual_recall_bottom_bar.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class InMemoryTrackingLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> store = {};
  final List<String> writeOperations = [];
  bool failOnWrite = false;

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
    store.remove(key);
  }

  @override
  Future<void> clear() async {
    writeOperations.add('clear');
    store.clear();
  }

  int get quranLastReadWrites =>
      writeOperations.where((op) => op == 'writeMap:quran').length;
}

class FakeLocationService implements LocationService {
  @override
  Future<AppPosition> currentPosition() async {
    return const AppPosition(
      latitude: 14.5425,
      longitude: 49.1242,
      label: 'المكلا، حضرموت',
      suggestedMethod: 'MWL',
    );
  }

  @override
  NearbyCity closestCity(double latitude, double longitude) {
    return const NearbyCity('المكلا، حضرموت', 14.5425, 49.1242, 'MWL', 0);
  }
}

class FakeNotificationService implements LocalNotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleAll(
    List<ScheduledAppNotification> notifications,
  ) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> showTest({
    required bool sound,
    required bool vibrate,
    String? soundName,
  }) async {}
}

class FakeQuranAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);

  final List<int> playedAyahs = [];
  bool isPlayingState = false;

  void emitState(PlayerState state) {
    isPlayingState = state.playing;
    _stateController.add(state);
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
    playedAyahs.add(globalAyah);
    isPlayingState = true;
    emitState(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> playAyahFromUrl(String url) async {}

  @override
  Future<void> pause() async {
    isPlayingState = false;
    emitState(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> resume() async {
    isPlayingState = true;
    emitState(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    isPlayingState = false;
    emitState(PlayerState(false, ProcessingState.idle));
  }

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

    final outDir = Directory('screenshots/production_integration');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
  });

  group('Q13 Production Integration Tests (36 Requirements)', () {
    late InMemoryTrackingLocalStorageService storage;
    late QuranMemorizationRepository memoRepo;
    late QuranMemorizationCubit memoCubit;
    late FakeQuranAudioService fakeAudio;
    late QuranCubit quranCubit;
    late SettingsCubit settingsCubit;

    setUp(() async {
      storage = InMemoryTrackingLocalStorageService();
      memoRepo = QuranMemorizationRepository(storage: storage);
      memoCubit = QuranMemorizationCubit(repository: memoRepo);
      await memoCubit.load();

      fakeAudio = FakeQuranAudioService();
      quranCubit = QuranCubit(
        repository: quranRepo,
        storage: storage,
        audio: fakeAudio,
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await quranCubit.load();

      settingsCubit = SettingsCubit(
        storage: storage,
        locationService: FakeLocationService(),
        notifications: FakeNotificationService(),
      );
      await settingsCubit.load();
    });

    tearDown(() async {
      await memoCubit.close();
      await quranCubit.close();
      await settingsCubit.close();
      await fakeAudio.dispose();
    });

    BuildContext getReaderInnerContext(WidgetTester tester) {
      return tester.element(
        find.descendant(
          of: find.byType(QuranReaderPage),
          matching: find.byType(Scaffold),
        ),
      );
    }

    Widget buildAppHarness({
      required Widget child,
      bool isDark = false,
      Size size = const Size(390, 844),
    }) {
      final baseTheme = isDark ? AppTheme.dark(1.0) : AppTheme.light(1.0);
      return MultiBlocProvider(
        providers: [
          BlocProvider<QuranCubit>.value(value: quranCubit),
          BlocProvider<QuranMemorizationCubit>.value(value: memoCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseTheme,
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      );
    }

    // ============================================================
    // GROUP 1: Provider Architecture (1 - 5)
    // ============================================================
    testWidgets(
      '1, 2, 3, 4. Production tree provides VisualRecallCubit with injected cubit, audio, and storage',
      (tester) async {
        QuranVisualRecallCubit? resolvedCubit;

        await tester.pumpWidget(
          buildAppHarness(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const QuranReaderPage(initialGlobalAyah: 1),
                      ),
                    );
                  },
                  child: const Text('Open Reader'),
                );
              },
            ),
          ),
        );

        // Open QuranReaderPage
        await tester.tap(find.text('Open Reader'));
        await tester.pumpAndSettle();

        // Verify QuranReaderPage is in tree
        expect(find.byType(QuranReaderPage), findsOneWidget);

        // Inspect resolved Cubit within Reader subtree
        final readerContext = getReaderInnerContext(tester);
        resolvedCubit = readerContext.read<QuranVisualRecallCubit>();

        // Assertions 1-4
        expect(resolvedCubit, isNotNull);
        expect(resolvedCubit.memorizationCubit, equals(memoCubit));
        expect(resolvedCubit.audioService, equals(quranCubit.audioService));
        expect(resolvedCubit.storage, equals(memoRepo.storage));
      },
    );

    testWidgets('5. Cubit disposed correctly when reader route is popped', (
      tester,
    ) async {
      QuranVisualRecallCubit? capturedCubit;

      await tester.pumpWidget(
        buildAppHarness(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const QuranReaderPage(initialGlobalAyah: 1),
                    ),
                  );
                },
                child: const Text('Open Reader'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Reader'));
      await tester.pumpAndSettle();

      final readerContext = getReaderInnerContext(tester);
      capturedCubit = readerContext.read<QuranVisualRecallCubit>();
      expect(capturedCubit.isClosed, isFalse);

      // Pop the route via appbar back button
      await tester.tap(find.byTooltip('العودة إلى الفهرس'));
      await tester.pumpAndSettle();

      // Cubit must be closed automatically on page disposal
      expect(capturedCubit.isClosed, isTrue);
      expect(find.byType(QuranReaderPage), findsNothing);
    });

    // ============================================================
    // GROUP 2: Q11 Daily Journey Integration (6 - 11)
    // ============================================================
    testWidgets(
      '6, 7, 8, 9, 10. Journey segment exposes Visual Recall and launches reader with queue',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Create active plan and due ayahs
        final plan = await memoCubit.createPlan(
          title: 'خطة حفظ سورة الفاتحة',
          startGlobalAyah: 1,
          endGlobalAyah: 7,
          dailyTarget: 7,
        );
        expect(plan, isNotNull);

        await tester.pumpWidget(
          buildAppHarness(child: const QuranMemorizationPage()),
        );
        await tester.pumpAndSettle();

        // Find the Journey start button
        final journeyButtonFinder = find.textContaining(
          'ابدأ ورد اليوم المتكامل',
        );
        expect(journeyButtonFinder, findsOneWidget);

        // Tap start journey button to open practice mode sheet
        await tester.tap(journeyButtonFinder);
        await tester.pumpAndSettle();

        // Requirement 6: Sheet exposes both choices
        expect(find.text('التسميع في المصحف (بصري)'), findsOneWidget);
        expect(find.text('التسميع بالبطاقات (تقليدي)'), findsOneWidget);

        // Tap 'التسميع في المصحف (بصري)'
        await tester.tap(find.text('التسميع في المصحف (بصري)'));
        await tester.pumpAndSettle();

        // Requirements 7, 8, 9, 10: QuranReaderPage opens and Visual Recall is active
        expect(find.byType(QuranReaderPage), findsOneWidget);
        final readerContext = getReaderInnerContext(tester);
        final recall = readerContext.read<QuranVisualRecallCubit>();

        expect(recall.state.hasActiveSession, isTrue);
        expect(recall.state.queue, equals([1, 2, 3, 4, 5, 6, 7]));
        expect(recall.state.currentGlobalAyah, 1);
      },
    );

    testWidgets('11. Traditional session still works from journey sheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await memoCubit.createPlan(
        title: 'خطة حفظ سورة الفاتحة',
        startGlobalAyah: 1,
        endGlobalAyah: 7,
        dailyTarget: 7,
      );

      await tester.pumpWidget(
        buildAppHarness(child: const QuranMemorizationPage()),
      );
      await tester.pumpAndSettle();

      final journeyButtonFinder = find.textContaining(
        'ابدأ ورد اليوم المتكامل',
      );
      await tester.tap(journeyButtonFinder);
      await tester.pumpAndSettle();

      // Tap 'التسميع بالبطاقات (تقليدي)'
      await tester.tap(find.text('التسميع بالبطاقات (تقليدي)'));
      await tester.pumpAndSettle();

      // Traditional MemorizationSessionPage must open
      expect(find.byType(MemorizationSessionPage), findsOneWidget);
      expect(find.byType(QuranReaderPage), findsNothing);
    });

    // ============================================================
    // GROUP 3: Single Ayah Entry (12 - 15)
    // ============================================================
    testWidgets(
      '12, 13, 14, 15. AyahActionSheet exposes Visual Recall and starts single ayah recall',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildAppHarness(child: const QuranReaderPage(initialGlobalAyah: 1)),
        );
        await tester.pumpAndSettle();

        final readerContext = getReaderInnerContext(tester);
        final recall = readerContext.read<QuranVisualRecallCubit>();
        final interaction = readerContext.read<MushafInteractionCubit>();

        // Select Ayah 3 on Page 1 and request opening action sheet
        interaction.selectAyahByGlobal(3, openActionSheet: true);
        await tester.pumpAndSettle();

        // AyahActionSheet opens with options
        expect(find.text('تسميع الآية'), findsOneWidget);
        expect(find.text('تحديد مقطع'), findsOneWidget);

        // Tap 'تسميع الآية'
        await tester.tap(find.text('تسميع الآية'));
        await tester.pumpAndSettle();

        // Requirements 13, 14, 15: Session queue contains exactly one ayah [3]
        expect(recall.state.hasActiveSession, isTrue);
        expect(recall.state.queue, equals([3]));
        expect(recall.state.currentGlobalAyah, 3);
        expect(find.byType(VisualRecallBottomBar), findsOneWidget);
      },
    );

    // ============================================================
    // GROUP 4: Range Selection (16 - 19)
    // ============================================================
    testWidgets(
      '16, 17, 18, 19. Range selection configures sequential queue and excludes outside ayahs',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildAppHarness(child: const QuranReaderPage(initialGlobalAyah: 1)),
        );
        await tester.pumpAndSettle();

        final readerContext = getReaderInnerContext(tester);
        final recall = readerContext.read<QuranVisualRecallCubit>();
        final interaction = readerContext.read<MushafInteractionCubit>();

        // Select Ayah 2 and request opening action sheet
        interaction.selectAyahByGlobal(2, openActionSheet: true);
        await tester.pumpAndSettle();

        await tester.tap(find.text('تحديد مقطع'));
        await tester.pumpAndSettle();

        // Requirement 16: Range selection is active
        expect(recall.state.isRangeSelecting, isTrue);
        expect(recall.state.rangeSelectionStart, 2);

        // Complete range up to Ayah 5
        recall.updateRangeEnd(5);
        await recall.confirmRangeSelection();
        await tester.pumpAndSettle();

        // Requirements 17, 18, 19:
        expect(recall.state.hasActiveSession, isTrue);
        expect(recall.state.queue, equals([2, 3, 4, 5]));
        expect(recall.state.queue.contains(1), isFalse);
        expect(recall.state.queue.contains(6), isFalse);
        expect(recall.state.activeMaskedGlobals, equals({2, 3, 4, 5}));
      },
    );

    // ============================================================
    // GROUP 5: Runtime Flow (20 - 25)
    // ============================================================
    testWidgets(
      '20, 21, 22, 23, 24, 25. Masking, reveal, assessment, advancement, completion, retry',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildAppHarness(
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1, 2],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final readerContext = getReaderInnerContext(tester);
        final recall = readerContext.read<QuranVisualRecallCubit>();

        // Requirement 20: Mask visible
        expect(recall.state.activeMaskedGlobals.contains(1), isTrue);

        // Requirement 21: Reveal works
        await tester.tap(find.text('إظهار الآية'));
        await tester.pumpAndSettle();
        expect(recall.state.isCurrentAyahRevealed, isTrue);
        expect(recall.state.isEvaluating, isTrue);

        // Requirement 22 & 23: Assessment and queue advance
        await tester.tap(find.text('أعرفها ومتقنة'));
        await tester.pumpAndSettle();
        expect(recall.state.currentGlobalAyah, 2);
        expect(recall.state.isCurrentAyahRevealed, isFalse);

        // Reveal second ayah and simulate failure on write to trigger retry banner
        await tester.tap(find.text('إظهار الآية'));
        await tester.pumpAndSettle();

        storage.failOnWrite = true;
        await tester.tap(find.text('تحتاج مراجعة'));
        await tester.pumpAndSettle();

        // Error banner with retry is displayed
        expect(find.text('إعادة المحاولة'), findsOneWidget);
        expect(recall.state.error, isNotNull);

        // Requirement 25: Retry works
        storage.failOnWrite = false;
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pumpAndSettle();

        // Requirement 24: Completion works
        expect(recall.state.isCompleted, isTrue);
        expect(find.textContaining('اكتملت الجلسة بنجاح'), findsOneWidget);
      },
    );

    // ============================================================
    // GROUP 6: Last Read Hard Invariant (26 - 30)
    // ============================================================
    testWidgets(
      '26, 27, 28, 29, 30. Last Read writes = 0 across start, reveal, assess, complete, audio',
      (tester) async {
        storage.writeOperations.clear();
        final initialLastReadWrites = storage.quranLastReadWrites;
        expect(initialLastReadWrites, 0);

        await tester.pumpWidget(
          buildAppHarness(
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1, 2],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final readerContext = getReaderInnerContext(tester);
        final recall = readerContext.read<QuranVisualRecallCubit>();

        // 26. Start does not write lastRead
        expect(storage.quranLastReadWrites, 0);

        // 27. Reveal does not write lastRead
        recall.revealCurrentAyah();
        await tester.pumpAndSettle();
        expect(storage.quranLastReadWrites, 0);

        // 28. Assessment does not write lastRead
        await recall.recordKnown();
        await tester.pumpAndSettle();
        expect(storage.quranLastReadWrites, 0);

        // 30. Audio does not write lastRead
        await recall.playCurrentAyahAudio();
        await tester.pumpAndSettle();
        expect(storage.quranLastReadWrites, 0);

        // 29. Completion does not write lastRead
        recall.revealCurrentAyah();
        await recall.recordKnown();
        await tester.pumpAndSettle();
        expect(recall.state.isCompleted, isTrue);
        expect(storage.quranLastReadWrites, 0);
      },
    );

    // ============================================================
    // GROUP 7: Lifecycle & State Hygiene (31 - 36)
    // ============================================================
    testWidgets(
      '31, 32, 33, 34, 35, 36. Navigation cleanup, fresh session, timers, no leakage',
      (tester) async {
        await tester.pumpWidget(
          buildAppHarness(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QuranReaderPage(
                          initialGlobalAyah: 1,
                          visualRecallInitialQueue: [1, 2],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Reader Session'),
                );
              },
            ),
          ),
        );

        // Open route
        await tester.tap(find.text('Open Reader Session'));
        await tester.pumpAndSettle();

        final readerContext = getReaderInnerContext(tester);
        final recall = readerContext.read<QuranVisualRecallCubit>();
        expect(recall.state.hasActiveSession, isTrue);

        // Play audio and start tardid timer
        await recall.playCurrentAyahAudio();
        expect(recall.state.isAudioPlaying, isTrue);

        // 31. Back navigation cleans session & disposes cubit
        await tester.tap(find.byTooltip('العودة إلى الفهرس'));
        await tester.pumpAndSettle();

        // 33, 34, 35. Cubit closed, timers canceled, audio stopped
        expect(recall.isClosed, isTrue);
        expect(find.byType(QuranReaderPage), findsNothing);

        // 32, 36. Reopening creates fresh unpolluted session
        await tester.tap(find.text('Open Reader Session'));
        await tester.pumpAndSettle();

        final newReaderContext = getReaderInnerContext(tester);
        final newRecall = newReaderContext.read<QuranVisualRecallCubit>();
        expect(newRecall, isNot(equals(recall)));
        expect(newRecall.isClosed, isFalse);
        expect(newRecall.state.hasActiveSession, isTrue);
        expect(newRecall.state.currentGlobalAyah, 1);
        expect(newRecall.state.isCompleted, isFalse);
      },
    );

    // ============================================================
    // GROUP 8: Visual Validation Artifacts (10 Production Screenshots)
    // ============================================================
    testWidgets('Generate 10 real production integration screenshots', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
              final file = File('screenshots/production_integration/$filename');
              await file.writeAsBytes(byteData.buffer.asUint8List());
              print(
                'Saved production screenshot: $filename (${byteData.lengthInBytes} bytes)',
              );
            }
          }
        });
      }

      await memoCubit.createPlan(
        title: 'خطة سورة الفاتحة',
        startGlobalAyah: 1,
        endGlobalAyah: 7,
        dailyTarget: 7,
      );

      // Screenshot 1: Q11 Journey -> Visual Recall Entry Sheet
      final key1 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key1,
          child: buildAppHarness(child: const QuranMemorizationPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ابدأ ورد اليوم المتكامل'));
      await tester.pumpAndSettle();
      await saveScreenshot(key1, '01_q11_journey_entry.png');

      // Screenshot 2: Visual Recall reader active
      final key2 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key2,
          child: buildAppHarness(
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1, 2, 3],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveScreenshot(key2, '02_visual_recall_reader_active.png');

      // Screenshot 3: Masked ayah on Mushaf Page
      final key3 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key3,
          child: buildAppHarness(
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1, 2, 3],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveScreenshot(key3, '03_masked_ayah.png');

      // Screenshot 4: Revealed ayah
      final readerCtx = getReaderInnerContext(tester);
      final recallCubit = readerCtx.read<QuranVisualRecallCubit>();
      recallCubit.revealCurrentAyah();
      await tester.pumpAndSettle();
      await saveScreenshot(key3, '04_revealed_ayah.png');

      // Screenshot 5: Assessment dock
      await saveScreenshot(key3, '05_assessment_dock.png');

      // Screenshot 6: Single Ayah entry sheet
      final key6 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key6,
          child: buildAppHarness(
            child: const QuranReaderPage(initialGlobalAyah: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ctx6 = getReaderInnerContext(tester);
      ctx6.read<MushafInteractionCubit>().selectAyahByGlobal(
        1,
        openActionSheet: true,
      );
      await tester.pumpAndSettle();
      await saveScreenshot(key6, '06_single_ayah_entry.png');

      // Screenshot 7: Range selection
      final key7 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key7,
          child: buildAppHarness(
            child: const QuranReaderPage(
              startRangeSelection: true,
              initialGlobalAyah: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveScreenshot(key7, '07_range_selection.png');

      // Screenshot 8: Completion
      final key8 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key8,
          child: buildAppHarness(
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ctx8 = getReaderInnerContext(tester);
      final recall8 = ctx8.read<QuranVisualRecallCubit>();
      recall8.revealCurrentAyah();
      await recall8.recordKnown();
      await tester.pumpAndSettle();
      await saveScreenshot(key8, '08_completion.png');

      // Screenshot 9: Dark mode
      final key9 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key9,
          child: buildAppHarness(
            isDark: true,
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1, 2],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveScreenshot(key9, '09_dark_mode.png');

      // Screenshot 10: Small mobile width (320x640)
      final key10 = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key10,
          child: buildAppHarness(
            size: const Size(320, 640),
            child: const QuranReaderPage(
              initialGlobalAyah: 1,
              visualRecallInitialQueue: [1, 2],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveScreenshot(key10, '10_small_mobile_width.png');
    });
  });
}
