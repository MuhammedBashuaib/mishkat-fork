// ignore_for_file: avoid_print
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/presentation/services/mushaf_coordinate_mapper.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_visual_recall_prototype.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository layoutRepo;
  const mapper = MushafCoordinateMapper();

  setUpAll(() async {
    layoutRepo = MushafLayoutRepository();
    await layoutRepo.load();
  });

  group('Q13 Phase 1 — Performance Profiling & Frame Timing Benchmark', () {
    test('1. Isolated VisualMaskPainter.paint execution time benchmark (1,000 iterations)', () {
      const contentSize = Size(390, 700);
      const maskColor = Color(0xFFF6F1E8);

      // Scenarios to benchmark
      final scenarios =
          <({String name, int page, int globalAyah, MaskBoundaryMode mode})>[
            (
              name: 'Rect Single-Line (Page 1, Ayah 2)',
              page: 1,
              globalAyah: 2,
              mode: MaskBoundaryMode.raw,
            ),
            (
              name: 'Polygon 8-Vertex Path (Page 2, Ayah 9)',
              page: 2,
              globalAyah: 9,
              mode: MaskBoundaryMode.raw,
            ),
            (
              name: 'Rect Standard Multi-Line (Page 3, Ayah 14)',
              page: 3,
              globalAyah: 14,
              mode: MaskBoundaryMode.raw,
            ),
            (
              name: 'Rect Long 8-Line Ayah (Page 76, Ayah 488)',
              page: 76,
              globalAyah: 488,
              mode: MaskBoundaryMode.raw,
            ),
            (
              name: 'Rect Micro-Inset Mode (Page 3, Ayah 14)',
              page: 3,
              globalAyah: 14,
              mode: MaskBoundaryMode.microInset,
            ),
            (
              name: 'Rect Rounded Corners Mode (Page 3, Ayah 14)',
              page: 3,
              globalAyah: 14,
              mode: MaskBoundaryMode.rounded,
            ),
          ];

      final results = <String, Map<String, double>>{};

      for (final sc in scenarios) {
        final pageGeom = layoutRepo.getPageGeometry(sc.page)!;
        final ayahBounds = layoutRepo.getAyah(sc.globalAyah)!;

        final painter = VisualMaskPainter(
          maskedAyah: ayahBounds,
          viewBox: pageGeom.viewBox,
          mapper: mapper,
          maskColor: maskColor,
          boundaryMode: sc.mode,
        );

        // Warm up JIT
        for (var i = 0; i < 50; i++) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          painter.paint(canvas, contentSize);
          recorder.endRecording();
        }

        // Measure 1,000 iterations
        final timingsMicros = <int>[];
        for (var i = 0; i < 1000; i++) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          final sw = Stopwatch()..start();
          painter.paint(canvas, contentSize);
          sw.stop();
          timingsMicros.add(sw.elapsedMicroseconds);
          recorder.endRecording();
        }

        timingsMicros.sort();
        final median =
            timingsMicros[(timingsMicros.length * 0.5).toInt()] / 1000.0;
        final p90 =
            timingsMicros[(timingsMicros.length * 0.9).toInt()] / 1000.0;
        final p95 =
            timingsMicros[(timingsMicros.length * 0.95).toInt()] / 1000.0;
        final p99 =
            timingsMicros[(timingsMicros.length * 0.99).toInt()] / 1000.0;
        final maxVal = timingsMicros.last / 1000.0;

        results[sc.name] = {
          'median': median,
          'p90': p90,
          'p95': p95,
          'p99': p99,
          'max': maxVal,
        };

        // Assert isolated painter completes well under the 2.0 ms SLA budget
        expect(
          median,
          lessThan(0.5),
          reason: '${sc.name} median paint must be < 0.5 ms',
        );
        expect(
          p95,
          lessThan(1.0),
          reason: '${sc.name} p95 paint must be < 1.0 ms',
        );
      }

      print('=== Isolated VisualMaskPainter Paint Performance (ms) ===');
      for (final entry in results.entries) {
        final m = entry.value;
        print(
          '${entry.key}: median=${m['median']}ms, p90=${m['p90']}ms, p95=${m['p95']}ms, p99=${m['p99']}ms, max=${m['max']}ms',
        );
      }
    });

    testWidgets('2. Realistic Interaction Frame Timing & Jank Profile', (
      tester,
    ) async {
      final ayah14 = layoutRepo.getAyah(14)!;
      const testSize = Size(390, 700);

      tester.view.physicalSize = testSize * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: testSize.width,
            height: testSize.height,
            child: MushafVisualRecallPrototype(
              layoutRepository: layoutRepo,
              initialPage: 3,
              initialTargetGlobalAyah: ayah14.globalAyah,
              initialMasked: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<MushafVisualRecallPrototypeState>(
        find.byType(MushafVisualRecallPrototype),
      );

      // Simulate 120 interaction frames: Mask toggling, zoom steps, and theme toggling
      final frameDurationsMicros = <int>[];
      final totalFrames = 120;

      for (var f = 0; f < totalFrames; f++) {
        final sw = Stopwatch()..start();

        if (f % 10 == 0) {
          state.toggleMask();
        } else if (f % 20 == 5) {
          state.setZoom(1.5);
        } else if (f % 20 == 15) {
          state.setZoom(1.0);
        } else if (f % 30 == 0) {
          state.setThemeMode(f % 60 == 0 ? ThemeMode.dark : ThemeMode.light);
        }

        await tester.pump(const Duration(milliseconds: 16));
        sw.stop();
        frameDurationsMicros.add(sw.elapsedMicroseconds);
      }

      frameDurationsMicros.sort();
      final medianMs =
          frameDurationsMicros[(totalFrames * 0.5).toInt()] / 1000.0;
      final p90Ms = frameDurationsMicros[(totalFrames * 0.9).toInt()] / 1000.0;
      final p95Ms = frameDurationsMicros[(totalFrames * 0.95).toInt()] / 1000.0;
      final p99Ms = frameDurationsMicros[(totalFrames * 0.99).toInt()] / 1000.0;
      final maxMs = frameDurationsMicros.last / 1000.0;

      // Define standard refresh targets:
      // 60 Hz budget = 16.67 ms. Slow frame > 16.67 ms. Jank frame > 33.33 ms (missed 2+ frames).
      final slowFrames = frameDurationsMicros.where((m) => m > 16670).length;
      final jankFrames = frameDurationsMicros.where((m) => m > 33333).length;
      final slowPercent = (slowFrames / totalFrames) * 100.0;
      final jankPercent = (jankFrames / totalFrames) * 100.0;

      print('=== Interaction Frame Timing Profile ($totalFrames frames) ===');
      print('Median frame: ${medianMs.toStringAsFixed(2)} ms');
      print('p90 frame:    ${p90Ms.toStringAsFixed(2)} ms');
      print('p95 frame:    ${p95Ms.toStringAsFixed(2)} ms');
      print('p99 frame:    ${p99Ms.toStringAsFixed(2)} ms');
      print('Max frame:    ${maxMs.toStringAsFixed(2)} ms');
      print(
        'Slow frames (>16.67ms): $slowFrames (${slowPercent.toStringAsFixed(1)}%)',
      );
      print(
        'Jank frames (>33.33ms): $jankFrames (${jankPercent.toStringAsFixed(1)}%)',
      );

      // Assert interaction frame median is well within the 60 Hz budget (16.67 ms)
      expect(medianMs, lessThan(16.67));
    });
  });
}
