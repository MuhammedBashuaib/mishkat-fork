// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_recall_prototype.dart';

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final value = _data[key];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final value = _data[key];
    return value is List ? List<dynamic>.from(value) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final value = _data[key];
    return value is num ? value.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _data[key] = value;
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _data[key] = value;
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository layoutRepo;
  late QuranRepository quranRepo;
  const mapper = MushafCoordinateMapper();

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository();
    await layoutRepo.load();
    quranRepo = QuranRepository();
    await quranRepo.load();

    final dir = Directory('screenshots/q13_prototype');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  });

  group('Q13 Phase 0 — 1. Geometry & Coordinate Mapping Unit Tests', () {
    test(
      'Standard page viewBox (345x550) with EdgeInsets.zero matches SVG 1:1',
      () {
        const viewBox = Rect.fromLTWH(0, 0, 345, 550);
        const contentSize = Size(390, 700);

        final destRect = mapper.getSvgDestinationRect(
          contentSize: contentSize,
          viewBox: viewBox,
          padding: EdgeInsets.zero,
        );

        // Width constrained: aspect ratio = 345 / 550 = 0.62727
        expect(destRect.width, closeTo(390.0, 1e-2));
        expect(destRect.height, closeTo(390.0 * (550 / 345), 1e-2));
        expect(destRect.left, 0.0);
        expect(destRect.top, closeTo((700.0 - (390.0 * 550 / 345)) / 2, 1e-2));
      },
    );

    test('Page 1 offset viewBox (-53.3109, -198.4777, 345, 550) maintains aspect ratio', () {
      const viewBox = Rect.fromLTWH(-53.3109, -198.4777, 345, 550);
      const contentSize = Size(390, 700);

      final destRect = mapper.getSvgDestinationRect(
        contentSize: contentSize,
        viewBox: viewBox,
        padding: EdgeInsets.zero,
      );

      expect(destRect.width, closeTo(390.0, 1e-2));
      expect(destRect.height, closeTo(390.0 * (550 / 345), 1e-2));
      expect(destRect.left, 0.0);
    });

    test('AyahPolygonSegment on Page 2 converts to valid local Path', () {
      final pageGeom = layoutRepo.getPageGeometry(2)!;
      final ayah9 = layoutRepo.getAyah(9)!; // 2:2
      expect(ayah9.segments.first, isA<AyahPolygonSegment>());

      final poly = ayah9.segments.first as AyahPolygonSegment;
      const contentSize = Size(390, 700);

      final localPath = mapper.viewBoxPathToLocal(
        points: poly.points,
        contentSize: contentSize,
        viewBox: pageGeom.viewBox,
        padding: EdgeInsets.zero,
      );

      final bounds = localPath.getBounds();
      expect(bounds.width, greaterThan(10));
      expect(bounds.height, greaterThan(10));
      expect(bounds.left, greaterThanOrEqualTo(0));
    });

    test('AyahRectSegment on Page 3 maps exact line corridor without negative values', () {
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah14 = layoutRepo.getAyah(14)!; // 2:7
      expect(ayah14.segments.first, isA<AyahRectSegment>());

      final rectSeg = ayah14.segments.first as AyahRectSegment;
      const contentSize = Size(390, 700);

      final localRect = mapper.viewBoxRectToLocal(
        viewBoxRect: rectSeg.rect,
        contentSize: contentSize,
        viewBox: pageGeom.viewBox,
        padding: EdgeInsets.zero,
      );

      expect(localRect.left, greaterThanOrEqualTo(0));
      expect(localRect.right, lessThanOrEqualTo(contentSize.width));
      expect(localRect.height, greaterThan(10));
    });

    test('Missing / invalid page geometry returns null and does not throw', () {
      expect(layoutRepo.getPageGeometry(0), isNull);
      expect(layoutRepo.getPageGeometry(605), isNull);
      expect(layoutRepo.getAyah(0), isNull);
      expect(layoutRepo.getAyah(9999), isNull);
    });
  });

  group('Q13 Phase 0 — 2. Last-Read Safety & Isolation Tests', () {
    testWidgets(
      'Navigating prototype across validation pages never alters Last Read',
      (tester) async {
        final storage = InMemoryLocalStorageService();
        final quranCubit = QuranCubit(
          repository: quranRepo,
          storage: storage,
          audio: QuranAudioService(),
          reciter: 'ar.alafasy',
          fontSize: 32,
        );
        await quranCubit.load();

        // Record baseline initial state
        final initialLastRead = quranCubit.state.lastRead;
        final initialPage = quranCubit.state.currentPage;

        // Pump the isolated prototype (which does not depend on QuranCubit for navigation)
        await tester.pumpWidget(
          MaterialApp(
            home: MushafVisualRecallPrototype(
              layoutRepository: layoutRepo,
              initialPage: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<MushafVisualRecallPrototypeState>(
          find.byType(MushafVisualRecallPrototype),
        );

        // Navigate to all ten validation pages
        const validationPages = [1, 2, 3, 76, 100, 282, 500, 590, 600, 604];
        for (final p in validationPages) {
          state.setPage(p);
          state.toggleMask();
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // Verify that QuranCubit state and storage were completely untouched
        expect(quranCubit.state.lastRead, equals(initialLastRead));
        expect(quranCubit.state.currentPage, equals(initialPage));

        final storedLastRead = storage.readMap('lastRead');
        expect(
          storedLastRead.isEmpty || storedLastRead == initialLastRead?.toJson(),
          isTrue,
        );

        quranCubit.close();
      },
    );
  });

  group('Q13 Phase 0 — 3. Neighbor Isolation & Reveal Tests', () {
    testWidgets(
      'Target Ayah mask toggles while neighbor Ayah remains independently configured',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MushafVisualRecallPrototype(
              layoutRepository: layoutRepo,
              initialPage: 3,
              initialTargetGlobalAyah: 13,
              initialNeighborGlobalAyah: 14,
              initialMasked: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<MushafVisualRecallPrototypeState>(
          find.byType(MushafVisualRecallPrototype),
        );

        // Verify initial masked state
        final painterFinder = find.byType(CustomPaint);
        expect(painterFinder, findsWidgets);

        CustomPaint customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(MushafVisualRecallPrototype),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is VisualMaskPainter,
            ),
          ),
        );
        var painter = customPaint.painter as VisualMaskPainter;
        expect(painter.maskedAyah, isNotNull);
        expect(painter.maskedAyah!.globalAyah, 13);
        expect(painter.neighborAyah, isNotNull);
        expect(painter.neighborAyah!.globalAyah, 14);

        // Toggle reveal
        state.toggleMask();
        await tester.pump();

        customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(MushafVisualRecallPrototype),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is VisualMaskPainter,
            ),
          ),
        );
        painter = customPaint.painter as VisualMaskPainter;
        expect(
          painter.maskedAyah,
          isNull,
          reason: 'Target Ayah must be completely revealed',
        );
        expect(
          painter.neighborAyah!.globalAyah,
          14,
          reason: 'Neighbor Ayah remains intact',
        );
      },
    );
  });

  group(
    'Q13 Phase 0 — 4. Visual Validation Matrix (Ten Representative Pages)',
    () {
      Future<void> capturePrototypeScreenshot({
        required WidgetTester tester,
        required String filename,
        required int page,
        required int targetGlobalAyah,
        int? neighborGlobalAyah,
        bool isMasked = true,
        ThemeMode themeMode = ThemeMode.light,
        double zoom = 1.0,
        Size size = const Size(390, 700),
        MaskBoundaryMode boundaryMode = MaskBoundaryMode.raw,
      }) async {
        final key = GlobalKey();
        tester.view.physicalSize = size * 2.0;
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: SizedBox(
                width: size.width,
                height: size.height,
                child: MushafVisualRecallPrototype(
                  key: ValueKey('proto-p$page-m$isMasked-z$zoom-$filename'),
                  layoutRepository: layoutRepo,
                  initialPage: page,
                  initialTargetGlobalAyah: targetGlobalAyah,
                  initialNeighborGlobalAyah: neighborGlobalAyah,
                  initialMasked: isMasked,
                  initialThemeMode: themeMode,
                  initialBoundaryMode: boundaryMode,
                  initialZoom: zoom,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.0);
          final byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final pngBytes = byteData!.buffer.asUint8List();

          final file = File('screenshots/q13_prototype/$filename');
          file.writeAsBytesSync(pngBytes);
          print('Captured $filename (${pngBytes.length} bytes)');
        });
      }

      // 10 validation targets definitions
      final validationTargets =
          <({int page, int targetGlobal, int neighborGlobal, String label})>[
            (
              page: 1,
              targetGlobal: 2,
              neighborGlobal: 3,
              label: 'Al-Fatihah 1:2',
            ),
            (
              page: 2,
              targetGlobal: 9,
              neighborGlobal: 10,
              label: 'Al-Baqarah 2:2',
            ),
            (
              page: 3,
              targetGlobal: 14,
              neighborGlobal: 15,
              label: 'Al-Baqarah 2:7',
            ),
            (
              page: 76,
              targetGlobal: 488,
              neighborGlobal: 489,
              label: 'Ali Imran 3:195',
            ),
            (
              page: 100,
              targetGlobal: 628,
              neighborGlobal: 629,
              label: 'An-Nisa 4:135',
            ),
            (
              page: 282,
              targetGlobal: 2030,
              neighborGlobal: 2031,
              label: 'Al-Isra 17:1',
            ),
            (
              page: 500,
              targetGlobal: 4487,
              neighborGlobal: 4488,
              label: 'Al-Jathiyah 45:14',
            ),
            (
              page: 590,
              targetGlobal: 5910,
              neighborGlobal: 5911,
              label: 'Al-Buruj 85:1',
            ),
            (
              page: 600,
              targetGlobal: 6158,
              neighborGlobal: 6159,
              label: 'Al-Qariah 101:1',
            ),
            (
              page: 604,
              targetGlobal: 6222,
              neighborGlobal: 6223,
              label: 'Al-Ikhlas 112:1',
            ),
          ];

      testWidgets(
        'Generate comprehensive Visual Validation Matrix for all 10 pages',
        (tester) async {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          for (final t in validationTargets) {
            final p = t.page;

            // 1. Original page with no mask
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_01_original.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: false,
            );

            // 2. Target Ayah fully masked (Raw)
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_02_masked_raw.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              boundaryMode: MaskBoundaryMode.raw,
            );

            // 3. Target Ayah fully masked (Micro-inset variant)
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_03_masked_inset.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              boundaryMode: MaskBoundaryMode.microInset,
            );

            // 4. Target Ayah revealed again
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_04_revealed.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: false,
            );

            // 5. Mask alignment at 1.5x zoom
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_05_zoom1_5.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              zoom: 1.5,
            );

            // 6. Mask alignment at 2.0x zoom
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_06_zoom2_0.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              zoom: 2.0,
            );

            // 7. Dark Theme
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_07_dark.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              themeMode: ThemeMode.dark,
            );

            // 8. Narrow Viewport (Compact phone 320x640)
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_08_narrow.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              size: const Size(320, 640),
            );

            // 9. Large Viewport (Large phone 430x932)
            await capturePrototypeScreenshot(
              tester: tester,
              filename: 'p${p.toString().padLeft(3, '0')}_09_large.png',
              page: p,
              targetGlobalAyah: t.targetGlobal,
              neighborGlobalAyah: t.neighborGlobal,
              isMasked: true,
              size: const Size(430, 932),
            );
          }

          print('All visual validation screenshots generated successfully.');
        },
      );
    },
  );
}
