import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/widgets/mishkat_widgets.dart';
import 'package:mishkat_app/features/prayer_times/domain/models/prayer_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final cairoFiles = [
      'assets/fonts/Cairo-Regular.ttf',
      'assets/fonts/Cairo-SemiBold.ttf',
      'assets/fonts/Cairo-Bold.ttf',
      'assets/fonts/Cairo-Light.ttf',
      'assets/fonts/Cairo-Black.ttf',
    ];
    final cairoLoader = FontLoader('Cairo');
    for (final path in cairoFiles) {
      final file = File(path);
      if (file.existsSync()) {
        cairoLoader.addFont(
          Future.value(ByteData.view(file.readAsBytesSync().buffer)),
        );
      }
    }
    await cairoLoader.load();
  });

  group('AppTheme Global Cairo Typography Scale Tests', () {
    test(
      'Font family and fallbacks are Cairo in both light and dark themes',
      () {
        final light = AppTheme.light();
        final dark = AppTheme.dark();

        expect(light.textTheme.bodyMedium?.fontFamily, 'Cairo');
        expect(dark.textTheme.bodyMedium?.fontFamily, 'Cairo');
        expect(light.textTheme.displayLarge?.fontFamily, 'Cairo');
        expect(dark.textTheme.displayLarge?.fontFamily, 'Cairo');
      },
    );

    test('Exact semantic scale values in light theme', () {
      final theme = AppTheme.light();
      final t = theme.textTheme;

      expect(t.displayLarge?.fontSize, 28.0);
      expect(t.displayLarge?.fontWeight, FontWeight.w800);

      expect(t.displayMedium?.fontSize, 24.0);
      expect(t.displayMedium?.fontWeight, FontWeight.w800);

      expect(t.displaySmall?.fontSize, 22.0);
      expect(t.displaySmall?.fontWeight, FontWeight.w700);

      expect(t.headlineLarge?.fontSize, 22.0);
      expect(t.headlineLarge?.fontWeight, FontWeight.w800);

      expect(t.headlineMedium?.fontSize, 20.0);
      expect(t.headlineMedium?.fontWeight, FontWeight.w700);

      expect(t.headlineSmall?.fontSize, 18.0);
      expect(t.headlineSmall?.fontWeight, FontWeight.w700);

      expect(t.titleLarge?.fontSize, 16.5);
      expect(t.titleLarge?.fontWeight, FontWeight.w700);

      expect(t.titleMedium?.fontSize, 15.0);
      expect(t.titleMedium?.fontWeight, FontWeight.w600);

      expect(t.titleSmall?.fontSize, 13.5);
      expect(t.titleSmall?.fontWeight, FontWeight.w600);

      expect(t.bodyLarge?.fontSize, 15.0);
      expect(t.bodyLarge?.fontWeight, FontWeight.w500);

      expect(t.bodyMedium?.fontSize, 13.5);
      expect(t.bodyMedium?.fontWeight, FontWeight.w400);

      expect(t.bodySmall?.fontSize, 12.0);
      expect(t.bodySmall?.fontWeight, FontWeight.w400);

      expect(t.labelLarge?.fontSize, 13.5);
      expect(t.labelLarge?.fontWeight, FontWeight.w700);

      expect(t.labelMedium?.fontSize, 12.0);
      expect(t.labelMedium?.fontWeight, FontWeight.w600);

      expect(t.labelSmall?.fontSize, 11.0);
    });

    test('Exact semantic scale values in dark theme', () {
      final theme = AppTheme.dark();
      final t = theme.textTheme;

      expect(t.displayLarge?.fontSize, 28.0);
      expect(t.headlineMedium?.fontSize, 20.0);
      expect(t.titleLarge?.fontSize, 16.5);
      expect(t.bodyLarge?.fontSize, 15.0);
      expect(t.bodyMedium?.fontSize, 13.5);
      expect(t.bodySmall?.fontSize, 12.0);
      expect(t.labelLarge?.fontSize, 13.5);
    });

    test('Custom scale parameter scales all text styles proportionately', () {
      final themeScaled = AppTheme.light(1.25);
      final t = themeScaled.textTheme;

      expect(t.displayLarge?.fontSize, closeTo(28.0 * 1.25, 0.01));
      expect(t.headlineMedium?.fontSize, closeTo(20.0 * 1.25, 0.01));
      expect(t.titleLarge?.fontSize, closeTo(16.5 * 1.25, 0.01));
      expect(t.bodyMedium?.fontSize, closeTo(13.5 * 1.25, 0.01));
    });
  });

  group('Responsive Layout & Text Overflow Verification', () {
    final sampleSchedule = PrayerSchedule(
      next: PrayerMoment(
        key: 'dhuhr',
        name: 'الظهر',
        at: DateTime(2026, 10, 11, 12, 18),
      ),
      current: PrayerMoment(
        key: 'shuruq',
        name: 'الشروق',
        at: DateTime(2026, 10, 11, 6, 21),
      ),
      today: PrayerTimes(
        values: {
          'fajr': DateTime(2026, 10, 11, 5, 4),
          'shuruq': DateTime(2026, 10, 11, 6, 21),
          'dhuhr': DateTime(2026, 10, 11, 12, 18),
          'asr': DateTime(2026, 10, 11, 15, 39),
          'maghrib': DateTime(2026, 10, 11, 18, 14),
          'isha': DateTime(2026, 10, 11, 19, 31),
        },
        methodName: 'أم القرى',
        methodKey: 'makkah',
      ),
      moments: [
        PrayerMoment(
          key: 'fajr',
          name: 'الفجر',
          at: DateTime(2026, 10, 11, 5, 4),
        ),
        PrayerMoment(
          key: 'shuruq',
          name: 'الشروق',
          at: DateTime(2026, 10, 11, 6, 21),
          noAdhan: true,
        ),
        PrayerMoment(
          key: 'dhuhr',
          name: 'الظهر',
          at: DateTime(2026, 10, 11, 12, 18),
        ),
        PrayerMoment(
          key: 'asr',
          name: 'العصر',
          at: DateTime(2026, 10, 11, 15, 39),
        ),
        PrayerMoment(
          key: 'maghrib',
          name: 'المغرب',
          at: DateTime(2026, 10, 11, 18, 14),
        ),
        PrayerMoment(
          key: 'isha',
          name: 'العشاء',
          at: DateTime(2026, 10, 11, 19, 31),
        ),
      ],
    );

    const widths = [320.0, 360.0, 390.0, 430.0];

    for (final width in widths) {
      testWidgets(
        'MishkatPrayerSchedule renders with 0 overflow at width: ${width}px',
        (tester) async {
          tester.view.physicalSize = Size(width * 2, 800 * 2);
          tester.view.devicePixelRatio = 2.0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: MishkatPrayerSchedule(
                    schedule: sampleSchedule,
                    cityName: 'الرياض',
                    onLocationTap: () {},
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
        },
      );

      testWidgets(
        'Mishkat widgets render with 0 overflow at width: ${width}px with accessibility scale 1.25',
        (tester) async {
          tester.view.physicalSize = Size(width * 2, 800 * 2);
          tester.view.devicePixelRatio = 2.0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.25)),
                  child: child!,
                );
              },
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const MishkatSectionHeader(
                          title: 'القسم الرئيسي للقرآن الكريم',
                          trailing: Text('عرض الكل'),
                        ),
                        const SizedBox(height: 12),
                        MishkatShortcutTile(
                          icon: Icons.menu_book_rounded,
                          title: 'المصحف الشريف بالقراءات',
                          subtitle: 'متابعة التلاوة والحفظ اليومي',
                          trailing: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 14,
                          ),
                          onTap: () {},
                        ),
                        const SizedBox(height: 12),
                        MishkatPrimaryAction(
                          label: 'متابعة القراءة من سورة البقرة',
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: () {},
                        ),
                        const SizedBox(height: 12),
                        MishkatSecondaryAction(
                          label: 'جدول المراجعة والتكرار',
                          icon: const Icon(Icons.repeat_rounded),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
        },
      );
    }
  });
}
