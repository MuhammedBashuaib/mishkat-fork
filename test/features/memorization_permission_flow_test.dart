import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/memorization_plan_page.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

void main() {
  testWidgets('saving a reminder requests permission and schedules the plan', (
    tester,
  ) async {
    final harness = await _openPlan(tester);
    await _save(tester);

    expect(harness.notifications.permissionRequests, 1);
    expect(harness.settings.state.settings.notificationsEnabled, isTrue);
    expect(harness.memorization.state.plans, hasLength(1));
    expect(
      harness.notifications.latest.any((item) => item.id == 800001),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'denial preserves the plan without claiming its reminder is ready',
    (tester) async {
      final harness = await _openPlan(tester, permissionGranted: false);
      await _save(tester);
      expect(harness.memorization.state.plans, isEmpty);
      await tester.tap(find.byKey(const Key('notification-permission-later')));
      await tester.pumpAndSettle();

      expect(harness.notifications.permissionRequests, 1);
      expect(harness.settings.state.settings.notificationsEnabled, isFalse);
      expect(harness.memorization.state.plans, hasLength(1));
      final restored = await QuranMemorizationRepository(
        storage: harness.storage,
      ).loadData();
      expect(restored.plans, hasLength(1));
      expect(
        find.text('حُفظت خطة الحفظ، ولم يكتمل تفعيل التذكير.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('revoked OS permission is checked despite an enabled master', (
    tester,
  ) async {
    final harness = await _openPlan(tester, initiallyEnabled: true);
    harness.notifications.granted = false;
    await _save(tester);

    expect(harness.notifications.permissionRequests, 1);
    expect(
      find.byKey(const Key('notification-permission-later')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('notification-permission-later')));
    await tester.pumpAndSettle();
    expect(harness.memorization.state.plans, hasLength(1));
    expect(
      find.text('حُفظت خطة الحفظ، ولم يكتمل تفعيل التذكير.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving without a reminder does not request notification access',
    (tester) async {
      final harness = await _openPlan(tester, permissionGranted: false);
      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _save(tester);

      expect(harness.notifications.permissionRequests, 0);
      expect(harness.memorization.state.plans.single.reminderHour, isNull);
      expect(harness.settings.state.settings.notificationsEnabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('بدء وتثبيت خطة الحفظ'));
  // While permission recovery is open, the plan's save spinner intentionally
  // remains active underneath it, so waiting for all animations would hang.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<_Harness> _openPlan(
  WidgetTester tester, {
  bool permissionGranted = true,
  bool initiallyEnabled = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = _Storage();
  if (initiallyEnabled) {
    await storage.writeMap('settings', {'notificationsEnabled': true});
  }
  final notifications = _Notifications(permissionGranted);
  final settings = SettingsCubit(
    storage: storage,
    locationService: LocationService(),
    notifications: notifications,
  );
  await settings.load();
  final memorization = QuranMemorizationCubit(
    repository: QuranMemorizationRepository(storage: storage),
    notificationService: notifications,
  );
  await memorization.load();
  addTearDown(settings.close);
  addTearDown(memorization.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: settings),
        BlocProvider.value(value: memorization),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MemorizationPlanPage.route(quranData: _quranData)),
              child: const Text('فتح خطة الحفظ'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('فتح خطة الحفظ'));
  await tester.pumpAndSettle();
  return _Harness(storage, settings, memorization, notifications);
}

const _quranData = QuranData(
  chapters: [
    QuranChapter(
      number: 1,
      name: 'الفاتحة',
      englishName: 'Al-Faatiha',
      revelationType: 'Meccan',
      page: 1,
      ayahs: ['آية ١', 'آية ٢', 'آية ٣', 'آية ٤', 'آية ٥', 'آية ٦', 'آية ٧'],
      globalStart: 1,
    ),
  ],
  juz: [JuzStart(number: 1, surah: 1, ayah: 1)],
  pages: [],
);

class _Harness {
  const _Harness(
    this.storage,
    this.settings,
    this.memorization,
    this.notifications,
  );
  final _Storage storage;
  final SettingsCubit settings;
  final QuranMemorizationCubit memorization;
  final _Notifications notifications;
}

class _Storage extends LocalStorageService {
  final _maps = <String, Map<String, dynamic>>{};
  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_maps[key] ?? const {});
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _maps[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {}
}

class _Notifications extends LocalNotificationService {
  _Notifications(this.granted);
  bool granted;
  int permissionRequests = 0;
  List<ScheduledAppNotification> latest = [];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<bool> canSchedulePrecisely() async => true;
  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    latest = notifications;
  }

  @override
  Future<void> cancelAll() async {}
}
