import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/recitation_feedback_settings.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('existing and malformed settings use the quiet sound default', () {
    expect(
      const AppSettings().recitationFeedbackMode,
      RecitationFeedbackMode.sound,
    );
    for (final value in [null, true, 1, 'unknown', '']) {
      final settings = AppSettings.fromJson({
        'recitationFeedbackMode': value,
        'theme': 'dark',
        'vibrate': false,
      });
      expect(settings.recitationFeedbackMode, RecitationFeedbackMode.sound);
      expect(settings.theme, AppThemePreference.dark);
      expect(settings.vibrate, isFalse);
    }
  });

  test(
    'feedback mode persists independently and survives a fresh cubit',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mishkat-feedback-settings-',
      );
      final storage = LocalStorageService(directory: directory);
      await storage.init();
      final cubit = SettingsCubit(
        storage: storage,
        locationService: LocationService(),
        notifications: LocalNotificationService(),
      );
      addTearDown(() async {
        await cubit.close();
        await directory.delete(recursive: true);
      });
      await cubit.load();
      await cubit.setVibration(false);
      await cubit.setTheme(AppThemePreference.dark);
      for (final mode in RecitationFeedbackMode.values) {
        await cubit.setRecitationFeedbackMode(mode);
        final settings = cubit.state.settings;
        expect(settings.recitationFeedbackMode, mode);
        expect(settings.vibrate, isFalse);
        expect(settings.theme, AppThemePreference.dark);
        expect(
          storage.readMap('settings')['recitationFeedbackMode'],
          mode.name,
        );
        expect(AppSettings.fromJson(settings.toJson()), settings);
        expect(settings.copyWith(recitationFeedbackMode: mode), settings);
      }
      expect(
        cubit.state.settings.copyWith(
          recitationFeedbackMode: RecitationFeedbackMode.sound,
        ),
        isNot(cubit.state.settings),
      );
      final reopened = SettingsCubit(
        storage: storage,
        locationService: LocationService(),
        notifications: LocalNotificationService(),
      );
      addTearDown(reopened.close);
      await reopened.load();
      expect(
        reopened.state.settings.recitationFeedbackMode,
        RecitationFeedbackMode.silent,
      );
      expect(reopened.state.settings.vibrate, isFalse);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'feedback options remain clear at 320dp and large text, dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var mode = RecitationFeedbackMode.sound;
        var previews = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Directionality(
                  textDirection: TextDirection.rtl,
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.6)),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: RecitationFeedbackSettings(
                        mode: mode,
                        onChanged: (value) => setState(() => mode = value),
                        canPreview: true,
                        onPreview: () => previews++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final sound = find.byKey(const ValueKey('recitation-feedback-sound'));
        final vibration = find.byKey(
          const ValueKey('recitation-feedback-vibration'),
        );
        final silent = find.byKey(const ValueKey('recitation-feedback-silent'));
        expect(Directionality.of(tester.element(sound)), TextDirection.rtl);
        expect(
          tester.getBottomLeft(sound).dy,
          lessThan(tester.getTopLeft(vibration).dy),
        );
        expect(
          tester.getBottomLeft(vibration).dy,
          lessThan(tester.getTopLeft(silent).dy),
        );
        expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
        await tester.tap(vibration);
        await tester.pump();
        expect(mode, RecitationFeedbackMode.vibration);
        final preview = find.byKey(
          const ValueKey('recitation-feedback-preview'),
        );
        await tester.ensureVisible(preview);
        await tester.tap(preview);
        await tester.pump();
        expect(previews, 1);
        await tester.ensureVisible(silent);
        await tester.tap(silent);
        await tester.pump();
        expect(mode, RecitationFeedbackMode.silent);
        expect(tester.widget<TextButton>(preview).onPressed, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('test cue stays disabled while capture or draining is active', (
    tester,
  ) async {
    var previews = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RecitationFeedbackSettings(
            mode: RecitationFeedbackMode.sound,
            onChanged: (_) {},
            canPreview: false,
            onPreview: () => previews++,
          ),
        ),
      ),
    );
    final preview = find.byKey(const ValueKey('recitation-feedback-preview'));
    expect(tester.widget<TextButton>(preview).onPressed, isNull);
    await tester.tap(preview);
    expect(previews, 0);
    expect(find.text('أوقف التسميع مؤقتًا لتجربة التنبيه.'), findsOneWidget);
  });
}
