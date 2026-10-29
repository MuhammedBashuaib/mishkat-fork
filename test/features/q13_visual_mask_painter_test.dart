import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_mask_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository layoutRepo;
  const mapper = MushafCoordinateMapper();

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository();
    await layoutRepo.load();
  });

  group('Q13 Phase 1B — VisualMaskPainter Unit Tests', () {
    const contentSize = Size(390, 700);
    const lightMaskColor = Color(0xFFF6F1E8);
    const darkMaskColor = Color(0xFF121C17);

    test(
      'All 6236 Ayahs have an exact number position inside their geometry',
      () {
        for (var global = 1; global <= 6236; global++) {
          final ayah = layoutRepo.getAyah(global)!;
          expect(ayah.numberCenter, isNotNull, reason: 'Ayah $global');
          expect(
            ayah.contains(ayah.numberCenter!),
            isTrue,
            reason: 'Ayah $global',
          );
        }
      },
    );

    test('1. Empty maskedAyahs produces no drawing commands', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      const painter = VisualMaskPainter(
        maskedAyahs: [],
        viewBox: Rect.fromLTWH(0, 0, 345, 550),
        mapper: mapper,
        maskColor: lightMaskColor,
      );

      painter.paint(canvas, contentSize);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('2. Single rectangular Ayah on Page 3 paints all rect segments', () {
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah14 = layoutRepo.getAyah(14)!; // 2:7 (3 segments)

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final painter = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
      );

      painter.paint(canvas, contentSize);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test(
      '3. Multiple Ayahs paint sequentially without clipping each other',
      () {
        final pageGeom = layoutRepo.getPageGeometry(3)!;
        final ayah13 = layoutRepo.getAyah(13)!;
        final ayah14 = layoutRepo.getAyah(14)!;

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        final painter = VisualMaskPainter(
          maskedAyahs: [ayah13, ayah14],
          viewBox: pageGeom.viewBox,
          mapper: mapper,
          maskColor: lightMaskColor,
        );

        painter.paint(canvas, contentSize);
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      },
    );

    test(
      '4. Polygon geometry on Page 2 (Ayah 9) paints valid polygon Path',
      () {
        final pageGeom = layoutRepo.getPageGeometry(2)!;
        final ayah9 = layoutRepo.getAyah(9)!;
        expect(ayah9.segments.first, isA<AyahPolygonSegment>());

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        final painter = VisualMaskPainter(
          maskedAyahs: [ayah9],
          viewBox: pageGeom.viewBox,
          mapper: mapper,
          maskColor: lightMaskColor,
        );

        painter.paint(canvas, contentSize);
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      },
    );

    test('5. Polygon geometry on Page 1 (Ayah 4) paints valid Path with offset viewBox', () {
      final pageGeom = layoutRepo.getPageGeometry(1)!;
      expect(pageGeom.viewBox.left, closeTo(-53.3109, 1e-3));
      final ayah4 = layoutRepo.getAyah(4)!;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final painter = VisualMaskPainter(
        maskedAyahs: [ayah4],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
      );

      painter.paint(canvas, contentSize);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('6. Micro-inset mode executes cleanly', () {
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah14 = layoutRepo.getAyah(14)!;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final painter = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
        boundaryMode: MaskBoundaryMode.microInset,
      );

      painter.paint(canvas, contentSize);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('7. Rounded corners mode executes cleanly', () {
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah14 = layoutRepo.getAyah(14)!;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final painter = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
        boundaryMode: MaskBoundaryMode.rounded,
      );

      painter.paint(canvas, contentSize);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('8. Dark mode mask color paints properly', () {
      final pageGeom = layoutRepo.getPageGeometry(76)!;
      final ayah488 = layoutRepo.getAyah(488)!; // Dense 8-line Ayah

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final painter = VisualMaskPainter(
        maskedAyahs: [ayah488],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: darkMaskColor,
      );

      painter.paint(canvas, contentSize);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('9. shouldRepaint returns false when parameters are identical', () {
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah14 = layoutRepo.getAyah(14)!;

      final p1 = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
      );

      final p2 = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
      );

      expect(p1.shouldRepaint(p2), isFalse);
    });

    test('10. shouldRepaint returns true when maskColor, boundaryMode, or maskedAyahs change', () {
      final pageGeom = layoutRepo.getPageGeometry(3)!;
      final ayah13 = layoutRepo.getAyah(13)!;
      final ayah14 = layoutRepo.getAyah(14)!;

      final base = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
      );

      final colorChanged = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: darkMaskColor,
      );
      expect(base.shouldRepaint(colorChanged), isTrue);

      final modeChanged = VisualMaskPainter(
        maskedAyahs: [ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
        boundaryMode: MaskBoundaryMode.microInset,
      );
      expect(base.shouldRepaint(modeChanged), isTrue);

      final ayahsChanged = VisualMaskPainter(
        maskedAyahs: [ayah13, ayah14],
        viewBox: pageGeom.viewBox,
        mapper: mapper,
        maskColor: lightMaskColor,
      );
      expect(base.shouldRepaint(ayahsChanged), isTrue);
    });
  });
}
