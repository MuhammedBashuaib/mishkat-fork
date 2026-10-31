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
      find.text('اختر تذكيراتك، ثم فعّل «نظام التنبيهات» لتصلك.'),
      findsOneWidget,
    );
    final charity = find.text('التذكير بالصدقة');
    await tester.ensureVisible(charity);
    await tester.tap(charity);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.charityEnabled, false);
    expect(find.text('موعد الصدقة صباحًا'), findsNothing);

    final frequency = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(frequency);
    await tester.tap(frequency);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خفيف — مرة يوميًا').last);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.dhikrPerDay, 1);

    final sound = find.text('صوت تذكيرات الخير والأذكار');
    await tester.ensureVisible(sound);
    await tester.tap(sound);
    await tester.pumpAndSettle();
    expect(cubit.state.settings.reminders.sound, true);
    expect(cubit.state.settings.adhanSound, true);
    expect(AppSettings.fromJson(storage.saved), cubit.state.settings);
    expect(tester.takeException(), isNull);
  });
}
