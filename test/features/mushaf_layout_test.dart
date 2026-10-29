import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MushafLayoutRepository repository;
  late MushafLayoutData layoutData;

  setUpAll(() async {
    repository = MushafLayoutRepository();
    layoutData = await repository.load();
  });

  group('MushafLayout - Integrity & Completeness', () {
    test('loads successfully and caches data', () {
      expect(repository.isLoaded, isTrue);
      expect(repository.data, isNotNull);
      expect(layoutData.version, 1);
      expect(layoutData.coordinateSystem, 'svg_viewbox');
    });

    test('exact counts match Madinah Mushaf specifications', () {
      expect(layoutData.totalPages, 604);
      expect(layoutData.totalAyahs, 6236);
      expect(layoutData.pages.length, 604);
      expect(layoutData.ayahIndex.length, 6236);

      var totalSegments = 0;
      var totalRects = 0;
      var totalPolys = 0;

      for (final page in layoutData.pages) {
        for (final ayah in page.ayahs) {
          totalSegments += ayah.segments.length;
          for (final seg in ayah.segments) {
            if (seg is AyahRectSegment) {
              totalRects++;
            } else if (seg is AyahPolygonSegment) {
              totalPolys++;
            }
          }
        }
      }

      expect(totalSegments, 11386);
      expect(totalRects, 11378);
      expect(totalPolys, 8);
    });

    test('globalAyah sequence is strictly contiguous from 1 to 6236', () {
      for (var i = 1; i <= 6236; i++) {
        final ayah = repository.getAyah(i);
        expect(ayah, isNotNull, reason: 'Missing globalAyah $i');
        expect(ayah!.globalAyah, i);
      }
    });

    test('page viewBox specifications are strictly preserved', () {
      // Pages 1 and 2 have ornamental offset viewBox
      final p1 = repository.getPageGeometry(1)!;
      final p2 = repository.getPageGeometry(2)!;
      expect(p1.viewBox.left, closeTo(-53.3109, 1e-3));
      expect(p1.viewBox.top, closeTo(-198.4777, 1e-3));
      expect(p1.viewBox.width, 345);
      expect(p1.viewBox.height, 550);

      expect(p2.viewBox.left, closeTo(-53.3109, 1e-3));
      expect(p2.viewBox.top, closeTo(-198.4777, 1e-3));
      expect(p2.viewBox.width, 345);
      expect(p2.viewBox.height, 550);

      // Pages 3 to 604 use standard [0, 0, 345, 550]
      for (var pageNum = 3; pageNum <= 604; pageNum++) {
        final pageGeom = repository.getPageGeometry(pageNum)!;
        expect(pageGeom.viewBox.left, 0.0);
        expect(pageGeom.viewBox.top, 0.0);
        expect(pageGeom.viewBox.width, 345.0);
        expect(pageGeom.viewBox.height, 550.0);
      }
    });
  });

  group('MushafLayout - Representative Pages Validation', () {
    test(
      'Page 1: Surah Al-Fatihah (7 Ayahs, exceptional polygon geometry)',
      () {
        final p1 = repository.getPageGeometry(1)!;
        expect(p1.page, 1);
        expect(p1.ayahs.length, 7);

        // First Ayah (1:1)
        final a1 = p1.ayahs.first;
        expect(a1.globalAyah, 1);
        expect(a1.surah, 1);
        expect(a1.ayah, 1);

        // Last Ayah of Al-Fatihah (1:7)
        final a7 = p1.ayahs.last;
        expect(a7.globalAyah, 7);
        expect(a7.surah, 1);
        expect(a7.ayah, 7);

        // Page 1 has polygon segments on ornamental verses (e.g. verse 4, 5, 6, 7)
        final hasPolys = p1.ayahs.any(
          (a) => a.segments.any((s) => s is AyahPolygonSegment),
        );
        expect(hasPolys, isTrue);
      },
    );

    test('Page 2: Start of Al-Baqarah (Ayahs 8..12)', () {
      final p2 = repository.getPageGeometry(2)!;
      expect(p2.page, 2);
      expect(p2.ayahs.length, 5);
      expect(p2.ayahs.first.globalAyah, 8);
      expect(p2.ayahs.first.surah, 2);
      expect(p2.ayahs.first.ayah, 1);
      expect(p2.ayahs.last.globalAyah, 12);
      expect(p2.ayahs.last.ayah, 5);
    });

    test('Page 3: First standard layout page (Ayahs 13..23 / 2:6..2:16)', () {
      final p3 = repository.getPageGeometry(3)!;
      expect(p3.page, 3);
      expect(p3.ayahs.first.globalAyah, 13);
      expect(p3.ayahs.first.surah, 2);
      expect(p3.ayahs.first.ayah, 6);
      expect(p3.ayahs.last.globalAyah, 23);
      expect(p3.ayahs.last.ayah, 16);
      // All segments on page 3 are rectangles
      for (final a in p3.ayahs) {
        expect(a.segments.every((s) => s is AyahRectSegment), isTrue);
      }
    });

    test('Page 604: Last page of the Mushaf (Al-Ikhlas, Al-Falaq, An-Nas)', () {
      final p604 = repository.getPageGeometry(604)!;
      expect(p604.page, 604);
      expect(p604.ayahs.last.globalAyah, 6236);
      expect(p604.ayahs.last.surah, 114);
      expect(p604.ayahs.last.ayah, 6);
    });

    test('Representative pages across Quran (10, 50, 100, 300, 500, 552)', () {
      const testPages = [10, 50, 100, 300, 500, 552];
      for (final pageNum in testPages) {
        final pageGeom = repository.getPageGeometry(pageNum);
        expect(pageGeom, isNotNull);
        expect(pageGeom!.page, pageNum);
        expect(pageGeom.ayahs, isNotEmpty);
        for (final ayah in pageGeom.ayahs) {
          expect(ayah.page, pageNum);
          expect(ayah.bounds.width, greaterThan(0));
          expect(ayah.bounds.height, greaterThan(0));
          expect(ayah.segments, isNotEmpty);
        }
      }
    });
  });

  group('MushafLayout - Representative Ayahs Validation', () {
    test('Ayah 1 (1:1 - Bismillah)', () {
      final a1 = repository.getAyah(1)!;
      expect(a1.globalAyah, 1);
      expect(a1.surah, 1);
      expect(a1.ayah, 1);
      expect(a1.page, 1);
      expect(repository.pageForAyah(1), 1);
    });

    test('Ayah 8 (2:1 - Alif Lam Meem)', () {
      final a8 = repository.getAyah(8)!;
      expect(a8.globalAyah, 8);
      expect(a8.surah, 2);
      expect(a8.ayah, 1);
      expect(a8.page, 2);
      expect(repository.pageForAyah(8), 2);
    });

    test('Ayah 6236 (114:6 - Min al-Jinnati wan-Nas)', () {
      final aLast = repository.getAyah(6236)!;
      expect(aLast.globalAyah, 6236);
      expect(aLast.surah, 114);
      expect(aLast.ayah, 6);
      expect(aLast.page, 604);
      expect(repository.pageForAyah(6236), 604);
    });
  });

  group('MushafLayout - Hit-Testing Functionality', () {
    test('hit-testing inside rect segments identifies the exact Ayah', () {
      // Test Ayah 13 on page 3 (first segment rect: [0, 0.75, 337.75, 41])
      final hitPoint = const Offset(150.0, 20.0);
      final hitAyah = repository.findAyahAt(3, hitPoint);
      expect(hitAyah, isNotNull);
      expect(hitAyah!.globalAyah, 13);
      expect(hitAyah.surah, 2);
      expect(hitAyah.ayah, 6);
    });

    test('hit-testing inside polygon segments on Page 1 identifies Ayah', () {
      // Ayah 4 on Page 1 (surah 1, ayah 4) has segment vertices:
      // (128.52, 76.22), (12.95, 76.22), (12.59, 103.24), (128.52, 103.24)
      final interiorPoint = const Offset(70.0, 88.0);
      final hitAyah = repository.findAyahAt(1, interiorPoint);
      expect(hitAyah, isNotNull);
      expect(hitAyah!.globalAyah, 4);
      expect(hitAyah.surah, 1);
      expect(hitAyah.ayah, 4);
    });

    test('hit-testing outside page viewBox returns null', () {
      final hitOutside = repository.findAyahAt(3, const Offset(500.0, 800.0));
      expect(hitOutside, isNull);

      final hitNegative = repository.findAyahAt(3, const Offset(-10.0, -10.0));
      expect(hitNegative, isNull);
    });

    test('hit-testing on non-existent page returns null', () {
      expect(repository.findAyahAt(0, const Offset(50, 50)), isNull);
      expect(repository.findAyahAt(605, const Offset(50, 50)), isNull);
    });
  });

  group('MushafLayout - 100% Round-Trip Completeness Across All 6,236 Ayahs', () {
    test('every single Ayah (1..6236) has valid geometry and is hit-testable', () {
      for (var g = 1; g <= 6236; g++) {
        final ayah = repository.getAyah(g)!;
        expect(ayah.page, inInclusiveRange(1, 604));
        expect(repository.pageForAyah(g), ayah.page);
        expect(ayah.segments, isNotEmpty);
        expect(ayah.bounds.width, greaterThan(0));
        expect(ayah.bounds.height, greaterThan(0));

        // Sample a guaranteed interior point of the Ayah
        final sample = ayah.samplePoint;

        // The Ayah must contain its samplePoint
        expect(
          ayah.contains(sample),
          isTrue,
          reason: 'Ayah $g failed to contain its samplePoint $sample',
        );

        // findAyahAt on the Ayah's page must hit this Ayah
        final hit = repository.findAyahAt(ayah.page, sample);
        expect(
          hit,
          isNotNull,
          reason:
              'findAyahAt failed for Ayah $g on page ${ayah.page} at $sample',
        );
        expect(
          hit!.globalAyah,
          g,
          reason:
              'findAyahAt returned wrong Ayah ${hit.globalAyah} instead of $g',
        );
      }
    });
  });

  group('MushafLayout - Performance Benchmark', () {
    test(
      'hit-testing performs at sub-millisecond speeds (< 0.05ms per query)',
      () {
        final stopwatch = Stopwatch()..start();
        const iterations = 5000;

        for (var i = 0; i < iterations; i++) {
          // Query random locations across various pages
          final pageNum = (i % 604) + 1;
          final x = (i * 37) % 300 + 20.0;
          final y = (i * 53) % 500 + 25.0;
          repository.findAyahAt(pageNum, Offset(x, y));
        }

        stopwatch.stop();
        final totalMicros = stopwatch.elapsedMicroseconds;
        final avgMicros = totalMicros / iterations;
        final avgMillis = avgMicros / 1000.0;

        // Benchmark assertion: average query time strictly under 0.05 ms (50 microseconds)
        expect(
          avgMillis,
          lessThan(0.05),
          reason: 'Hit test took $avgMillis ms per query (exceeded 0.05 ms)',
        );
      },
    );
  });
}
