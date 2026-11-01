import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';
import 'package:mishkat_app/features/settings/presentation/pages/settings_page.dart';
import 'package:mishkat_app/features/settings/presentation/widgets/about_mishkat_dialog.dart';

class _Storage extends LocalStorageService {
  final Map<String, Map<String, dynamic>> values = {};
  @override
  Map<String, dynamic> readMap(String key) => values[key] ?? {};
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    values[key] = value;
  }
}

class _Notifications extends LocalNotificationService {
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

Future<SettingsCubit> _mount(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  bool prayerSettings = false,
}) async {
  final storage = _Storage();
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
    notifications: _Notifications(),
  );
  await cubit.load();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) => MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: state.settings.theme == AppThemePreference.dark
              ? AppTheme.dark(state.settings.uiFontScale)
              : AppTheme.light(state.settings.uiFontScale),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: SettingsPage(openPrayerSettings: prayerSettings),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

Future<void> _openRow(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'مشكاة',
      packageName: 'com.dakomn.mishkatapp',
      version: '1.2.3',
      buildNumber: '154',
      buildSignature: '',
    ),
  );

  for (final (dark, size, scale) in [
    (false, const Size(390, 844), 1.0),
    (true, const Size(390, 844), 1.0),
    (false, const Size(320, 568), 2.0),
    (true, const Size(320, 568), 2.0),
  ]) {
    testWidgets(
      'About opens as a scrollable dialog with actual English version (dark: $dark, scale: $scale)',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _mount(tester, dark: dark, scale: scale);
        expect(find.byKey(const ValueKey('theme-dark')), findsOneWidget);
        await _openRow(tester, 'عن مشكاة');
        expect(find.byType(AboutMishkatDialog), findsOneWidget);
        expect(find.text('1.2.3'), findsOneWidget);
        expect(find.text('(154)'), findsOneWidget);
        expect(
          tester.getRect(find.text('1.2.3')).right,
          lessThan(tester.getRect(find.text('(154)')).left),
        );
        expect(find.text('سورة النور، الآية ٣٥'), findsOneWidget);
        final version = find.byKey(const ValueKey('about-app-version'));
        expect(tester.getRect(version).bottom, lessThan(size.height));
        await tester.scrollUntilVisible(
          find.textContaining('المصحف برواية حفص'),
          200,
          scrollable: find.descendant(
            of: find.byType(AboutMishkatDialog),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('إغلاق'));
        await tester.pumpAndSettle();
        expect(find.byType(AboutMishkatDialog), findsNothing);
        expect(find.byKey(const ValueKey('settings-about')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reading preferences remain editable and persist after returning',
    (tester) async {
      final cubit = await _mount(tester);
      await _openRow(tester, 'القراءة والتلاوة');
      expect(find.text('حجم خط الواجهة'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<double>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('كبير جدًا').last);
      await tester.pumpAndSettle();
      expect(cubit.state.settings.uiFontScale, 1.25);
      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
      expect(find.text('الإعدادات'), findsOneWidget);
      await cubit.load();
      expect(cubit.state.settings.uiFontScale, 1.25);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('notification preferences are reachable and stay in sync', (
    tester,
  ) async {
    final cubit = await _mount(tester);
    await _openRow(tester, 'الأذان والتنبيهات');
    expect(find.text('نظام التنبيهات'), findsOneWidget);
    await tester.tap(find.text('نظام التنبيهات'));
    await tester.pumpAndSettle();
    expect(cubit.state.settings.notificationsEnabled, isTrue);
    expect(find.text('الأذان عند دخول الوقت'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.textContaining('التنبيهات مفعّلة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prayer settings shortcut still opens the calculation controls', (
    tester,
  ) async {
    await _mount(tester, prayerSettings: true);
    expect(find.text('الموقع والمواقيت'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('طريقة حساب المواقيت'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('حساب صلاة العصر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'About reads changed package metadata instead of a fixed version',
    (tester) async {
      await _mount(tester);
      await _openRow(tester, 'عن مشكاة');
      expect(find.text('1.2.3'), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pumpAndSettle();
      PackageInfo.setMockInitialValues(
        appName: 'مشكاة',
        packageName: 'com.dakomn.mishkatapp',
        version: '2.4.6',
        buildNumber: '32',
        buildSignature: '',
      );
      await _openRow(tester, 'عن مشكاة');
      expect(find.text('2.4.6'), findsOneWidget);
      expect(find.text('(32)'), findsOneWidget);
      expect(find.text('1.2.3'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
