import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/theme/quran_text_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<dynamic> surahs;

  setUpAll(() async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/data/quran.json'),
    ) as Map<String, dynamic>;
    surahs = data['surahs'] as List<dynamic>;
    await (FontLoader(
      'QpcHafs',
    )..addFont(rootBundle.load('assets/fonts/UthmanicHafs_V22.ttf'))).load();
    await (FontLoader(
      'AmiriQuran',
    )..addFont(rootBundle.load('assets/fonts/AmiriQuran-Regular.ttf'))).load();
  });

  for (final sample in [
    (name: 'connected letters and diacritics', surah: 1, ayah: 3, width: 360.0),
    (name: 'lam-alif and stacked Quran marks', surah: 1, ayah: 7, width: 240.0),
    (name: 'pause signs', surah: 2, ayah: 2, width: 240.0),
    (name: 'long verse on a narrow screen', surah: 2, ayah: 255, width: 180.0),
  ]) {
    testWidgets(
      '${sample.name} retains clean Arabic shaping under hostile UI typography',
      (tester) async {
        final chapter = surahs[sample.surah - 1] as Map<String, dynamic>;
        final source =
            (chapter['ayahs'] as List<dynamic>)[sample.ayah - 1] as String;
        const ink = Color(0xFF16241D);
        const fontSize = 26.0;
        const lineHeight = 1.85;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: sample.width,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 8,
                          wordSpacing: 20,
                          height: 0.8,
                          decoration: TextDecoration.underline,
                          fontFeatures: [
                            ui.FontFeature.disable('rlig'),
                            ui.FontFeature.disable('liga'),
                            ui.FontFeature.disable('calt'),
                          ],
                        ),
                        child: Text(
                          source,
                          key: const Key('quran-text'),
                          textScaler: TextScaler.noScaling,
                          style: QuranTextStyle.ayah(
                            color: ink,
                            fontSize: fontSize,
                            height: lineHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(const Key('quran-text')),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.text.toPlainText(), source);
        expect(paragraph.textDirection, TextDirection.rtl);
        expect(paragraph.text.style!.color, ink);
        expect(paragraph.text.style!.fontFeatures, isNull);
        expect(paragraph.text.style!.decoration, TextDecoration.none);

        // Compare the actual rendered widget with an independently constructed
        // Quran paragraph. This catches inherited spacing, synthetic weight,
        // disabled ligatures and changed wrapping, not just helper properties.
        final reference = TextPainter(
          text: TextSpan(
            text: source,
            style: const TextStyle(
              inherit: false,
              fontFamily: 'QpcHafs',
              fontFamilyFallback: ['AmiriQuran'],
              fontSize: fontSize,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.normal,
              letterSpacing: 0,
              wordSpacing: 0,
              height: lineHeight,
              color: ink,
            ),
          ),
          textDirection: TextDirection.rtl,
          textScaler: TextScaler.noScaling,
          locale: paragraph.locale,
        )..layout(minWidth: sample.width, maxWidth: sample.width);
        addTearDown(reference.dispose);

        expect(paragraph.size.width, closeTo(reference.width, 0.01));
        expect(paragraph.size.height, closeTo(reference.height, 0.01));
        expect(paragraph.didExceedMaxLines, isFalse);
        if (sample.ayah == 255) {
          expect(reference.computeLineMetrics().length, greaterThan(3));
        }

        // Check each complete word, retaining its combining marks. Whole-text
        // bounds alone could miss differences in individual Arabic joins.
        for (final word in RegExp(r'\S+').allMatches(source)) {
          final selection = TextSelection(
            baseOffset: word.start,
            extentOffset: word.end,
          );
          final actualBoxes = paragraph.getBoxesForSelection(selection);
          final expectedBoxes = reference.getBoxesForSelection(selection);
          expect(actualBoxes.length, expectedBoxes.length);
          for (var index = 0; index < expectedBoxes.length; index++) {
            final actual = actualBoxes[index];
            final expected = expectedBoxes[index];
            expect(actual.direction, expected.direction);
            expect(actual.left, closeTo(expected.left, 0.01));
            expect(actual.top, closeTo(expected.top, 0.01));
            expect(actual.right, closeTo(expected.right, 0.01));
            expect(actual.bottom, closeTo(expected.bottom, 0.01));
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
