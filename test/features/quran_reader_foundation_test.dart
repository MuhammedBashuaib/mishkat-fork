import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_reader_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(MushafLayoutRepository.instance.load);

  group('Quran Reader Foundation & Integrity Tests', () {
    test('604 SVG Mushaf assets integrity', () {
      final dir = Directory('assets/mushaf/pages');
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'assets/mushaf/pages must exist',
      );

      final files = dir.listSync().whereType<File>().toList();
      expect(files.length, 604, reason: 'Must contain exactly 604 SVG files');

      for (var page = 1; page <= 604; page++) {
        final path =
            'assets/mushaf/pages/${page.toString().padLeft(3, '0')}.svg';
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'Page $path must exist');
        expect(
          file.lengthSync(),
          greaterThan(10000),
          reason: 'Page $path must not be empty',
        );
      }
    });

    test(
      'Quran dataset completeness: 114 Surahs, 6236 Ayahs, 30 Juz, 604 Pages',
      () async {
        final data = await QuranRepository().load();
        expect(data.chapters.length, 114);
        expect(data.juz.length, 30);
        expect(data.pages.length, 604);

        final totalAyahs = data.chapters.fold<int>(
          0,
          (sum, c) => sum + c.ayahs.length,
        );
        expect(totalAyahs, 6236);

        // Verify first and last points
        expect(data.page(1).first.global, 1);
        expect(data.page(604).last.global, 6236);
      },
    );

    test('Persistence compatibility: currentPage, lastRead, bookmarks', () {
      final point = const QuranPoint(surah: 18, ayah: 1, global: 2141);
      final pointJson = point.toJson();
      expect(pointJson, {'s': 18, 'a': 1, 'g': 2141});

      final restoredPoint = QuranPoint.fromJson(pointJson);
      expect(restoredPoint, point);

      final bookmark = QuranBookmark(
        page: 293,
        point: point,
        createdAt: DateTime(2026, 10, 4, 12, 0),
      );
      final bookmarkJson = bookmark.toJson();
      expect(bookmarkJson['page'], 293);
      expect(bookmarkJson['point'], {'s': 18, 'a': 1, 'g': 2141});

      final restoredBookmark = QuranBookmark.fromJson(bookmarkJson);
      expect(restoredBookmark.page, 293);
      expect(restoredBookmark.point, point);

      // Verify store JSON structure
      final storeData = <String, dynamic>{
        'currentPage': 293,
        'lastRead': point.toJson(),
        'bookmarks': [bookmark.toJson()],
      };
      final raw = jsonEncode(storeData);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      expect(decoded['currentPage'], 293);
      expect(
        QuranPoint.fromJson(decoded['lastRead'] as Map<String, dynamic>),
        point,
      );
      expect(
        (decoded['bookmarks'] as List)
            .map((e) => QuranBookmark.fromJson(e as Map<String, dynamic>))
            .first
            .page,
        293,
      );
    });

    test('MushafThemeColors definitions for Light and Dark modes', () {
      // Light Mode colors
      expect(MushafThemeColors.lightBackground, const Color(0xFFF6F1E8));
      expect(MushafThemeColors.lightInk, const Color(0xFF231F20));

      // Dark Mode colors
      expect(MushafThemeColors.darkBackground, const Color(0xFF121C17));
      expect(MushafThemeColors.darkInk, const Color(0xFFECE5D8));
    });

    test('Key sample pages exist and contain ayahPolygon layer (1, 2, 10, 50, 300, 604)', () {
      const samplePages = [1, 2, 10, 50, 300, 604];
      for (final p in samplePages) {
        final path = 'assets/mushaf/pages/${p.toString().padLeft(3, '0')}.svg';
        final content = File(path).readAsStringSync();
        expect(content.contains('<svg'), isTrue);
        expect(
          content.contains('class="ayahPolygon"'),
          isTrue,
          reason: 'Page $p must have ayahPolygon layer',
        );
      }
    });

    testWidgets(
      'Visual verification: render sample pages (1, 2, 10, 50, 300, 604) in Light and Dark mode',
      (tester) async {
        const samplePages = [1, 2, 10, 50, 300, 604];
        for (final p in samplePages) {
          // Test Light Mode
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.light(),
              home: Scaffold(
                body: Directionality(
                  textDirection: TextDirection.rtl,
                  child: MushafPage(page: p, scale: 1.0, isCurrent: true),
                ),
              ),
            ),
          );
          expect(find.byType(MushafPage), findsOneWidget);

          // Test Dark Mode
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              home: Scaffold(
                body: Directionality(
                  textDirection: TextDirection.rtl,
                  child: MushafPage(page: p, scale: 1.0, isCurrent: true),
                ),
              ),
            ),
          );
          expect(find.byType(MushafPage), findsOneWidget);
        }
      },
    );

    testWidgets(
      'Reader lens zooms and returns to fit without resizing the page viewport',
      (tester) async {
        Widget harness(double scale) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 700,
              child: MushafPage(page: 1, scale: scale, isCurrent: true),
            ),
          ),
        );

        await tester.pumpWidget(harness(1));
        await tester.pump();
        final viewportSize = tester.getSize(find.byType(InteractiveViewer));

        await tester.pumpWidget(harness(1.5));
        await tester.pump();
        final zoomed = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(
          zoomed.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1.5, .01),
        );
        expect(tester.getSize(find.byType(InteractiveViewer)), viewportSize);

        await tester.pumpWidget(harness(1));
        await tester.pump();
        final reduced = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(
          reduced.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1, .01),
        );
        expect(tester.getSize(find.byType(InteractiveViewer)), viewportSize);
      },
    );
  });
}
