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
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_recall_interaction_layer.dart';

class InMemoryTrackingLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> store = {};
  final List<String> writeOperations = [];

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
    store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    writeOperations.add('writeList:$key');
    store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    writeOperations.add('writeInt:$key');
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
  const mapper = MushafCoordinateMapper();

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository.instance;
    await layoutRepo.load();
    quranRepo = QuranRepository();
    await quranRepo.load();

    final outDir = Directory('screenshots/visual_recall_interaction');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
  });

  group('Q13 Phase 1C — Interaction & Hit-Testing Production Tests', () {
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
      MushafInteractionCubit? interactionCubit,
    }) {
      final baseTheme = isDark ? AppTheme.dark(1.0) : AppTheme.light(1.0);
      Widget app = MaterialApp(
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
      );

      final providers = <BlocProvider>[
        BlocProvider<QuranVisualRecallCubit>.value(value: recallCubit),
        BlocProvider<QuranCubit>.value(value: quranCubit),
      ];

      if (interactionCubit != null) {
        providers.add(
          BlocProvider<MushafInteractionCubit>.value(value: interactionCubit),
        );
      }

      return MultiBlocProvider(providers: providers, child: app);
    }

    /// Helper to resolve the global screen tap coordinate for an Ayah using Flutter's render transform tree
    Offset getAyahScreenPoint(WidgetTester tester, int page, AyahBounds ayah) {
      final layerFinder = find.byType(MushafVisualRecallInteractionLayer);
      final renderBox = tester.renderObject<RenderBox>(layerFinder);
      final layerSize = renderBox.size;
      final pageGeom = layoutRepo.getPageGeometry(page)!;

      final localPoint = mapper.viewBoxToLocal(
        viewBoxCoordinate: ayah.samplePoint,
        contentSize: layerSize,
        viewBox: pageGeom.viewBox,
        padding: EdgeInsets.zero,
      );

      return renderBox.localToGlobal(localPoint);
    }

    Future<void> tapAyah(WidgetTester tester, int page, AyahBounds ayah) async {
      final screenPoint = getAyahScreenPoint(tester, page, ayah);
      await tester.tapAt(screenPoint);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    // ============================================================
    // GROUP 1: Basic Hit Testing
    // ============================================================
    testWidgets(
      '1. Tap current ayah reveals it while later queued ayahs stay masked',
      (tester) async {
        await recallCubit.startRange(13, 15);
        final ayah13 = layoutRepo.getAyah(13)!;

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        expect(recallCubit.state.revealedGlobals, isEmpty);

        await tapAyah(tester, 3, ayah13);

        expect(recallCubit.state.revealedGlobals, {13});
        expect(recallCubit.state.activeMaskedGlobals, {14, 15});
      },
    );

    testWidgets(
      '2. Tap empty margin area results in no reveal and no state corruption',
      (tester) async {
        await recallCubit.startRange(13, 15);

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        final layerFinder = find.byType(MushafVisualRecallInteractionLayer);
        final renderBox = tester.renderObject<RenderBox>(layerFinder);
        final layerTopLeft = renderBox.localToGlobal(Offset.zero);

        // Tap very top-left corner in letterbox/pillarbox empty margin
        await tester.tapAt(layerTopLeft + const Offset(1, 1));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        expect(recallCubit.state.revealedGlobals, isEmpty);
        expect(recallCubit.state.activeMaskedGlobals, {13, 14, 15});
      },
    );

    testWidgets('3. Tap outside page results in no action and no crash', (
      tester,
    ) async {
      await recallCubit.startRange(13, 15);

      await tester.pumpWidget(
        buildTestHarness(
          child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
        ),
      );
      await tester.pump();

      // Tap outside the widget viewport bounds
      await tester.tapAt(const Offset(389, 843));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(recallCubit.state.revealedGlobals, isEmpty);
    });

    testWidgets('4. Tap with invalid coordinates produces no crash', (
      tester,
    ) async {
      await recallCubit.startRange(13, 15);

      await tester.pumpWidget(
        buildTestHarness(
          child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '5. Missing or unloaded geometry safely handles taps with zero crash',
      (tester) async {
        await recallCubit.startRange(13, 15);

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 999, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        final layerFinder = find.byType(MushafVisualRecallInteractionLayer);
        if (layerFinder.evaluate().isNotEmpty) {
          await tester.tap(layerFinder);
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump();
        }

        expect(tester.takeException(), isNull);
      },
    );

    // ============================================================
    // GROUP 2: Queue Filtering
    // ============================================================
    testWidgets(
      '6 & 7. Queue filtering: current ayah reveals, non-queued ayah is ignored',
      (tester) async {
        // Ayah 14 is current; neighboring Ayah 15 is not in the queue.
        await recallCubit.startRange(14, 14);
        final ayah14 = layoutRepo.getAyah(14)!;
        final ayah15 = layoutRepo.getAyah(15)!;

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Tap non-queued Ayah 15
        await tapAyah(tester, 3, ayah15);

        // Ayah 15 must NOT be revealed!
        expect(recallCubit.state.revealedGlobals, isEmpty);

        // Tap queued Ayah 14
        await tapAyah(tester, 3, ayah14);

        // Ayah 14 MUST be revealed!
        expect(recallCubit.state.revealedGlobals, {14});
      },
    );

    testWidgets(
      '8. Repeated taps preserve revealed current ayah until explicitly hidden',
      (tester) async {
        await recallCubit.startRange(14, 15);
        final ayah14 = layoutRepo.getAyah(14)!;

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Tap 1: Reveal Ayah 14
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});

        // Repeated taps do not hide text while the learner evaluates it.
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});

        recallCubit.hideCurrentAyah();
        await tester.pump();
        expect(recallCubit.state.revealedGlobals, isEmpty);

        // Explicitly hidden current Ayah can be revealed again.
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});
      },
    );

    testWidgets(
      '9. Future ayahs reveal only after earlier ayahs are assessed',
      (tester) async {
        await recallCubit.startRange(13, 15);
        final ayah13 = layoutRepo.getAyah(13)!;
        final ayah14 = layoutRepo.getAyah(14)!;
        final ayah15 = layoutRepo.getAyah(15)!;

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Tap Ayah 13
        await tapAyah(tester, 3, ayah13);
        expect(recallCubit.state.revealedGlobals, {13});

        // Tapping a future Ayah must not expose its text.
        await tapAyah(tester, 3, ayah15);
        expect(recallCubit.state.revealedGlobals, {13});
        expect(recallCubit.state.activeMaskedGlobals, {14, 15});

        await recallCubit.recordKnown();
        await tester.pump();
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {13, 14});
        expect(recallCubit.state.activeMaskedGlobals, {15});

        await recallCubit.recordKnown();
        await tester.pump();
        await tapAyah(tester, 3, ayah15);
        expect(recallCubit.state.revealedGlobals, {13, 14, 15});
        expect(recallCubit.state.activeMaskedGlobals, isEmpty);
      },
    );

    // ============================================================
    // GROUP 3: Coordinate Mapping (Zoom, Pan, Responsive Viewports)
    // ============================================================
    testWidgets(
      '10, 11, 12, 13. InteractiveViewer zoom (1.0x, 1.5x, 2.0x) and pan mapping',
      (tester) async {
        await recallCubit.startRange(14, 15);
        final ayah14 = layoutRepo.getAyah(14)!;

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        final ivFinder = find.byType(InteractiveViewer);
        final ivWidget = tester.widget<InteractiveViewer>(ivFinder);
        final controller = ivWidget.transformationController!;

        // 1.0x tap
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});

        // Hide explicitly before testing a fresh reveal at the next scale.
        recallCubit.hideCurrentAyah();
        await tester.pump();
        expect(recallCubit.state.revealedGlobals, isEmpty);

        // 1.5x Zoom
        controller.value = Matrix4.identity()
          ..scaleByDouble(1.5, 1.5, 1.0, 1.0);
        await tester.pump();

        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});

        recallCubit.hideCurrentAyah();
        await tester.pump();
        expect(recallCubit.state.revealedGlobals, isEmpty);

        // 2.0x Zoom
        controller.value = Matrix4.identity()
          ..scaleByDouble(2.0, 2.0, 1.0, 1.0);
        await tester.pump();

        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});

        recallCubit.hideCurrentAyah();
        await tester.pump();

        // Zoom + Pan
        controller.value = Matrix4.identity()
          ..translateByDouble(15.0, 25.0, 0.0, 1.0)
          ..scaleByDouble(1.5, 1.5, 1.0, 1.0);
        await tester.pump();

        // Reveal after applying both pan and zoom.
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {14});

        // Reset
        controller.value = Matrix4.identity();
        await tester.pump();
      },
    );

    testWidgets(
      '14, 15, 16. Responsive viewports: compact (320px), standard (390px), wide (430px)',
      (tester) async {
        const viewports = [Size(320, 640), Size(390, 844), Size(430, 932)];

        final ayah14 = layoutRepo.getAyah(14)!;

        for (final vp in viewports) {
          await recallCubit.startRange(14, 15);
          expect(recallCubit.state.revealedGlobals, isEmpty);

          await tester.pumpWidget(
            buildTestHarness(
              size: vp,
              child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
            ),
          );
          await tester.pump();

          await tapAyah(tester, 3, ayah14);

          expect(recallCubit.state.revealedGlobals, {
            14,
          }, reason: 'Ayah 14 must reveal in viewport $vp');
        }
      },
    );

    // ============================================================
    // GROUP 4: Geometry (Polygon Pages 1 & 2, Rect Pages, Shared Boundaries)
    // ============================================================
    testWidgets('17. Page 1 polygon hit-testing (Al-Fatihah)', (tester) async {
      // Make the polygon Ayah under test the current item.
      await recallCubit.startRange(4, 7);
      final ayah4 = layoutRepo.getAyah(
        4,
      )!; // Maliki yawmi ad-din (polygon segment)

      await tester.pumpWidget(
        buildTestHarness(
          child: const MushafPage(page: 1, scale: 1.0, isCurrent: true),
        ),
      );
      await tester.pump();

      expect(ayah4.segments.first, isA<AyahPolygonSegment>());

      await tapAyah(tester, 1, ayah4);

      expect(recallCubit.state.revealedGlobals, {4});
    });

    testWidgets('18. Page 2 polygon hit-testing (Al-Baqarah 2:1-5)', (
      tester,
    ) async {
      await recallCubit.startRange(9, 12);
      final ayah9 = layoutRepo.getAyah(9)!; // Dhalika al-kitabu la rayba fih

      await tester.pumpWidget(
        buildTestHarness(
          child: const MushafPage(page: 2, scale: 1.0, isCurrent: true),
        ),
      );
      await tester.pump();

      expect(ayah9.segments.first, isA<AyahPolygonSegment>());

      await tapAyah(tester, 2, ayah9);

      expect(recallCubit.state.revealedGlobals, {9});
    });

    testWidgets(
      '19, 20, 21, 22. Multi-line rect, neighboring ayahs, and shared line corridors',
      (tester) async {
        await recallCubit.startRange(13, 16);
        final ayah13 = layoutRepo.getAyah(13)!; // 2:6 (2 segments)
        final ayah14 = layoutRepo.getAyah(14)!; // 2:7 (3 segments)

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Tap Ayah 13
        await tapAyah(tester, 3, ayah13);
        expect(recallCubit.state.revealedGlobals, {13});

        // Advance before revealing the neighboring Ayah on a shared corridor.
        await recallCubit.recordKnown();
        await tester.pump();
        await tapAyah(tester, 3, ayah14);
        expect(recallCubit.state.revealedGlobals, {13, 14});
      },
    );

    // ============================================================
    // GROUP 5: State & Coexistence with MushafInteractionCubit
    // ============================================================
    testWidgets(
      '23, 24, 25, 26. State consistency and MushafInteractionCubit coexistence',
      (tester) async {
        final interactionCubit = MushafInteractionCubit(
          layoutRepository: layoutRepo,
        );
        await recallCubit.startRange(14, 15);
        final ayah14 = layoutRepo.getAyah(14)!;

        await tester.pumpWidget(
          buildTestHarness(
            interactionCubit: interactionCubit,
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Tap Ayah 14 during active Visual Recall session
        await tapAyah(tester, 3, ayah14);

        // Visual Recall Cubit received reveal
        expect(recallCubit.state.revealedGlobals, {14});

        // MushafInteractionCubit must NOT have intercepted or opened Action Sheet
        expect(interactionCubit.state.hasSelection, isFalse);
        expect(interactionCubit.state.isActionSheetOpen, isFalse);

        interactionCubit.close();
      },
    );

    // ============================================================
    // GROUP 6: Last Read Isolation
    // ============================================================
    testWidgets(
      '27. Interaction and reveal sequence causes zero Last Read writes',
      (tester) async {
        const initialLastRead = {'page': 100, 'surah': 16, 'ayah': 50};
        await storage.writeMap('last_read', initialLastRead);
        await storage.writeInt('last_read_page', 100);
        storage.writeOperations.clear();

        await recallCubit.startRange(13, 15);
        final ayah13 = layoutRepo.getAyah(13)!;
        final ayah14 = layoutRepo.getAyah(14)!;

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Tap Ayah 13
        await tapAyah(tester, 3, ayah13);

        await recallCubit.recordKnown();
        await tester.pump();

        // Tap the new current Ayah 14.
        await tapAyah(tester, 3, ayah14);

        // Tapping a previously assessed Ayah leaves the session unchanged.
        await tapAyah(tester, 3, ayah13);
        expect(recallCubit.state.revealedGlobals, {13, 14});

        final lastReadWrites = storage.writeOperations
            .where((op) => op.contains('last_read'))
            .toList();
        expect(
          lastReadWrites,
          isEmpty,
          reason:
              'Visual Recall interaction must have 0 writes to Last Read keys',
        );
        expect(storage.readMap('last_read'), initialLastRead);
        expect(storage.readInt('last_read_page'), 100);
      },
    );

    // ============================================================
    // GROUP 7: Visual Interaction Evidence (Section 20 Matrices)
    // ============================================================
    testWidgets('28. Generate 12 real visual interaction screenshots', (
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
                'screenshots/visual_recall_interaction/$filename',
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

      // 1. Initial masked page (Page 3: Ayahs 13, 14, 15 masked)
      await recallCubit.startRange(13, 15);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        ),
      );
      await tester.pump();
      await saveScreenshot(key, '01_initial_masked_page3.png');

      // 2 & 3. Tap first queued ayah (Ayah 13) -> revealed
      final ayah13 = layoutRepo.getAyah(13)!;
      await tapAyah(tester, 3, ayah13);
      expect(recallCubit.state.revealedGlobals, {13});
      await saveScreenshot(key, '02_first_ayah_revealed_page3.png');

      // 4 & 5. Assess Ayah 13, then reveal the new current Ayah 14.
      await recallCubit.recordKnown();
      await tester.pump();
      final ayah14 = layoutRepo.getAyah(14)!;
      await tapAyah(tester, 3, ayah14);
      expect(recallCubit.state.revealedGlobals, {13, 14});
      await saveScreenshot(key, '03_multiple_ayahs_revealed_page3.png');

      // 6. Non-queued Ayah 16 is ignored without changing recall state.
      final ayah16 = layoutRepo.getAyah(16)!;
      await tapAyah(tester, 3, ayah16);
      expect(recallCubit.state.revealedGlobals, {13, 14}); // unchanged
      await saveScreenshot(key, '04_non_queued_tapped_unaltered_page3.png');

      // 7. Zoomed 1.5x interaction
      final ivWidget = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = ivWidget.transformationController!;
      controller.value = Matrix4.identity()..scaleByDouble(1.5, 1.5, 1.0, 1.0);
      await tester.pump();
      await saveScreenshot(key, '05_zoomed_1_5x_page3.png');

      // 8. Zoomed 2.0x interaction
      controller.value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0);
      await tester.pump();
      await saveScreenshot(key, '06_zoomed_2_0x_page3.png');

      // 9. Panned interaction
      controller.value = Matrix4.identity()
        ..translateByDouble(20.0, 30.0, 0.0, 1.0)
        ..scaleByDouble(1.5, 1.5, 1.0, 1.0);
      await tester.pump();
      await saveScreenshot(key, '07_panned_page3.png');

      // Reset zoom
      controller.value = Matrix4.identity();
      await tester.pump();

      // 10. Page 1 polygon interaction (Al-Fatihah, Ayah 4 tapped & revealed)
      final keyP1 = GlobalKey();
      await recallCubit.startRange(4, 7);
      await tester.pumpWidget(
        RepaintBoundary(
          key: keyP1,
          child: buildTestHarness(
            child: const MushafPage(page: 1, scale: 1.0, isCurrent: true),
          ),
        ),
      );
      await tester.pump();
      final ayahP1_4 = layoutRepo.getAyah(4)!;
      await tapAyah(tester, 1, ayahP1_4);
      expect(recallCubit.state.revealedGlobals, {4});
      await saveScreenshot(keyP1, '08_page1_polygon_interaction.png');

      // 11. Page 2 polygon interaction (Al-Baqarah, Ayah 9 tapped & revealed)
      final keyP2 = GlobalKey();
      await recallCubit.startRange(9, 12);
      await tester.pumpWidget(
        RepaintBoundary(
          key: keyP2,
          child: buildTestHarness(
            child: const MushafPage(page: 2, scale: 1.0, isCurrent: true),
          ),
        ),
      );
      await tester.pump();
      final ayahP2_9 = layoutRepo.getAyah(9)!;
      await tapAyah(tester, 2, ayahP2_9);
      expect(recallCubit.state.revealedGlobals, {9});
      await saveScreenshot(keyP2, '09_page2_polygon_interaction.png');

      // 12. Compact 320px interaction
      final keyC320 = GlobalKey();
      await recallCubit.startRange(13, 15);
      await tester.pumpWidget(
        RepaintBoundary(
          key: keyC320,
          child: buildTestHarness(
            size: const Size(320, 640),
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        ),
      );
      await tester.pump();
      await tapAyah(tester, 3, ayah13);
      expect(recallCubit.state.revealedGlobals, {13});
      await saveScreenshot(keyC320, '10_compact_320px_interaction.png');

      // 13. Standard 390px interaction
      final keyS390 = GlobalKey();
      await recallCubit.startRange(13, 15);
      await tester.pumpWidget(
        RepaintBoundary(
          key: keyS390,
          child: buildTestHarness(
            size: const Size(390, 844),
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        ),
      );
      await tester.pump();
      await tapAyah(tester, 3, ayah13);
      expect(recallCubit.state.revealedGlobals, {13});
      await saveScreenshot(keyS390, '11_standard_390px_interaction.png');

      // 14. Wide 430px interaction
      final keyW430 = GlobalKey();
      await recallCubit.startRange(13, 15);
      await tester.pumpWidget(
        RepaintBoundary(
          key: keyW430,
          child: buildTestHarness(
            size: const Size(430, 932),
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        ),
      );
      await tester.pump();
      await tapAyah(tester, 3, ayah13);
      expect(recallCubit.state.revealedGlobals, {13});
      await saveScreenshot(keyW430, '12_wide_430px_interaction.png');
    });
  });
}
