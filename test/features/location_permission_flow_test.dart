import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/widgets/location_permission_flow.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class _MemoryStorage extends LocalStorageService {
  final Map<String, Map<String, dynamic>> data = {};

  @override
  Map<String, dynamic> readMap(String key) => data[key] ?? {};

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    data[key] = value;
  }
}

class _Notifications extends LocalNotificationService {
  @override
  Future<void> cancelAll() async {}
}

class _Location extends LocationService {
  LocationFailure? failure;
  Completer<AppPosition>? pending;
  int calls = 0;

  @override
  Future<AppPosition> currentPosition() async {
    calls++;
    if (failure != null) throw failure!;
    return pending?.future ??
        const AppPosition(
          latitude: 21.3891,
          longitude: 39.8579,
          label: 'مكة المكرمة',
          suggestedMethod: 'Makkah',
        );
  }
}

class _SettingsPlatform extends GeolocatorPlatform {
  int applicationSettings = 0;
  int locationSettings = 0;

  @override
  Future<bool> openAppSettings() async {
    applicationSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }
}

void main() {
  late _Location location;
  late SettingsCubit settings;
  late GeolocatorPlatform originalPlatform;
  late _SettingsPlatform platform;
  bool? result;

  setUp(() async {
    result = null;
    location = _Location();
    settings = SettingsCubit(
      storage: _MemoryStorage(),
      locationService: location,
      notifications: _Notifications(),
    );
    await settings.load();
    originalPlatform = GeolocatorPlatform.instance;
    platform = _SettingsPlatform();
    GeolocatorPlatform.instance = platform;
  });
  tearDown(() async {
    GeolocatorPlatform.instance = originalPlatform;
    await settings.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('use-location'),
                onPressed: () async {
                  result = await LocationPermissionFlow.useCurrentLocation(
                    context,
                  );
                },
                child: const Text('استخدام موقعي الحالي'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('use-location')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'denial offers a city in the same feature without another permission',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      location.failure = const LocationFailure(
        'لم يُسمح بالوصول إلى الموقع.',
        reason: LocationFailureReason.denied,
      );
      await mount(tester);
      expect(find.text('الموقع للصلاة والقبلة'), findsOneWidget);
      expect(find.text('فتح إعدادات الجهاز'), findsNothing);
      expect(settings.state.message, isNull);
      expect(location.calls, 1);
      await tester.tap(find.text('اختيار مدينة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مكة المكرمة'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(settings.state.settings.locationAuto, isFalse);
      expect(settings.state.settings.city, 'مكة المكرمة');
      expect(location.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reason in [
    LocationFailureReason.permanentlyDenied,
    LocationFailureReason.serviceDisabled,
  ]) {
    testWidgets(
      '$reason opens the correct system screen and retries only on request',
      (tester) async {
        location.failure = LocationFailure('الموقع غير متاح.', reason: reason);
        await mount(tester);
        await tester.tap(find.text('فتح إعدادات الجهاز'));
        await tester.pumpAndSettle();
        expect(
          platform.applicationSettings,
          reason == LocationFailureReason.permanentlyDenied ? 1 : 0,
        );
        expect(
          platform.locationSettings,
          reason == LocationFailureReason.serviceDisabled ? 1 : 0,
        );
        expect(location.calls, 1);
        location.failure = null;
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pumpAndSettle();
        expect(location.calls, 2);
        expect(result, isTrue);
        expect(settings.state.settings.locationAuto, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  testWidgets('dismissal respects denial without a prompt loop', (
    tester,
  ) async {
    location.failure = const LocationFailure(
      'لا يوجد إذن.',
      reason: LocationFailureReason.denied,
    );
    await mount(tester);
    await tester.tap(find.text('لاحقًا'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(location.calls, 1);
    expect(settings.state.settings.hasLocation, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'rapid taps share the active request and disposed feature shows no dialog',
    (tester) async {
      location.pending = Completer<AppPosition>();
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('use-location')));
      await tester.pump();
      expect(location.calls, 1);
      await tester.pumpWidget(const SizedBox());
      location.pending!.completeError(
        const LocationFailure('لم يُسمح بالموقع.'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
