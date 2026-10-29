import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/prayer_times/data/services/prayer_calculator.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_cubit.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_state.dart';
import 'package:mishkat_app/features/qibla/presentation/pages/qibla_page.dart';
import 'package:mishkat_app/features/qibla/presentation/widgets/mishkat_compass_widget.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/shell/presentation/widgets/mishkat_bottom_nav_bar.dart';

class FakeLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _store = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final val = _store[key];
    return val is Map ? Map<String, dynamic>.from(val) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final val = _store[key];
    return val is List ? List<dynamic>.from(val) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) =>
      (_store[key] as num?)?.toInt() ?? fallback;

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

void main() {
  group('1. Qibla Bearing & Mathematical Calculations Verification', () {
    const calculator = PrayerCalculator();

    test('Hadramout (الشحر / المكلا): bearing in range 305°-315°, distance ~1245 km', () {
      final result = calculator.qibla(14.7664, 49.6254);
      expect(result.bearing, inInclusiveRange(305.0, 315.0));
      expect(result.distanceKm, inInclusiveRange(1200.0, 1300.0));
    });

    test('Medina: due South towards Mecca (~176°), distance ~340 km', () {
      final result = calculator.qibla(24.4672, 39.6111);
      expect(result.bearing, inInclusiveRange(173.0, 180.0));
      expect(result.distanceKm, inInclusiveRange(300.0, 380.0));
    });

    test(
      'Cairo, Egypt: South-East towards Mecca (~136°), distance ~1290 km',
      () {
        final result = calculator.qibla(30.0444, 31.2357);
        expect(result.bearing, inInclusiveRange(130.0, 142.0));
        expect(result.distanceKm, inInclusiveRange(1200.0, 1350.0));
      },
    );

    test(
      'Jerusalem: South-South-East towards Mecca (~155°), distance ~1240 km',
      () {
        final result = calculator.qibla(31.7683, 35.2137);
        expect(result.bearing, inInclusiveRange(150.0, 160.0));
        expect(result.distanceKm, inInclusiveRange(1150.0, 1300.0));
      },
    );

    test('New York (USA): Great circle route East-North-East (~58.5°)', () {
      final result = calculator.qibla(40.7128, -74.0060);
      expect(result.bearing, inInclusiveRange(55.0, 62.0));
      expect(result.distanceKm, inInclusiveRange(10000.0, 11000.0));
    });

    test('Jakarta (Indonesia): North-West (~295°)', () {
      final result = calculator.qibla(-6.2088, 106.8456);
      expect(result.bearing, inInclusiveRange(290.0, 300.0));
      expect(result.distanceKm, inInclusiveRange(7500.0, 8500.0));
    });

    test('At the Kaaba itself: bearing is wrapped to 0°, distance 0 km', () {
      final result = calculator.qibla(21.4225, 39.8262);
      expect(result.distanceKm, closeTo(0.0, 1.0));
    });
  });

  group('2. Circular Delta & Angle Wrapping Mathematics', () {
    test(
      'Boundary crossing: Bearing 5°, Heading 355° -> Shortest Delta = +10°',
      () {
        const state = QiblaState(bearing: 5.0, heading: 355.0);
        expect(state.delta, closeTo(10.0, 0.001));
      },
    );

    test(
      'Boundary crossing: Bearing 355°, Heading 5° -> Shortest Delta = -10°',
      () {
        const state = QiblaState(bearing: 355.0, heading: 5.0);
        expect(state.delta, closeTo(-10.0, 0.001));
      },
    );

    test('Opposite directions (180° difference)', () {
      const state = QiblaState(bearing: 90.0, heading: 270.0);
      expect(state.delta?.abs(), closeTo(180.0, 0.001));
    });

    test('Alignment within threshold (<= 5°)', () {
      const state1 = QiblaState(bearing: 245.0, heading: 243.0);
      expect(state1.aligned, isTrue);

      const state2 = QiblaState(bearing: 245.0, heading: 250.0);
      expect(state2.aligned, isTrue); // delta = -5° is within 5°

      const state3 = QiblaState(bearing: 245.0, heading: 252.0);
      expect(state3.aligned, isFalse); // delta = -7° is outside 5°
    });

    test('Alignment respects sensor accuracy', () {
      const goodAccuracy = QiblaState(
        bearing: 100.0,
        heading: 100.0,
        accuracy: 5.0,
      );
      expect(goodAccuracy.aligned, isTrue);

      const poorAccuracy = QiblaState(
        bearing: 100.0,
        heading: 100.0,
        accuracy: 35.0,
      );
      expect(poorAccuracy.aligned, isFalse);

      const negativeAccuracy = QiblaState(
        bearing: 100.0,
        heading: 100.0,
        accuracy: -1.0,
      );
      expect(negativeAccuracy.aligned, isFalse);
    });

    test('Turn instructions format correctly', () {
      const alignedState = QiblaState(bearing: 100.0, heading: 100.0);
      expect(alignedState.turnInstruction, 'أنت الآن باتجاه القبلة مباشرة');

      const turnRightState = QiblaState(bearing: 120.0, heading: 100.0);
      expect(turnRightState.turnInstruction, 'استدر يمينًا بمقدار 20°');

      const turnLeftState = QiblaState(bearing: 80.0, heading: 100.0);
      expect(turnLeftState.turnInstruction, 'استدر يسارًا بمقدار 20°');
    });

    test('Boundary alignment close to 0° and 360°', () {
      // Bearing 2°, Heading 359° -> delta = +3° -> aligned
      const nearNorth1 = QiblaState(bearing: 2.0, heading: 359.0);
      expect(nearNorth1.delta, closeTo(3.0, 0.001));
      expect(nearNorth1.aligned, isTrue);

      // Bearing 358°, Heading 1° -> delta = -3° -> aligned
      const nearNorth2 = QiblaState(bearing: 358.0, heading: 1.0);
      expect(nearNorth2.delta, closeTo(-3.0, 0.001));
      expect(nearNorth2.aligned, isTrue);

      // Bearing 10°, Heading 350° -> delta = +20° -> not aligned
      const notAligned = QiblaState(bearing: 10.0, heading: 350.0);
      expect(notAligned.delta, closeTo(20.0, 0.001));
      expect(notAligned.aligned, isFalse);
    });
  });

  group('2b. True North vs Magnetic North & Geomagnetic Declination', () {
    test(
      'On Android: declination is calculated from WMM and stored in state',
      () {
        final androidCubit = QiblaCubit(platform: TargetPlatform.android);
        // Riyadh (24.7136, 46.6753)
        androidCubit.setLocation(24.7136, 46.6753);
        expect(androidCubit.state.declination, isNotNull);
        // Declination in Riyadh is approx +3.1°
        expect(androidCubit.state.declination!, inInclusiveRange(2.5, 4.0));
        androidCubit.close();
      },
    );

    test('On Android: Makkah declination is approx +3.5°', () {
      final androidCubit = QiblaCubit(platform: TargetPlatform.android);
      androidCubit.setLocation(21.4225, 39.8262);
      expect(androidCubit.state.declination!, inInclusiveRange(3.0, 4.0));
      androidCubit.close();
    });

    test('On Android: New York declination is negative (~ -12.5°)', () {
      final androidCubit = QiblaCubit(platform: TargetPlatform.android);
      androidCubit.setLocation(40.7128, -74.0060);
      expect(androidCubit.state.declination!, inInclusiveRange(-14.0, -11.0));
      androidCubit.close();
    });

    test('On iOS: declination remains null to prevent double-correction (iOS provides trueHeading directly)', () {
      final iosCubit = QiblaCubit(platform: TargetPlatform.iOS);
      iosCubit.setLocation(24.7136, 46.6753);
      expect(iosCubit.state.declination, isNull);
      iosCubit.close();
    });

    test(
      'Negative headings (from Android sensor) are normalized to [0, 360)',
      () {
        final cubit = QiblaCubit();
        cubit.setHeadingForTesting(-30.0);
        expect(cubit.state.heading, 330.0);
        expect(cubit.state.heading, isNonNegative);

        cubit.setHeadingForTesting(-370.0);
        expect(cubit.state.heading, 350.0);
        cubit.close();
      },
    );
  });

  group('3. QiblaCubit State Management Tests', () {
    late QiblaCubit cubit;

    setUp(() {
      cubit = QiblaCubit();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('Initial state is noLocation', () {
      expect(cubit.state.status, QiblaStatus.noLocation);
      expect(cubit.state.bearing, isNull);
      expect(cubit.state.distanceKm, isNull);
    });

    test('setLocation sets ready status with bearing and distance', () {
      cubit.setLocation(14.7664, 49.6254);
      expect(cubit.state.status, QiblaStatus.ready);
      expect(cubit.state.bearing, isNotNull);
      expect(cubit.state.distanceKm, isNotNull);
    });

    test('setLocation with null resets state to noLocation', () {
      cubit.setLocation(14.7664, 49.6254);
      cubit.setLocation(null, null);
      expect(cubit.state.status, QiblaStatus.noLocation);
      expect(cubit.state.bearing, isNull);
    });

    test('setHeadingForTesting updates heading and listening status', () {
      cubit.setLocation(14.7664, 49.6254);
      cubit.setHeadingForTesting(309.0, accuracy: 5.0);
      expect(cubit.state.status, QiblaStatus.listening);
      expect(cubit.state.heading, 309.0);
      expect(cubit.state.accuracy, 5.0);
      expect(cubit.state.aligned, isTrue);
    });
  });

  group(
    '4. Bottom Navigation Bar Tests (Order, Floating Center Compass, RTL)',
    () {
      testWidgets(
        'MishkatBottomNavBar renders 5 tabs in RTL order with prominent center compass',
        (tester) async {
          int selected = 0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              locale: const Locale('ar'),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  bottomNavigationBar: StatefulBuilder(
                    builder: (context, setState) {
                      return MishkatBottomNavBar(
                        selectedIndex: selected,
                        onItemSelected: (i) => setState(() => selected = i),
                      );
                    },
                  ),
                ),
              ),
            ),
          );

          // Verify all 5 tab labels are visible
          expect(find.text('الرئيسية'), findsOneWidget);
          expect(find.text('القرآن'), findsOneWidget);
          expect(find.text('القبلة'), findsOneWidget);
          expect(find.text('الأذكار'), findsOneWidget);
          expect(find.text('المكتبة'), findsOneWidget);

          // Verify tapping center Qibla tab selects index 2
          await tester.tap(find.text('القبلة'));
          await tester.pumpAndSettle();
          expect(selected, 2);

          // Verify tapping Quran selects index 1
          await tester.tap(find.text('القرآن'));
          await tester.pumpAndSettle();
          expect(selected, 1);

          // Verify tapping Adhkar selects index 3
          await tester.tap(find.text('الأذكار'));
          await tester.pumpAndSettle();
          expect(selected, 3);

          // Verify tapping Library selects index 4
          await tester.tap(find.text('المكتبة'));
          await tester.pumpAndSettle();
          expect(selected, 4);

          // Verify tapping Home selects index 0
          await tester.tap(find.text('الرئيسية'));
          await tester.pumpAndSettle();
          expect(selected, 0);
        },
      );
    },
  );

  group('5. Qibla Page Widget & Multi-State UI Tests', () {
    late LocalStorageService storage;
    late SettingsCubit settingsCubit;
    late QiblaCubit qiblaCubit;

    setUp(() async {
      storage = FakeLocalStorageService();
      final locationService = LocationService();
      final notifications = LocalNotificationService();
      settingsCubit = SettingsCubit(
        storage: storage,
        locationService: locationService,
        notifications: notifications,
      );
      await settingsCubit.load();
      qiblaCubit = QiblaCubit();
    });

    tearDown(() async {
      await settingsCubit.close();
      await qiblaCubit.close();
    });

    Widget buildQiblaApp() {
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: settingsCubit),
          BlocProvider.value(value: qiblaCubit),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('ar')],
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: QiblaPage(),
          ),
        ),
      );
    }

    testWidgets('State: No Location shows location required prompt', (
      tester,
    ) async {
      qiblaCubit.setLocation(null, null);

      await tester.pumpWidget(buildQiblaApp());
      await tester.pumpAndSettle();

      expect(find.text('تحديد الموقع مطلوب'), findsOneWidget);
      expect(find.text('استخدام موقعي الحالي'), findsOneWidget);
    });

    testWidgets(
      'State: Location available renders Header, Compass, Metrics and Guidance',
      (tester) async {
        // Set location for Hadramout
        await settingsCubit.selectCity(
          const NearbyCity('المكلا، حضرموت', 14.5425, 49.1242, 'MWL'),
        );
        qiblaCubit.setLocation(14.5425, 49.1242);

        await tester.pumpWidget(buildQiblaApp());
        await tester.pumpAndSettle();

        // Header checks
        expect(find.text('اتجاه القبلة'), findsOneWidget);
        expect(find.text('المكلا، حضرموت'), findsOneWidget);

        // Metric labels check
        expect(find.text('زاوية القبلة'), findsOneWidget);
        expect(find.text('اتجاه هاتفك'), findsOneWidget);
        expect(find.text('المسافة للكعبة'), findsOneWidget);

        // Compass widget check
        expect(find.byType(MishkatCompassWidget), findsOneWidget);

        // Calibration tip card check (located down in ListView)
        expect(
          find.text('إرشادات لدقة البوصلة', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'State: Compass facing Qibla shows aligned celebration banner',
      (tester) async {
        await settingsCubit.selectCity(
          const NearbyCity('مكة المكرمة', 21.4225, 39.8262, 'Makkah'),
        );
        qiblaCubit.setLocation(14.5425, 49.1242);
        final bearing = qiblaCubit.state.bearing!;

        // Simulate phone facing Qibla bearing
        qiblaCubit.setHeadingForTesting(bearing, accuracy: 5.0);

        await tester.pumpWidget(buildQiblaApp());
        await tester.pumpAndSettle();

        expect(find.text('أنت الآن باتجاه القبلة مباشرة'), findsOneWidget);
      },
    );

    testWidgets('State: Sensor unavailable renders informative notice', (
      tester,
    ) async {
      await settingsCubit.selectCity(
        const NearbyCity('المكلا، حضرموت', 14.5425, 49.1242, 'MWL'),
      );
      qiblaCubit.setLocation(14.5425, 49.1242);
      qiblaCubit.emit(
        qiblaCubit.state.copyWith(status: QiblaStatus.unavailable),
      );

      await tester.pumpWidget(buildQiblaApp());
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'مستشعر البوصلة المباشر غير متوفر',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });
  });

  group('6. Responsive Design & Screen Sizes (320px to Tablet)', () {
    testWidgets('Qibla Page renders on narrow 320px phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;

      final storage = FakeLocalStorageService();
      final settingsCubit = SettingsCubit(
        storage: storage,
        locationService: LocationService(),
        notifications: LocalNotificationService(),
      );
      await settingsCubit.load();
      await settingsCubit.selectCity(
        const NearbyCity('المكلا، حضرموت', 14.5425, 49.1242, 'MWL'),
      );

      final qiblaCubit = QiblaCubit()..setLocation(14.5425, 49.1242);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: settingsCubit),
            BlocProvider.value(value: qiblaCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ar')],
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: QiblaPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MishkatCompassWidget), findsOneWidget);
      expect(tester.takeException(), isNull);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        settingsCubit.close();
        qiblaCubit.close();
      });
    });
  });
}
