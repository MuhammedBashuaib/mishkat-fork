import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/khatma/presentation/pages/khatma_page.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

void main() {
  testWidgets('custom months use Arabic input and persist a five month plan', (
    tester,
  ) async {
    final harness = await _openBuilder(tester);
    await _tapText(tester, 'مخصص');
    await _enter(tester, 'khatma-custom-duration', '٥');
    await _choose(tester, 'khatma-duration-unit', 'أشهر');
    await _withoutReminder(tester);
    await _submit(tester);

    final plan = harness.khatma.state.active!;
    expect(plan.planningMode, KhatmaPlanningMode.duration);
    expect(plan.durationDays, 150);
    expect(plan.dailyPages, 5);
    final restored = KhatmaCubit(harness.storage);
    addTearDown(restored.close);
    expect(restored.state.active, plan);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom three day plan is accepted', (tester) async {
    final harness = await _openBuilder(tester);
    await _tapText(tester, 'مخصص');
    await _enter(tester, 'khatma-custom-duration', '3');
    await _withoutReminder(tester);
    await _submit(tester);

    final plan = harness.khatma.state.active!;
    expect(plan.durationDays, 3);
    expect(plan.dailyPages, 202);
    expect(plan.todayEnd, 202);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five daily pages produces 121 days and keeps the page target', (
    tester,
  ) async {
    final harness = await _openBuilder(tester);
    await _tapText(tester, 'بالصفحات');
    await _enter(tester, 'khatma-daily-pages', '٥');
    expect(find.textContaining('121'), findsWidgets);
    await _withoutReminder(tester);
    await _submit(tester);

    final plan = harness.khatma.state.active!;
    expect(plan.planningMode, KhatmaPlanningMode.pages);
    expect(plan.dailyPages, 5);
    expect(plan.durationDays, 121);
    expect(plan.todayEnd, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page plans calculate from the selected starting page', (
    tester,
  ) async {
    final harness = await _openBuilder(tester);
    await _enter(tester, 'khatma-start-page', '٦٠٠');
    await _tapText(tester, 'بالصفحات');
    await _enter(tester, 'khatma-daily-pages', '5');
    await _withoutReminder(tester);
    await _submit(tester);

    final plan = harness.khatma.state.active!;
    expect(plan.startPage, 600);
    expect(plan.durationDays, 1);
    expect(plan.dailyPages, 5);
    expect(plan.todayEnd, 604);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a chosen daily reminder time is saved with notification permission',
    (tester) async {
      final harness = await _openBuilder(tester);
      await _choose(tester, 'khatma-reminder', 'وقت محدد');
      final timeButton = find.byKey(const Key('khatma-reminder-time'));
      await tester.ensureVisible(timeButton);
      await tester.tap(timeButton);
      await tester.pumpAndSettle();
      final localizations = MaterialLocalizations.of(
        tester.element(find.byType(TimePickerDialog)),
      );
      await tester.tap(find.byTooltip(localizations.inputTimeModeButtonLabel));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputs.at(0), '21');
      await tester.enterText(inputs.at(1), '17');
      tester.testTextInput.hide();
      await tester.tap(find.text(localizations.okButtonLabel));
      await tester.pumpAndSettle();
      await _submit(tester);

      final plan = harness.khatma.state.active!;
      expect(plan.reminderTime, '21:17');
      expect(plan.reminderPrayer, isNull);
      expect(harness.notifications.permissionRequests, 1);
      expect(harness.settings.state.settings.notificationsEnabled, true);
      final reminder = harness.notifications.latest.singleWhere(
        (item) => item.payload == 'khatma:${plan.id}',
      );
      expect(reminder.at.hour, 21);
      expect(reminder.at.minute, 17);
      expect(reminder.repeatsDaily, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid page and duration values cannot create a plan', (
    tester,
  ) async {
    final harness = await _openBuilder(tester);
    await _tapText(tester, 'مخصص');
    await _enter(tester, 'khatma-custom-duration', '0');
    await _submit(tester);
    expect(harness.khatma.state.plans, isEmpty);
    expect(find.text('أنشئ خطة ختمتك'), findsOneWidget);

    await _enter(tester, 'khatma-custom-duration', '605');
    await _submit(tester);
    expect(harness.khatma.state.plans, isEmpty);

    await _enter(tester, 'khatma-custom-duration', '3');
    await _enter(tester, 'khatma-start-page', '605');
    await _submit(tester);
    expect(harness.khatma.state.plans, isEmpty);

    await _enter(tester, 'khatma-start-page', '1');
    await _tapText(tester, 'بالصفحات');
    for (final invalid in ['', '0', '605']) {
      await _enter(tester, 'khatma-daily-pages', invalid);
      await _submit(tester);
      expect(harness.khatma.state.plans, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs retains entries and cancelling creates nothing', (
    tester,
  ) async {
    final harness = await _openBuilder(tester);
    await _tapText(tester, 'مخصص');
    await _enter(tester, 'khatma-custom-duration', '3');
    await _tapText(tester, 'بالصفحات');
    await _enter(tester, 'khatma-daily-pages', '7');
    await _tapText(tester, 'بالمدة');
    expect(_inputValue(tester, 'khatma-custom-duration'), '3');
    await _tapText(tester, 'بالصفحات');
    expect(_inputValue(tester, 'khatma-daily-pages'), '7');

    final context = tester.element(find.byKey(const Key('khatma-submit')));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(harness.khatma.state.plans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom controls fit a narrow RTL screen with larger text', (
    tester,
  ) async {
    final harness = await _openBuilder(
      tester,
      size: const Size(320, 760),
      textScale: 1.4,
    );
    await _tapText(tester, 'مخصص');
    await _enter(tester, 'khatma-custom-duration', '5');
    await _choose(tester, 'khatma-duration-unit', 'أشهر');
    expect(tester.takeException(), isNull);
    await _tapText(tester, 'بالصفحات');
    await _enter(tester, 'khatma-daily-pages', '5');
    await _choose(tester, 'khatma-reminder', 'وقت محدد');
    await tester.ensureVisible(find.byKey(const Key('khatma-reminder-time')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(harness.khatma.state.plans, isEmpty);
  });

  testWidgets(
    'denied notifications preserve the plan and show permission feedback',
    (tester) async {
      final harness = await _openBuilder(tester, permissionGranted: false);
      await _submit(tester);

      expect(harness.khatma.state.plans, hasLength(1));
      expect(harness.notifications.permissionRequests, 1);
      expect(harness.settings.state.settings.notificationsEnabled, false);
      expect(find.textContaining('إشعار'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Harness> _openBuilder(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool permissionGranted = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = _MemoryStorage();
  final notifications = _Notifications(permissionGranted);
  final khatma = KhatmaCubit(storage, notifications: notifications);
  final settings = SettingsCubit(
    storage: storage,
    locationService: LocationService(),
    notifications: notifications,
  );
  await settings.load();
  addTearDown(khatma.close);
  addTearDown(settings.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: khatma),
        BlocProvider.value(value: settings),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => KhatmaPage.showCreatePlanModal(context, 1),
                child: const Text('فتح الخطة'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('فتح الخطة'));
  await tester.pumpAndSettle();
  return _Harness(storage, khatma, settings, notifications);
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await _tapText(tester, value);
}

Future<void> _withoutReminder(WidgetTester tester) =>
    _choose(tester, 'khatma-reminder', 'دون تذكير');

Future<void> _submit(WidgetTester tester) async {
  final finder = find.byKey(const Key('khatma-submit'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _inputValue(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

class _Harness {
  const _Harness(this.storage, this.khatma, this.settings, this.notifications);
  final _MemoryStorage storage;
  final KhatmaCubit khatma;
  final SettingsCubit settings;
  final _Notifications notifications;
}

class _MemoryStorage extends LocalStorageService {
  final _values = <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_values[key] ?? const {});

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _values[key] = Map<String, dynamic>.from(value);
  }
}

class _Notifications extends LocalNotificationService {
  _Notifications(this.granted);
  final bool granted;
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
