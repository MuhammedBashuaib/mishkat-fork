import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_surah_picker_sheet.dart';

const chapters = [
  QuranChapter(
    number: 1,
    name: 'الفاتحة',
    englishName: 'Al-Fatihah',
    revelationType: 'مكية',
    page: 1,
    ayahs: ['آية'],
    globalStart: 1,
  ),
  QuranChapter(
    number: 2,
    name: 'البقرة',
    englishName: 'Al-Baqarah',
    revelationType: 'مدنية',
    page: 2,
    ayahs: ['آية'],
    globalStart: 8,
  ),
  QuranChapter(
    number: 36,
    name: 'يس',
    englishName: 'Ya-Sin',
    revelationType: 'مكية',
    page: 440,
    ayahs: ['آية'],
    globalStart: 3706,
  ),
];

void main() {
  testWidgets('search, clear and select preserve the actual surah number', (
    tester,
  ) async {
    QuranChapter? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: QuranSurahPickerSheet(
              chapters: chapters,
              reciterName: 'مشاري العفاسي',
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, 'سورة الْبَقَرَة');
    await tester.pumpAndSettle();
    expect(find.text('سورة البقرة'), findsOneWidget);
    expect(find.text('سورة الفاتحة'), findsNothing);
    await tester.enterText(field, '٣٦');
    await tester.pumpAndSettle();
    await tester.tap(find.text('سورة يس'));
    expect(selected, same(chapters.last));
    await tester.enterText(field, 'لايوجداسم');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد سور مطابقة لبحثك'), findsOneWidget);
    await tester.tap(find.byTooltip('مسح البحث'));
    await tester.pumpAndSettle();
    expect(find.text('سورة الفاتحة'), findsOneWidget);
    expect(find.text('سورة البقرة'), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('search sheet remains usable with keyboard at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      viewInsets: EdgeInsets.only(bottom: size.height * .45),
                    ),
                    child: QuranSurahPickerSheet(
                      chapters: chapters,
                      reciterName: 'مشاري راشد العفاسي',
                      onSelected: (_) {},
                    ),
                  ),
                ),
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '٢');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('سورة البقرة'));
      expect(find.text('سورة البقرة'), findsOneWidget);
    });
  }
}
