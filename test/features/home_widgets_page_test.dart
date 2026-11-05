import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/widgets/mishkat_widgets.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/home/presentation/cubit/home_cubit.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/home_widgets/presentation/pages/home_widgets_page.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class _MemoryStorage implements LocalStorageService {
  final Map<String, dynamic> values = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from((values[key] as Map?) ?? {});

  @override
  List<dynamic> readList(String key) =>
      List<dynamic>.from((values[key] as List?) ?? []);

  @override
  int readInt(String key, [int fallback = 0]) =>
      (values[key] as num?)?.toInt() ?? fallback;

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    values[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    values[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}

class _GalleryWidgetService extends HomeWidgetService {
  _GalleryWidgetService() : super(adhkarRepository: AdhkarRepository());

  @override
  Future<bool> isInstalled(MishkatHomeWidget widget) async => false;

  bool pinSupported = false;
  int pinRequests = 0;

  @override
  Future<bool> isPinRequestSupported() async => pinSupported;

  @override
  Future<void> requestPin(MishkatHomeWidget widget) async {
    pinRequests++;
  }
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      loader.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'home widget gallery has no layout errors in ${brightness.name} mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 3200));
        debugDefaultTargetPlatformOverride = brightness == Brightness.dark
            ? TargetPlatform.iOS
            : TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final settingsStorage = _MemoryStorage();
        final settingsCubit = SettingsCubit(
          storage: settingsStorage,
          locationService: LocationService(),
          notifications: LocalNotificationService(),
        );
        final homeCubit = HomeCubit(const AppSettings());
        final khatmaCubit = KhatmaCubit(_MemoryStorage());
        final tasbihCubit = TasbihCubit(_MemoryStorage());
        await khatmaCubit.create(
          name: 'ختمتي',
          durationDays: 30,
          startPage: 42,
        );
        for (var index = 0; index < 24; index++) {
          await tasbihCubit.increment();
        }
        final widgetService = _GalleryWidgetService();

        await tester.pumpWidget(
          RepositoryProvider<HomeWidgetService>.value(
            value: widgetService,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
                BlocProvider<HomeCubit>.value(value: homeCubit),
                BlocProvider<KhatmaCubit>.value(value: khatmaCubit),
                BlocProvider<TasbihCubit>.value(value: tasbihCubit),
              ],
              child: MaterialApp(
                theme: brightness == Brightness.dark
                    ? AppTheme.dark()
                    : AppTheme.light(),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: RepaintBoundary(
                    key: ValueKey('gallery-preview'),
                    child: HomeWidgetsPage(),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.text('مواقيت الصلاة'), findsOneWidget);
        expect(find.text('بوصلة القبلة'), findsOneWidget);
        expect(find.text('ذِكر اليوم'), findsOneWidget);
        expect(find.text('الصلاة على شاشة القفل'), findsOneWidget);
        final actionCount =
            find.text('أضف للشاشة الرئيسية').evaluate().length +
            find.text('جارٍ التحقق…').evaluate().length;
        expect(actionCount, 5);
        expect(find.text('الورد اليومي'), findsOneWidget);
        expect(find.text('المسبحة'), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('tasbih-compact-preview'))),
          const Size(156, 156),
        );
        final wirdSize = tester.getSize(
          find.byKey(const ValueKey('wird-wide-preview')),
        );
        expect(wirdSize.height, 180);
        expect(
          wirdSize,
          tester.getSize(find.byKey(const ValueKey('prayer-wide-preview'))),
        );
        expect(find.byType(NextPrayerCountdown), findsNothing);
        homeCubit.updateSettings(
          const AppSettings(latitude: 21.4, longitude: 39.8),
        );
        await tester.pumpAndSettle();
        final countdown = tester.widget<NextPrayerCountdown>(
          find.byKey(const ValueKey('widget-prayer-countdown')),
        );
        expect(countdown.targetTime, homeCubit.state.schedule!.next.at);
        expect(
          tester
              .widget<NextPrayerCountdown>(
                find.byKey(const ValueKey('lock-screen-prayer-countdown')),
              )
              .targetTime,
          countdown.targetTime,
        );
        expect(
          find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$')),
          findsNWidgets(2),
        );
        homeCubit.updateSettings(const AppSettings());
        await tester.pumpAndSettle();
        expect(find.byType(NextPrayerCountdown), findsNothing);

        final systemChoice = find.byKey(const ValueKey('widget-theme-system'));
        expect(tester.widget<ChoiceChip>(systemChoice).selected, isTrue);
        final progress = find.byKey(const ValueKey('widget-wird-progress'));
        expect(Theme.of(tester.element(progress)).brightness, brightness);
        expect(tester.widget<LinearProgressIndicator>(progress).value, 0);
        await khatmaCubit.recordProgress(50);
        await tester.pumpAndSettle();
        expect(
          tester.widget<LinearProgressIndicator>(progress).value,
          closeTo(9 / 563, .000001),
        );

        if (const bool.fromEnvironment('CAPTURE_WIDGET_GALLERY')) {
          await settingsCubit.selectCity(
            const NearbyCity('مكة المكرمة', 21.4, 39.8, 'Makkah'),
          );
          homeCubit.updateSettings(settingsCubit.state.settings);
          await khatmaCubit.recordProgress(310);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('gallery-preview')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            const captureDirectory = String.fromEnvironment(
              'WIDGET_GALLERY_CAPTURE_DIR',
              defaultValue: 'screenshots',
            );
            await Directory(captureDirectory).create(recursive: true);
            await File('$captureDirectory/home_widgets_${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        final darkChoice = find.byKey(const ValueKey('widget-theme-dark'));
        await tester.ensureVisible(darkChoice);
        await tester.pumpAndSettle();
        await tester.tap(darkChoice);
        await tester.pumpAndSettle();
        expect(
          settingsCubit.state.settings.widgetTheme,
          AppThemePreference.dark,
        );
        expect(settingsStorage.readMap('settings')['widgetTheme'], 'dark');
        expect(Theme.of(tester.element(progress)).brightness, Brightness.dark);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('widget-theme-light')));
        await tester.pumpAndSettle();
        expect(
          settingsCubit.state.settings.widgetTheme,
          AppThemePreference.light,
        );
        expect(Theme.of(tester.element(progress)).brightness, Brightness.light);
        await tester.tap(systemChoice);
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(progress)).brightness, brightness);
        // The system widget theme is independent of the application theme.
        tester.platformDispatcher.platformBrightnessTestValue =
            brightness == Brightness.dark ? Brightness.light : Brightness.dark;
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(progress)).brightness,
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );

        await tester.binding.setSurfaceSize(const Size(320, 700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('الصلاة والقبلة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('الصلاة والقبلة'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('الصلاة على شاشة القفل'), findsOneWidget);
        widgetService.pinSupported = true;
        await tester.tap(find.byTooltip('تحديث الحالة'));
        await tester.pumpAndSettle();
        final lockInstructions = find.byKey(
          const ValueKey('lock-screen-prayer-instructions'),
        );
        await tester.ensureVisible(lockInstructions);
        await tester.pumpAndSettle();
        await tester.tap(lockInstructions);
        await tester.pumpAndSettle();
        expect(find.text('أضف الصلاة إلى شاشة القفل'), findsOneWidget);
        if (brightness == Brightness.dark) {
          expect(find.text('اختر «تخصيص» ثم «شاشة القفل».'), findsOneWidget);
          expect(
            find.text('اضغط «إضافة ودجت»، ثم اختر «مشكاة» و«مواقيت الصلاة».'),
            findsOneWidget,
          );
        } else {
          expect(
            find.textContaining('إذا كان جهازك يدعم ودجت شاشة القفل'),
            findsOneWidget,
          );
          expect(
            find.textContaining('تعتمد الإتاحة على جهازك وإصدار النظام'),
            findsOneWidget,
          );
        }
        expect(widgetService.pinRequests, 0);
        await tester.ensureVisible(find.text('فهمت'));
        await tester.tap(find.text('فهمت'));
        await tester.pumpAndSettle();
        widgetService.pinSupported = false;
        await tester.tap(find.byTooltip('تحديث الحالة'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('القرآن'),
          -400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('القرآن'));
        await tester.pumpAndSettle();
        expect(find.text('الورد اليومي'), findsOneWidget);
        expect(find.text('المسبحة'), findsNothing);
        expect(find.text('مواقيت الصلاة'), findsNothing);
        expect(find.text('الصلاة على شاشة القفل'), findsNothing);

        await tester.ensureVisible(find.text('أضف للشاشة الرئيسية'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('أضف للشاشة الرئيسية'));
        await tester.pumpAndSettle();
        expect(
          find.text('ابحث عن «مشكاة»، ثم اختر «الورد اليومي».'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await settingsCubit.close();
        await homeCubit.close();
        await khatmaCubit.close();
        await tasbihCubit.close();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
