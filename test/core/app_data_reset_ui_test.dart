import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/app/app.dart';
import 'package:mishkat_app/core/services/app_data_reset_service.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/services/offline_audio_download_controller.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_cubit.dart';
import 'package:mishkat_app/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_cubit.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/pages/settings_page.dart';
import 'package:mishkat_app/features/shell/presentation/pages/app_shell.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';

import '../features/quran_bookmarks_test.dart'
    show DummyAudioService, InMemoryLocalStorageService;

class _Notifications extends LocalNotificationService {
  int cancellations = 0;
  @override
  Future<void> cancelAll() async => cancellations++;
}

class _GatedDownloads extends OfflineAudioDownloadController {
  _GatedDownloads() : super(QuranAudioCacheService());
  final gate = Completer<void>();
  int clears = 0;

  @override
  Future<void> clearAllDownloads() async {
    clears++;
    await gate.future;
  }
}

class _Widgets extends HomeWidgetService {
  _Widgets(AdhkarRepository repository) : super(adhkarRepository: repository);
  @override
  bool get isSupportedPlatform => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final quranRepository = QuranRepository();
  final adhkarRepository = AdhkarRepository();
  final libraryRepository = LibraryRepository();

  setUpAll(() async {
    // Load real bundled content outside the widget test's fake clock.
    await Future.wait([
      quranRepository.load(),
      adhkarRepository.load(),
      libraryRepository.loadCatalog(),
    ]);
    // Ahem's square placeholder glyphs make Arabic prayer-card headers wider
    // than the real UI. Measure the actual bundled typography at phone width.
    final cairo = FontLoader('Cairo');
    for (final weight in ['Light', 'Regular', 'SemiBold', 'Bold', 'Black']) {
      cairo.addFont(rootBundle.load('assets/fonts/Cairo-$weight.ttf'));
    }
    await cairo.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('Settings erase resets the live app and dismisses its busy route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    notificationTapPayload.value = null;
    homeWidgetLaunchUri.value = null;
    const wakelockChannel =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      wakelockChannel,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    addTearDown(() => messenger.setMockMessageHandler(wakelockChannel, null));
    final storage = InMemoryLocalStorageService();
    await storage.writeInt('onboarding_version', 1);
    await storage.writeMap(
      'settings',
      const AppSettings(
        onboardingSeen: true,
        city: 'مكة المكرمة',
        latitude: 21.3891,
        longitude: 39.8579,
      ).toJson(),
    );
    final notifications = _Notifications();
    final settings = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: notifications,
    );
    await settings.load();
    final khatma = KhatmaCubit(storage, notifications: notifications);
    final downloads = _GatedDownloads();
    await tester.pumpWidget(
      MishkatApp(
        storage: storage,
        notifications: notifications,
        audioService: DummyAudioService(),
        quranRepository: quranRepository,
        adhkarRepository: adhkarRepository,
        libraryRepository: libraryRepository,
        settingsCubit: settings,
        khatmaCubit: khatma,
        offlineDownloads: downloads,
        homeWidgetService: _Widgets(adhkarRepository),
        initiallyShowOnboarding: storage.readInt('onboarding_version') < 1,
      ),
    );
    await tester.pumpAndSettle();
    final appContext = tester.element(find.byType(AppShell));
    final reset = appContext.read<AppDataResetService>();
    final qibla = appContext.read<QiblaCubit>();
    addTearDown(() async {
      if (!downloads.gate.isCompleted) downloads.gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await khatma.close();
      await qibla.close();
      downloads.dispose();
      notificationTapPayload.value = null;
      homeWidgetLaunchUri.value = null;
    });
    expect(find.byType(OnboardingPage), findsNothing);
    expect(tester.takeException(), isNull);

    // Seed the actual live providers, so the assertions below detect stale
    // feature instances as well as failed disk or navigation coordination.
    await reset.quran.openPage(42);
    await reset.quran.toggleAyahBookmark(262);
    await reset.adhkar.saveCustom(
      title: 'دعائي القديم',
      text: 'نص قديم',
      count: 3,
    );
    await reset.tasbih.setCustomDhikr('ذكري القديم', target: 7);
    await reset.tasbih.increment();
    await reset.tasbih.increment();
    await khatma.create(name: 'ختمتي القديمة', durationDays: 30, startPage: 1);
    await reset.library.toggleFavorite(reset.library.state.books.first.id);
    await reset.memorization.createPlan(
      title: 'حفظي القديم',
      startGlobalAyah: 1,
      endGlobalAyah: 7,
      dailyTarget: 1,
    );
    await tester.pumpAndSettle();
    expect(storage.readMap('quran')['bookmarks'], hasLength(1));
    expect(reset.tasbih.state.count, 2);
    expect(khatma.state.plans, hasLength(1));

    await tester.tap(find.byTooltip('الإعدادات').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('التنزيل والبيانات'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('التنزيل والبيانات'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('مسح جميع البيانات'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('مسح جميع البيانات'));
    await tester.pumpAndSettle();
    expect(find.text('مسح جميع البيانات؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'مسح البيانات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('جارٍ مسح البيانات…'), findsOneWidget);
    expect(reset.isResetting, isTrue);
    expect(downloads.clears, 1);
    expect(tester.takeException(), isNull);

    // The barrier must stay until async deletion completes.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('جارٍ مسح البيانات…'), findsOneWidget);
    notificationTapPayload.value = 'quran:kahf';
    homeWidgetLaunchUri.value = Uri.parse('mishkat://wird');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('جارٍ مسح البيانات…'), findsOneWidget);
    expect(reset.isResetting, isTrue);
    expect(reset.quran.state.currentPage, 42);
    expect(tester.takeException(), isNull);
    downloads.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('جارٍ مسح البيانات…'), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-skip')), findsOneWidget);
    expect(reset.isResetting, isFalse);
    expect(reset.generation, 1);
    expect(notifications.cancellations, 1);
    expect(storage.readInt('onboarding_version'), 0);
    expect(notificationTapPayload.value, isNull);
    expect(homeWidgetLaunchUri.value, isNull);

    final onboardingContext = tester.element(find.byType(OnboardingPage));
    expect(onboardingContext.read<AppDataResetService>(), same(reset));
    expect(onboardingContext.read<QuranCubit>(), same(reset.quran));
    expect(onboardingContext.read<AdhkarCubit>(), same(reset.adhkar));
    expect(onboardingContext.read<TasbihCubit>(), same(reset.tasbih));
    expect(onboardingContext.read<KhatmaCubit>(), same(khatma));
    expect(onboardingContext.read<LibraryCubit>(), same(reset.library));
    expect(
      onboardingContext.read<QuranMemorizationCubit>(),
      same(reset.memorization),
    );
    expect(settings.state.settings.hasLocation, isFalse);
    expect(reset.quran.state.currentPage, 1);
    expect(reset.quran.state.bookmarks, isEmpty);
    expect(reset.quran.state.data, isNotNull);
    expect(reset.adhkar.state.customItems, isEmpty);
    expect(reset.adhkar.state.categories, isNotEmpty);
    expect(reset.tasbih.state.count, 0);
    expect(reset.tasbih.state.customDhikrs, isEmpty);
    expect(khatma.state.plans, isEmpty);
    expect(reset.library.state.favorites, isEmpty);
    expect(reset.memorization.state.plans, isEmpty);
    expect(reset.shell.state.index, 0);
    expect(tester.takeException(), isNull);
  });
}
