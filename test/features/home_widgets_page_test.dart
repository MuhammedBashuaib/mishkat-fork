import 'dart:io';
import 'dart:ui' as ui;

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

  @override
  Future<bool> isPinRequestSupported() async => false;
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
        await tester.binding.setSurfaceSize(const Size(390, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final settingsCubit = SettingsCubit(
          storage: _MemoryStorage(),
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
        final actionCount =
            find.text('أضف للشاشة الرئيسية').evaluate().length +
            find.text('جارٍ التحقق…').evaluate().length;
        expect(actionCount, 5);
        expect(find.text('الورد اليومي'), findsOneWidget);
        expect(find.text('المسبحة'), findsOneWidget);

        if (const bool.fromEnvironment('CAPTURE_WIDGET_GALLERY')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('gallery-preview')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('screenshots/home_widgets_${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        final previewToggle = find.byTooltip(
          brightness == Brightness.dark
              ? 'معاينة المظهر الفاتح'
              : 'معاينة المظهر الداكن',
        );
        await tester.ensureVisible(previewToggle);
        await tester.pumpAndSettle();
        await tester.tap(previewToggle);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(const Size(320, 700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('الصلاة والقبلة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('الصلاة والقبلة'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('القرآن'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('القرآن'));
        await tester.pumpAndSettle();
        expect(find.text('الورد اليومي'), findsOneWidget);
        expect(find.text('المسبحة'), findsNothing);
        expect(find.text('مواقيت الصلاة'), findsNothing);

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
      },
    );
  }
}
