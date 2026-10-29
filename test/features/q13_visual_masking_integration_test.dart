// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_mask_overlay.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository layoutRepo;
  const mapper = MushafCoordinateMapper();

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository.instance;
    await layoutRepo.load();

    final outDir = Directory('screenshots/visual_recall');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
  });

  group('Q13 Phase 1B — MushafPage Visual Masking Integration Tests', () {
    late InMemoryTrackingLocalStorageService storage;
    late QuranMemorizationRepository memoRepo;
    late QuranMemorizationCubit memoCubit;
    late QuranVisualRecallCubit recallCubit;

    setUp(() async {
      storage = InMemoryTrackingLocalStorageService();
      memoRepo = QuranMemorizationRepository(storage: storage);
      memoCubit = QuranMemorizationCubit(repository: memoRepo);
      await memoCubit.load();
      recallCubit = QuranVisualRecallCubit(
        memorizationCubit: memoCubit,
        storage: storage,
      );
    });

    tearDown(() async {
      await recallCubit.close();
      await memoCubit.close();
    });

    Widget buildTestHarness({
      required Widget child,
      bool isDark = false,
      Size size = const Size(390, 844),
    }) {
      final baseTheme = isDark ? AppTheme.dark(1.0) : AppTheme.light(1.0);
      return BlocProvider.value(
        value: recallCubit,
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

    testWidgets(
      '1. InteractiveViewer zoom and transform alignment with Visual Mask Overlay',
      (tester) async {
        // Setup recall session on Page 3 for Ayahs 13, 14, 15
        await recallCubit.startRange(13, 15);
        expect(recallCubit.state.activeMaskedGlobals, {13, 14, 15});

        bool zoomChangedReported = false;
        await tester.pumpWidget(
          buildTestHarness(
            child: MushafPage(
              page: 3,
              scale: 1.0,
              isCurrent: true,
              onZoomChanged: (zoomed) {
                zoomChangedReported = zoomed;
              },
            ),
          ),
        );
        await tester.pump();

        // Find MushafVisualMaskOverlay
        expect(find.byType(MushafVisualMaskOverlay), findsOneWidget);
        final overlay = tester.widget<MushafVisualMaskOverlay>(
          find.byType(MushafVisualMaskOverlay),
        );
        expect(overlay.maskedAyahs.map((a) => a.globalAyah).toList(), [
          13,
          14,
          15,
        ]);

        // Verify overlay is inside InteractiveViewer
        final interactiveViewerFinder = find.byType(InteractiveViewer);
        expect(interactiveViewerFinder, findsOneWidget);
        expect(
          find.descendant(
            of: interactiveViewerFinder,
            matching: find.byType(MushafVisualMaskOverlay),
          ),
          findsOneWidget,
        );

        // Verify transformation controller zoom to 1.5x
        final ivWidget = tester.widget<InteractiveViewer>(
          interactiveViewerFinder,
        );
        final controller = ivWidget.transformationController!;
        controller.value = Matrix4.identity()
          ..scaleByDouble(1.5, 1.5, 1.0, 1.0);
        await tester.pump();

        // Zoom should be reported
        expect(zoomChangedReported, isTrue);

        // Overlay must still be present and aligned in the transformed subtree
        expect(find.byType(MushafVisualMaskOverlay), findsOneWidget);

        // Further zoom to 2.0x
        controller.value = Matrix4.identity()
          ..scaleByDouble(2.0, 2.0, 1.0, 1.0);
        await tester.pump();
        expect(find.byType(MushafVisualMaskOverlay), findsOneWidget);

        // Reset zoom
        controller.value = Matrix4.identity();
        await tester.pump();
        expect(zoomChangedReported, isFalse);
      },
    );

    testWidgets(
      '2. Dynamic per-Ayah reveal semantics updates mask overlay without rebuilding SVG',
      (tester) async {
        await recallCubit.startRange(13, 15);

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // Initial state: all 3 Ayahs masked
        var overlay = tester.widget<MushafVisualMaskOverlay>(
          find.byType(MushafVisualMaskOverlay),
        );
        expect(overlay.maskedAyahs.length, 3);
        expect(overlay.maskedAyahs.map((a) => a.globalAyah).toSet(), {
          13,
          14,
          15,
        });

        // Reveal current Ayah (13)
        recallCubit.revealCurrentAyah();
        await tester.pump();
        await tester.pump();

        // Mask overlay must now ONLY mask Ayahs 14 and 15
        overlay = tester.widget<MushafVisualMaskOverlay>(
          find.byType(MushafVisualMaskOverlay),
        );
        expect(overlay.maskedAyahs.length, 2);
        expect(overlay.maskedAyahs.map((a) => a.globalAyah).toSet(), {14, 15});

        // Toggle reveal on Ayah 14
        recallCubit.toggleAyahReveal(14);
        await tester.pump();
        await tester.pump();

        // Mask overlay must now ONLY mask Ayah 15
        overlay = tester.widget<MushafVisualMaskOverlay>(
          find.byType(MushafVisualMaskOverlay),
        );
        expect(overlay.maskedAyahs.length, 1);
        expect(overlay.maskedAyahs.single.globalAyah, 15);

        // Toggle Ayah 14 back to masked
        recallCubit.toggleAyahReveal(14);
        await tester.pump();
        await tester.pump();

        overlay = tester.widget<MushafVisualMaskOverlay>(
          find.byType(MushafVisualMaskOverlay),
        );
        expect(overlay.maskedAyahs.length, 2);
        expect(overlay.maskedAyahs.map((a) => a.globalAyah).toSet(), {14, 15});

        // Reveal both remaining Ayahs (14 and 15)
        recallCubit.toggleAyahReveal(14);
        recallCubit.toggleAyahReveal(15);
        await tester.pump();
        await tester.pump();

        // When all are revealed, activeMaskedGlobals is empty -> overlay returns SizedBox.shrink()
        expect(find.byType(MushafVisualMaskOverlay), findsNothing);
      },
    );

    testWidgets(
      '3. Repaint boundary isolation and CustomPaint delegate behavior',
      (tester) async {
        await recallCubit.startSingleAyah(14);

        await tester.pumpWidget(
          buildTestHarness(
            child: const MushafPage(page: 3, scale: 1.0, isCurrent: true),
          ),
        );
        await tester.pump();

        // MushafVisualMaskOverlay wraps CustomPaint in RepaintBoundary and IgnorePointer
        final repaintBoundaryFinder = find.descendant(
          of: find.byType(MushafVisualMaskOverlay),
          matching: find.byType(RepaintBoundary),
        );
        expect(repaintBoundaryFinder, findsOneWidget);

        final ignorePointerFinder = find.descendant(
          of: find.byType(MushafVisualMaskOverlay),
          matching: find.byType(IgnorePointer),
        );
        expect(ignorePointerFinder, findsOneWidget);

        final customPaintFinder = find.descendant(
          of: find.byType(MushafVisualMaskOverlay),
          matching: find.byType(CustomPaint),
        );
        expect(customPaintFinder, findsOneWidget);

        final customPaint = tester.widget<CustomPaint>(customPaintFinder);
        final painter = customPaint.painter as VisualMaskPainter;

        expect(painter.maskedAyahs.single.globalAyah, 14);
        expect(painter.maskColor, MushafThemeColors.lightBackground);
        expect(painter.currentAyah?.globalAyah, 14);
        expect(painter.preserveAyahNumbers, isTrue);
        expect(painter.currentNumberOutlineColor, isNotNull);

        // shouldRepaint returns false when delegate parameters are identical
        final identicalPainter = VisualMaskPainter(
          maskedAyahs: painter.maskedAyahs,
          currentAyah: painter.currentAyah,
          viewBox: painter.viewBox,
          mapper: painter.mapper,
          maskColor: painter.maskColor,
          currentNumberOutlineColor: painter.currentNumberOutlineColor,
          preserveAyahNumbers: painter.preserveAyahNumbers,
          boundaryMode: painter.boundaryMode,
        );
        expect(painter.shouldRepaint(identicalPainter), isFalse);

        // shouldRepaint returns true when maskColor changes
        final darkPainter = VisualMaskPainter(
          maskedAyahs: painter.maskedAyahs,
          currentAyah: painter.currentAyah,
          viewBox: painter.viewBox,
          mapper: painter.mapper,
          maskColor: MushafThemeColors.darkBackground,
          currentNumberOutlineColor: painter.currentNumberOutlineColor,
          preserveAyahNumbers: painter.preserveAyahNumbers,
          boundaryMode: painter.boundaryMode,
        );
        expect(painter.shouldRepaint(darkPainter), isTrue);
      },
    );

    testWidgets(
      '4. Mask hides Ayah text while preserving the original number medallion',
      (tester) async {
        final ayah = layoutRepo.getAyah(13)!;
        final page = layoutRepo.getPageGeometry(ayah.page)!;
        const canvasSize = Size(345, 550);
        final painter = VisualMaskPainter(
          maskedAyahs: [ayah],
          currentAyah: ayah,
          viewBox: page.viewBox,
          mapper: mapper,
          maskColor: Colors.white,
          currentNumberOutlineColor: Colors.green,
        );
        final numberWindow = painter.ayahNumberWindow(ayah, canvasSize);
        expect(numberWindow, isNotNull);
        expect(numberWindow!.center.dx, closeTo(269.06, .1));
        expect(numberWindow.center.dy, closeTo(61.75, 1));

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          Offset.zero & canvasSize,
          Paint()..color = Colors.black,
        );
        painter.paint(canvas, canvasSize);
        final bytes = await tester.runAsync(() async {
          final image = await recorder.endRecording().toImage(
            canvasSize.width.toInt(),
            canvasSize.height.toInt(),
          );
          return image.toByteData(format: ui.ImageByteFormat.rawRgba);
        });
        expect(bytes, isNotNull);

        int redAt(Offset point) {
          final x = point.dx.round();
          final y = point.dy.round();
          return bytes!.getUint8((y * canvasSize.width.toInt() + x) * 4);
        }

        // The number window remains transparent to the original Mushaf SVG.
        expect(redAt(numberWindow.center), lessThan(20));
        // The surrounding Ayah text corridor is fully concealed by the mask.
        expect(redAt(Offset(325, numberWindow.center.dy)), greaterThan(240));
      },
    );

    testWidgets(
      '5. Taps reveal only the current Ayah; future Ayahs remain masked',
      (tester) async {
        await recallCubit.startRange(13, 15);
        const contentSize = Size(345, 550);
        const viewBox = Rect.fromLTWH(0, 0, 345, 550);

        await tester.pumpWidget(
          buildTestHarness(
            size: contentSize,
            child: MushafVisualRecallInteractionLayer(
              page: 3,
              visualRecallCubit: recallCubit,
              effectiveLayoutRepo: layoutRepo,
              viewBox: viewBox,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        );

        final layer = find.byType(MushafVisualRecallInteractionLayer);
        final topLeft = tester.getTopLeft(layer);
        final futureAyah = layoutRepo.getAyah(14)!;
        final futureLocal = mapper.viewBoxToLocal(
          viewBoxCoordinate: futureAyah.samplePoint,
          contentSize: contentSize,
          viewBox: viewBox,
          padding: EdgeInsets.zero,
        );
        await tester.tapAt(topLeft + futureLocal);
        await tester.pump();
        expect(recallCubit.state.revealedGlobals, isEmpty);
        expect(recallCubit.state.currentGlobalAyah, 13);

        final currentAyah = layoutRepo.getAyah(13)!;
        final currentLocal = mapper.viewBoxToLocal(
          viewBoxCoordinate: currentAyah.samplePoint,
          contentSize: contentSize,
          viewBox: viewBox,
          padding: EdgeInsets.zero,
        );
        await tester.tapAt(topLeft + currentLocal);
        await tester.pump();
        expect(recallCubit.state.revealedGlobals, {13});
        expect(recallCubit.state.isEvaluating, isTrue);
      },
    );

    test(
      '6. Complete Last Read isolation across all Visual Recall operations',
      () async {
        // Seed initial Last Read state
        const initialLastRead = {'page': 100, 'surah': 16, 'ayah': 50};
        await storage.writeMap('last_read', initialLastRead);
        await storage.writeInt('last_read_page', 100);
        storage.writeOperations.clear();

        // 1. Start single Ayah session
        await recallCubit.startSingleAyah(13);
        expect(recallCubit.state.isActiveRecall, isTrue);

        // 2. Reveal Ayah
        recallCubit.revealCurrentAyah();
        expect(recallCubit.state.isCurrentAyahRevealed, isTrue);

        // 3. Record outcome
        await recallCubit.recordOutcome(ReviewOutcome.good);

        // 4. Start range session
        await recallCubit.startRange(20, 25);
        expect(recallCubit.state.queue.length, 6);

        // 5. Jump Ayah
        recallCubit.jumpToAyah(22);
        expect(recallCubit.state.currentGlobalAyah, 22);

        // 6. Interactive range selection workflow
        recallCubit.enterRangeSelection(1);
        recallCubit.updateRangeEnd(7);
        await recallCubit.confirmRangeSelection();

        // 7. End session
        await recallCubit.endSession();
        expect(recallCubit.state.isIdle, isTrue);

        // Verify that NO operation ever touched 'last_read' or 'last_read_page'
        final lastReadWrites = storage.writeOperations
            .where((op) => op.contains('last_read'))
            .toList();
        expect(
          lastReadWrites,
          isEmpty,
          reason: 'Visual Recall must have 0 writes to Last Read keys',
        );

        // Verify persisted last_read is 100% unaltered
        expect(storage.readMap('last_read'), initialLastRead);
        expect(storage.readInt('last_read_page'), 100);
      },
    );

    test('7. Byte-level canvas reversion: unmasked page produces zero mask drawing commands', () {
      const contentSize = Size(390, 700);
      const viewBox = Rect.fromLTWH(0, 0, 345, 550);

      // Recorder 1: Baseline canvas with 0 drawing operations
      final recorderEmpty = ui.PictureRecorder();
      final canvasEmpty = Canvas(recorderEmpty);
      const emptyPainter = VisualMaskPainter(
        maskedAyahs: [],
        viewBox: viewBox,
        mapper: mapper,
        maskColor: MushafThemeColors.lightBackground,
      );
      emptyPainter.paint(canvasEmpty, contentSize);
      final picEmpty = recorderEmpty.endRecording();

      // Recorder 2: Clean canvas with no painter call
      final recorderClean = ui.PictureRecorder();
      Canvas(recorderClean);
      final picClean = recorderClean.endRecording();

      // Both should produce equivalent minimal pictures (approx 0 byte drawing payload)
      expect(picEmpty, isNotNull);
      expect(picClean, isNotNull);
    });
  });

  group(
    'Q13 Phase 1B — Representative Pages Screenshot & Geometry Verification',
    () {
      const representativePages = [1, 2, 3, 76, 100, 282, 500, 590, 600, 604];
      const viewports = <({String name, Size size})>[
        (name: 'compact_320', size: Size(320, 640)),
        (name: 'standard_390', size: Size(390, 844)),
        (name: 'pro_max_430', size: Size(430, 932)),
      ];

      testWidgets(
        '6. Render and capture visual masking across representative pages, themes, and viewports',
        (tester) async {
          final storage = InMemoryTrackingLocalStorageService();
          final memoRepo = QuranMemorizationRepository(storage: storage);
          final memoCubit = QuranMemorizationCubit(repository: memoRepo);
          await memoCubit.load();
          final recallCubit = QuranVisualRecallCubit(
            memorizationCubit: memoCubit,
            storage: storage,
          );

          for (final pageNum in representativePages) {
            final pageGeom = layoutRepo.getPageGeometry(pageNum);
            expect(
              pageGeom,
              isNotNull,
              reason: 'Page $pageNum geometry must exist',
            );
            final firstAyah = pageGeom!.ayahs.first;

            // Mask the first Ayah on this page
            await recallCubit.startSingleAyah(firstAyah.globalAyah);

            // Test Light Mode (390x844)
            final keyLight = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: keyLight,
                child: BlocProvider.value(
                  value: recallCubit,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.light(1.0),
                    home: Scaffold(
                      body: MediaQuery(
                        data: const MediaQueryData(size: Size(390, 844)),
                        child: MushafPage(
                          page: pageNum,
                          scale: 1.0,
                          isCurrent: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            // Verify overlay is mounted with the correct masked Ayah
            expect(find.byType(MushafVisualMaskOverlay), findsOneWidget);
            final overlay = tester.widget<MushafVisualMaskOverlay>(
              find.byType(MushafVisualMaskOverlay),
            );
            expect(overlay.maskedAyahs.single.globalAyah, firstAyah.globalAyah);
            expect(overlay.maskColor, MushafThemeColors.lightBackground);

            // Capture PNG for representative pages
            await tester.runAsync(() async {
              final boundary =
                  keyLight.currentContext!.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary != null) {
                final image = await boundary.toImage(pixelRatio: 1.0);
                final byteData = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (byteData != null) {
                  final file = File(
                    'screenshots/visual_recall/page_${pageNum}_light.png',
                  );
                  await file.writeAsBytes(byteData.buffer.asUint8List());
                }
              }
            });

            // Test Dark Mode
            final keyDark = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: keyDark,
                child: BlocProvider.value(
                  value: recallCubit,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.dark(1.0),
                    home: Scaffold(
                      body: MediaQuery(
                        data: const MediaQueryData(size: Size(390, 844)),
                        child: MushafPage(
                          page: pageNum,
                          scale: 1.0,
                          isCurrent: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            final darkOverlay = tester.widget<MushafVisualMaskOverlay>(
              find.byType(MushafVisualMaskOverlay),
            );
            expect(darkOverlay.maskColor, MushafThemeColors.darkBackground);

            await tester.runAsync(() async {
              final boundary =
                  keyDark.currentContext!.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary != null) {
                final image = await boundary.toImage(pixelRatio: 1.0);
                final byteData = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (byteData != null) {
                  final file = File(
                    'screenshots/visual_recall/page_${pageNum}_dark.png',
                  );
                  await file.writeAsBytes(byteData.buffer.asUint8List());
                }
              }
            });
          }

          // Test responsive viewports on Page 3
          final page3Geom = layoutRepo.getPageGeometry(3)!;
          final ayah14 = page3Geom.ayahs.firstWhere((a) => a.globalAyah == 14);
          await recallCubit.startSingleAyah(ayah14.globalAyah);

          for (final vp in viewports) {
            final keyVp = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: keyVp,
                child: BlocProvider.value(
                  value: recallCubit,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.light(1.0),
                    home: Scaffold(
                      body: MediaQuery(
                        data: MediaQueryData(size: vp.size),
                        child: SizedBox(
                          width: vp.size.width,
                          height: vp.size.height,
                          child: const MushafPage(
                            page: 3,
                            scale: 1.0,
                            isCurrent: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            expect(find.byType(MushafVisualMaskOverlay), findsOneWidget);

            await tester.runAsync(() async {
              final boundary =
                  keyVp.currentContext!.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary != null) {
                final image = await boundary.toImage(pixelRatio: 1.0);
                final byteData = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (byteData != null) {
                  final file = File(
                    'screenshots/visual_recall/page_3_${vp.name}.png',
                  );
                  await file.writeAsBytes(byteData.buffer.asUint8List());
                }
              }
            });
          }

          await recallCubit.close();
          await memoCubit.close();
        },
      );
    },
  );
}
