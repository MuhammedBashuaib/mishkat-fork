import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';
import 'package:mishkat_app/features/settings/presentation/pages/settings_page.dart';

// Opt-in visual review; produces images without changing device settings/data.
// flutter test --dart-define=CAPTURE_SETTINGS_CALM=true test/settings_calm_capture_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const captureEnabled = bool.fromEnvironment('CAPTURE_SETTINGS_CALM');

  setUpAll(() async {
    if (!captureEnabled) return;
    final cairo = FontLoader('Cairo');
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Directory('screenshots').create(recursive: true);
  });

  for (final (name, dark, size, scale) in [
    ('light', false, const Size(390, 844), 1.0),
    ('dark', true, const Size(390, 844), 1.0),
    ('small_large_text', false, const Size(320, 568), 2.0),
  ]) {
    testWidgets('capture calm settings: $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _CaptureStorage();
      await storage.writeMap(
        'settings',
        AppSettings(
          theme: dark ? AppThemePreference.dark : AppThemePreference.light,
          city: 'المكلا',
          latitude: 14.54,
          longitude: 49.12,
        ).toJson(),
      );
      final cubit = SettingsCubit(
        storage: storage,
        locationService: LocationService(),
        notifications: _CaptureNotifications(),
      );
      await cubit.load();
      addTearDown(cubit.close);
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: RepaintBoundary(
            key: boundaryKey,
            child: BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, state) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.only(top: 24, bottom: 20),
                  ),
                  child: child!,
                ),
                home: const SettingsPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('screenshots/settings_calm_${name}_$state.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await _openSettingsRow(tester, 'تذكيرات الخير والأذكار');
      await capture('reminders');
      final charity = find.byKey(const ValueKey('reminder-charity'));
      await tester.ensureVisible(charity);
      await tester.pumpAndSettle();
      expect(charity.hitTestable(), findsOneWidget);
      await tester.tap(charity);
      await tester.pumpAndSettle();
      expect(find.text('موعد الصدقة صباحًا'), findsOneWidget);
      await Scrollable.ensureVisible(tester.element(charity), alignment: 0.1);
      await tester.pumpAndSettle();
      await capture('charity');

      final dhikr = find.byKey(const ValueKey('reminder-dhikr'));
      await tester.ensureVisible(dhikr);
      await tester.pumpAndSettle();
      await tester.tap(dhikr);
      await tester.pumpAndSettle();
      final frequency = find.byType(DropdownButtonFormField<int>);
      expect(frequency, findsOneWidget);
      await Scrollable.ensureVisible(tester.element(frequency), alignment: 0.4);
      await tester.pumpAndSettle();
      await capture('dhikr');
      await tester.tap(frequency);
      await tester.pumpAndSettle();
      await capture('dhikr_menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
      await _openSettingsRow(tester, 'سياسة الخصوصية');
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byTooltip('إغلاق').hitTestable(), findsOneWidget);
      await capture('privacy');
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !captureEnabled);
  }
}

Future<void> _openSettingsRow(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

class _CaptureStorage extends LocalStorageService {
  final _values = <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic> readMap(String key) => _values[key] ?? {};

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _values[key] = value;
  }
}

class _CaptureNotifications extends LocalNotificationService {
  @override
  Future<bool> canSchedulePrecisely() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleAll(
    List<ScheduledAppNotification> notifications,
  ) async {}

  @override
  Future<void> cancelAll() async {}
}
