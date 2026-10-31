import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/app/app.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_oral_recitation_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';

class TestStorage implements LocalStorageService {
  final Map<String, dynamic> _store = {};
  @override
  Future<void> init() async {}
  @override
  Map<String, dynamic> readMap(String key) =>
      _store[key] is Map ? Map<String, dynamic>.from(_store[key]) : {};
  @override
  List<dynamic> readList(String key) =>
      _store[key] is List ? List<dynamic>.from(_store[key]) : [];
  @override
  int readInt(String key, [int fallback = 0]) =>
      _store[key] is num ? (_store[key] as num).toInt() : fallback;
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async =>
      _store[key] = Map<String, dynamic>.from(value);
  @override
  Future<void> writeList(String key, List<dynamic> value) async =>
      _store[key] = List<dynamic>.from(value);
  @override
  Future<void> writeInt(String key, int value) async => _store[key] = value;
  @override
  Future<void> remove(String key) async => _store.remove(key);
  @override
  Future<void> clear() async => _store.clear();
}

class TestAudioService implements QuranAudioService {
  final _state = StreamController<PlayerState>.broadcast();
  final _pos = StreamController<Duration>.broadcast();

  @override
  Stream<PlayerState> get playerState => _state.stream;
  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Duration? get duration => null;
  @override
  Duration get currentPosition => Duration.zero;
  @override
  bool get isPlaying => false;
  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async {
    await _state.close();
    await _pos.close();
  }
}

class TestNotifications implements LocalNotificationService {
  @override
  Future<bool> canSchedulePrecisely() async => true;

  @override
  Future<void> stopTest() async {}

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAll(
    List<ScheduledAppNotification> notifications,
  ) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showTest({
    required bool sound,
    required bool vibrate,
    String? soundName,
  }) async {}
}

class TestLocationService implements LocationService {
  @override
  Future<AppPosition> currentPosition() async => const AppPosition(
    latitude: 14.5425,
    longitude: 49.1242,
    label: 'المكلا، حضرموت',
    suggestedMethod: 'MWL',
  );

  @override
  NearbyCity closestCity(double latitude, double longitude) =>
      const NearbyCity('المكلا، حضرموت', 14.5425, 49.1242, 'MWL');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranRepository globalQuranRepo;
  late AdhkarRepository globalAdhkarRepo;
  late LibraryRepository globalLibraryRepo;

  setUpAll(() async {
    globalQuranRepo = QuranRepository();
    globalAdhkarRepo = AdhkarRepository();
    globalLibraryRepo = LibraryRepository();

    await globalQuranRepo.load();
    await globalAdhkarRepo.load();
    await globalLibraryRepo.loadCatalog();
  });

  testWidgets(
    'Navigating to Oral Recitation from QuranPage in MishkatApp opens without ProviderNotFoundException',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = TestStorage();
      await storage.init();
      await storage.writeMap(
        'settings',
        const AppSettings(
          city: 'المكلا، حضرموت',
          latitude: 14.5425,
          longitude: 49.1242,
          onboardingSeen: true,
          method: 'MWL',
          notificationsEnabled: false,
          keepAwake: false,
        ).toJson(),
      );

      final settingsCubit = SettingsCubit(
        storage: storage,
        locationService: TestLocationService(),
        notifications: TestNotifications(),
      );
      await settingsCubit.load();

      final khatmaCubit = KhatmaCubit(storage);

      // Boot real MishkatApp
      await tester.pumpWidget(
        MishkatApp(
          storage: storage,
          notifications: TestNotifications(),
          audioService: TestAudioService(),
          quranRepository: globalQuranRepo,
          adhkarRepository: globalAdhkarRepo,
          libraryRepository: globalLibraryRepo,
          settingsCubit: settingsCubit,
          khatmaCubit: khatmaCubit,
          speechService: MockSpeechRecognitionService(),
        ),
      );
      await tester.pumpAndSettle();

      // App starts on HomePage. Switch to Quran tab (Tab 1)
      final quranTab = find.text('القرآن');
      expect(quranTab, findsWidgets);
      await tester.tap(quranTab.first);
      await tester.pumpAndSettle();

      // Open the dedicated memorization destination, then start oral recitation.
      // Secondary practice tools intentionally live there to keep Quran home calm.
      final memorizationButton = find.text('لوحة التحفيظ');
      expect(memorizationButton, findsOneWidget);
      await tester.tap(memorizationButton);
      await tester.pumpAndSettle();

      final oralInfoButton = find.text('التسميع الذكي');
      expect(oralInfoButton, findsOneWidget);
      await tester.ensureVisible(oralInfoButton);
      await tester.tap(oralInfoButton);
      await tester.pumpAndSettle();

      // No plan exists in this scenario, so choose the default free range first.
      expect(find.text('تسميع حر'), findsOneWidget);
      final continueButton = find.text('متابعة إلى التسميع');
      expect(continueButton, findsOneWidget);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'تبقى الآيات مخفية أثناء القراءة، ثم تظهر بعد اكتمال كل آية مع تمييز مواضع الخطأ.',
        ),
        findsOneWidget,
      );
      expect(find.text('متاح ومدمج'), findsNothing);

      // Bottom sheet is now visible. Tap primary action to open Oral Recitation page
      final startOralButton = find.text('بدء التسميع الشفهي الآن');
      expect(startOralButton, findsOneWidget);
      await tester.tap(startOralButton);
      await tester.pumpAndSettle();

      // Verify Oral Recitation page is rendered without any ProviderNotFoundException
      expect(find.byType(QuranOralRecitationPage), findsOneWidget);
      expect(find.text('التسميع الشفهي الذكي'), findsOneWidget);
      expect(find.text('الفاتحة · الآيات 1 - 5'), findsOneWidget);
      expect(find.text('جاهز للتسميع'), findsOneWidget);
      expect(find.text('بدء التسميع'), findsOneWidget);

      // Verify cubit received real QuranRepository instance from MishkatApp root
      final innerContext = tester.element(find.text('التسميع الشفهي الذكي'));
      final cubit = innerContext.read<QuranOralRecitationCubit>();
      expect(cubit.quranRepository, same(globalQuranRepo));
      expect(cubit.state.lifecycle, OralRecitationLifecycle.ready);
      expect(cubit.state.targetWords.length, 17);
      expect(cubit.state.errorMessage, isNull);

      // Tap back / leave page to verify clean disposal
      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Verify we returned back to Quran tab
      expect(find.byType(QuranOralRecitationPage), findsNothing);
    },
  );
}
