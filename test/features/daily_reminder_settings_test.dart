import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';
import 'package:mishkat_app/features/settings/presentation/widgets/daily_reminder_settings.dart';

class _Storage extends LocalStorageService {
  Map<String, dynamic> saved = {};
  @override
  Map<String, dynamic> readMap(String key) => key == 'settings' ? saved : {};
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    if (key == 'settings') saved = value;
  }
}

void main() {
  testWidgets('reminder controls fit a small RTL screen and persist choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _Storage();
    final cubit = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: LocalNotificationService(),
    );
    await cubit.load();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: BlocBuilder<SettingsCubit, SettingsState>(
                  builder: (context, state) =>
                      DailyReminderSettings(settings: state.settings),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('فعّل الإشعارات لتصلك التذكيرات التي تختارها.'),
      findsOneWidget,
    );
    // The overview stays quiet even when every reminder is enabled.
    expect(find.text('موعد الصدقة صباحًا'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.textContaining('نباعد تذكيرات'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reminder-friday')));
    await tester.pumpAndSettle();
    final friday = find.byKey(const ValueKey('friday-reminders-toggle'));
    expect(cubit.state.settings.reminders.fridayEnabled, true);
    await tester.ensureVisible(friday);
    await tester.tap(friday);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.fridayEnabled, false);
    expect(storage.saved['reminders']['fridayEnabled'], false);
    expect(cubit.state.settings.reminders.dhikrEnabled, true);
    expect(cubit.state.settings.adhkarNotifications, true);
    final charity = find.text('التذكير بالصدقة');
    await tester.ensureVisible(charity);
    await tester.tap(charity);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('friday-reminders-toggle')), findsNothing);
    expect(find.text('موعد الصدقة صباحًا'), findsOneWidget);
    // Opening a section does not toggle or reschedule its saved preference.
    expect(cubit.state.settings.reminders.charityEnabled, true);
    final charityToggle = find.byKey(
      const ValueKey('charity-reminders-toggle'),
    );
    await tester.ensureVisible(charityToggle);
    await tester.tap(charityToggle);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.charityEnabled, false);
    expect(find.text('موعد الصدقة صباحًا'), findsNothing);

    final dhikr = find.byKey(const ValueKey('reminder-dhikr'));
    await tester.ensureVisible(dhikr);
    await tester.tap(dhikr);
    await tester.pumpAndSettle();
    final frequency = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(frequency);
    await tester.tap(frequency);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مرة يوميًا').last);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.dhikrPerDay, 1);

    final sound = find.byKey(const ValueKey('reminder-sound-toggle'));
    await tester.ensureVisible(sound);
    await tester.tap(sound);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.sound, true);
    expect(cubit.state.settings.adhanSound, true);
    expect(AppSettings.fromJson(storage.saved), cubit.state.settings);
    expect(tester.takeException(), isNull);
  });
}
