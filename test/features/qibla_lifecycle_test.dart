import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_cubit.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_state.dart';
import 'package:mishkat_app/features/qibla/presentation/pages/qibla_page.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

import 'quran_home_hub_test.dart'
    show FakeLocationService, FakeNotificationService, InMemoryLocalStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform rejects nonfinite headings and recovers cleanly', () async {
      final events = StreamController<CompassEvent>.broadcast(sync: true);
      final cubit = QiblaCubit(platform: platform, compassEvents: events.stream)
        ..setLocation(14.7664, 49.6254);
      addTearDown(events.close);
      addTearDown(cubit.close);
      await cubit.start();
      for (final invalid in [double.nan, double.infinity, -double.infinity]) {
        events.add(CompassEvent.fromList([40, 0, 5]));
        expect(cubit.state.heading, isNotNull);
        events.add(CompassEvent.fromList([invalid, 0, 5]));
        expect(cubit.state.status, QiblaStatus.unavailable);
        expect(cubit.state.heading, isNull);
        expect(cubit.state.aligned, isFalse);
      }
      events.add(CompassEvent.fromList([0, 0, 5]));
      expect(cubit.state.heading, closeTo(cubit.state.declination ?? 0, .001));
      expect(cubit.state.status, QiblaStatus.listening);
    });
  }

  test(
    'iOS -1 is unavailable while Android negative headings are valid',
    () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        final events = StreamController<CompassEvent>.broadcast(sync: true);
        final cubit = QiblaCubit(
          platform: platform,
          compassEvents: events.stream,
        )..setLocation(14.7664, 49.6254);
        await cubit.start();
        events.add(CompassEvent.fromList([-1, 0, 5]));
        if (platform == TargetPlatform.iOS) {
          expect(cubit.state.heading, isNull);
          expect(cubit.state.status, QiblaStatus.unavailable);
        } else {
          final expected = (-1 + cubit.state.declination! + 360) % 360;
          expect(cubit.state.heading, closeTo(expected, .001));
          expect(cubit.state.status, QiblaStatus.listening);
        }
        await cubit.close();
        await events.close();
      }
    },
  );

  test('stop cancels a start still awaiting subscription setup', () async {
    final events = StreamController<CompassEvent>.broadcast();
    final cubit = QiblaCubit(compassEvents: events.stream)
      ..setLocation(14.7664, 49.6254);
    final starting = cubit.start();
    await cubit.stop();
    await starting;
    expect(events.hasListener, isFalse);
    expect(cubit.state.status, QiblaStatus.ready);
    await cubit.close();
    await events.close();
  });

  testWidgets(
    'hidden tabs and covered routes stop sensors and alignment haptics',
    (tester) async {
      final storage = InMemoryLocalStorage();
      final settings = SettingsCubit(
        storage: storage,
        locationService: FakeLocationService(),
        notifications: FakeNotificationService(),
      );
      await settings.load();
      await settings.selectCity(
        const NearbyCity('الشحر', 14.7664, 49.6254, 'MWL'),
      );
      final events = StreamController<CompassEvent>.broadcast(sync: true);
      final cubit = QiblaCubit(
        platform: TargetPlatform.iOS,
        compassEvents: events.stream,
      )..setLocation(14.7664, 49.6254);
      var haptics = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await cubit.close();
        await settings.close();
        await events.close();
      });
      final navigator = GlobalKey<NavigatorState>();
      var active = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: settings),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return IndexedStack(
                  index: active ? 1 : 0,
                  children: [
                    const SizedBox(),
                    QiblaPage(isActive: active),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);
      cubit.setHeadingForTesting(cubit.state.bearing, accuracy: 5);
      await tester.pump();
      expect(haptics, 0);
      await cubit.stop();

      rebuild(() => active = true);
      await tester.pumpAndSettle();
      expect(events.hasListener, isTrue);
      events.add(CompassEvent.fromList([cubit.state.bearing!, 0, 5]));
      await tester.pump();
      expect(haptics, 1);

      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(events.hasListener, isTrue);

      rebuild(() => active = false);
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);

      rebuild(() => active = true);
      await tester.pumpAndSettle();
      expect(events.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(events.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(events.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(events.hasListener, isFalse);
    },
  );
}
