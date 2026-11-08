import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/app_data_reset_service.dart';
import 'package:mishkat_app/core/services/home_widget_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/services/offline_audio_download_controller.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_cubit.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_item.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_session.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/shell/presentation/cubit/shell_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_state.dart';

import '../features/quran_bookmarks_test.dart' show DummyAudioService;

class _Notifications extends LocalNotificationService {
  int cancellations = 0;
  @override
  Future<void> cancelAll() async => cancellations++;
}

class _Downloads extends OfflineAudioDownloadController {
  _Downloads() : super(QuranAudioCacheService());
  int clears = 0;
  Completer<void>? gate;
  @override
  Future<void> clearAllDownloads() async {
    clears++;
    await gate?.future;
  }
}

class _Widgets extends HomeWidgetService {
  _Widgets() : super(adhkarRepository: AdhkarRepository());
  AppSettings? settings;
  KhatmaPlan? plan;
  TasbihState? tasbih;
  @override
  Future<void> sync(AppSettings value) async => settings = value;
  @override
  Future<void> syncWird(KhatmaPlan? value) async => plan = value;
  @override
  Future<void> syncTasbih(TasbihState value) async => tasbih = value;
}

class _DelayedLocation extends LocationService {
  final result = Completer<AppPosition>();
  @override
  Future<AppPosition> currentPosition() => result.future;
}

class _DelayedMemorizationRepository extends QuranMemorizationRepository {
  _DelayedMemorizationRepository({required super.storage});
  final gate = Completer<void>();
  @override
  Future<void> saveData({
    required List<MemorizationPlan> plans,
    required Map<int, MemorizationItem> items,
    MemorizationSession? session,
    List<MemorizationReviewRecord>? history,
  }) async {
    await gate.future;
    await super.saveData(
      plans: plans,
      items: items,
      session: session,
      history: history,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalStorageService storage;
  late SettingsCubit settings;
  late QuranCubit quran;
  late QuranMemorizationCubit memorization;
  late AdhkarCubit adhkar;
  late TasbihCubit tasbih;
  late KhatmaCubit khatma;
  late LibraryCubit library;
  late ShellCubit shell;
  late _Downloads downloads;
  late _Widgets widgets;
  late _Notifications notifications;

  AppDataResetService coordinator() => AppDataResetService(
    settings: settings,
    quran: quran,
    memorization: memorization,
    adhkar: adhkar,
    tasbih: tasbih,
    khatma: khatma,
    library: library,
    shell: shell,
    downloads: downloads,
    widgets: widgets,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mishkat-reset-');
    storage = LocalStorageService(directory: directory);
    await storage.init();
    notifications = _Notifications();
    settings = SettingsCubit(
      storage: storage,
      locationService: LocationService(),
      notifications: notifications,
    );
    await settings.load();
    quran = QuranCubit(
      repository: QuranRepository(),
      storage: storage,
      audio: DummyAudioService(),
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    memorization = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: storage),
    );
    adhkar = AdhkarCubit(AdhkarRepository(), storage);
    tasbih = TasbihCubit(storage);
    khatma = KhatmaCubit(storage);
    library = LibraryCubit(LibraryRepository(), storage);
    shell = ShellCubit();
    downloads = _Downloads();
    widgets = _Widgets();
    await Future.wait([
      quran.load(),
      memorization.load(),
      adhkar.load(),
      library.load(),
    ]);
  });

  tearDown(() async {
    await Future.wait([
      settings.close(),
      quran.close(),
      memorization.close(),
      adhkar.close(),
      tasbih.close(),
      khatma.close(),
      library.close(),
      shell.close(),
    ]);
    downloads.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'erase resets every live feature and later writes cannot resurrect data',
    () async {
      await settings.selectCity(LocationService.cities.first);
      await quran.openPage(42);
      await quran.toggleAyahBookmark(10);
      quran.search('الرحمن');
      await adhkar.saveCustom(title: 'دعائي القديم', text: 'نص قديم', count: 3);
      await tasbih.setCustomDhikr('ذكري القديم', target: 7);
      for (var i = 0; i < 5; i++) {
        await tasbih.increment();
      }
      await khatma.create(name: 'ختمة قديمة', durationDays: 30, startPage: 1);
      await library.toggleFavorite(library.state.books.first.id);
      await memorization.createPlan(
        title: 'حفظ قديم',
        startGlobalAyah: 1,
        endGlobalAyah: 7,
        dailyTarget: 1,
      );
      shell.select(4);
      widgets.plan = khatma.state.active;
      final reset = coordinator();
      addTearDown(reset.dispose);

      await reset.clearAllData();

      expect(reset.generation, 1);
      expect(reset.isResetting, isFalse);
      expect(downloads.clears, 1);
      expect(notifications.cancellations, 1);
      expect(settings.state.settings.hasLocation, isFalse);
      expect(quran.state.currentPage, 1);
      expect(quran.state.lastRead, isNull);
      expect(quran.state.bookmarks, isEmpty);
      expect(quran.state.query, isEmpty);
      expect(quran.state.data, isNotNull);
      expect(adhkar.state.customItems, isEmpty);
      expect(adhkar.state.progress, isEmpty);
      expect(adhkar.state.categories, isNotEmpty);
      expect(tasbih.state.count, 0);
      expect(tasbih.state.total, 0);
      expect(tasbih.state.customDhikrs, isEmpty);
      expect(khatma.state.plans, isEmpty);
      expect(memorization.state.plans, isEmpty);
      expect(memorization.state.items, isEmpty);
      expect(memorization.state.history, isEmpty);
      expect(library.state.favorites, isEmpty);
      expect(library.state.books, isNotEmpty);
      expect(shell.state.index, 0);
      expect(widgets.plan, isNull);
      expect(widgets.tasbih!.count, 0);
      expect(widgets.settings!.hasLocation, isFalse);

      await tasbih.increment();
      await quran.toggleAyahBookmark(2);
      final reopened = LocalStorageService(directory: directory);
      await reopened.init();
      final reopenedTasbih = TasbihCubit(reopened);
      addTearDown(reopenedTasbih.close);
      expect(reopenedTasbih.state.count, 1);
      expect(reopenedTasbih.state.total, 1);
      expect(reopenedTasbih.state.customDhikrs, isEmpty);
      expect(reopened.readMap('khatma'), isEmpty);
      expect(reopened.readMap('quran_memorization'), isEmpty);
      expect(reopened.readMap('quran')['bookmarks'], hasLength(1));
      expect(
        (reopened.readMap('quran')['bookmarks'] as List)
            .single['point']['g'],
        2,
      );
    },
  );

  test('erase waits for an in-flight memorization save including its legacy history', () async {
    await memorization.close();
    final repository = _DelayedMemorizationRepository(storage: storage);
    memorization = QuranMemorizationCubit(repository: repository);
    final saving = memorization.createPlan(
      title: 'متأخر',
      startGlobalAyah: 1,
      endGlobalAyah: 7,
      dailyTarget: 1,
    );
    final reset = coordinator();
    addTearDown(reset.dispose);
    final erasing = reset.clearAllData();
    await Future<void>.delayed(Duration.zero);
    expect(reset.isResetting, isTrue);
    expect(reset.generation, 0);
    repository.gate.complete();
    await Future.wait([saving, erasing]);
    expect(memorization.state.plans, isEmpty);
    final reopened = LocalStorageService(directory: directory);
    await reopened.init();
    expect(reopened.readMap('quran_memorization'), isEmpty);
    expect(reopened.readList('quran_memorization_history'), isEmpty);
  });

  test('duplicate erase requests share work and a failed erase keeps feature state', () async {
    await tasbih.increment();
    downloads.gate = Completer<void>();
    final reset = coordinator();
    addTearDown(reset.dispose);
    final first = reset.clearAllData();
    final second = reset.clearAllData();
    final failures = [
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ];
    await Future<void>.delayed(Duration.zero);
    downloads.gate!.completeError(StateError('simulated erase failure'));
    await Future.wait(failures);
    expect(downloads.clears, 1);
    expect(reset.generation, 0);
    expect(tasbih.state.count, 1);
    expect(storage.readMap('tasbihSessionV2')['count'], 1);
  });

  test(
    'a late location response cannot restore location after reset',
    () async {
      await settings.close();
      final location = _DelayedLocation();
      settings = SettingsCubit(
        storage: storage,
        locationService: location,
        notifications: notifications,
      );
      await settings.load();
      final locating = settings.useCurrentLocation();
      await settings.clearAllData();
      location.result.complete(
        const AppPosition(
          latitude: 21.4,
          longitude: 39.8,
          label: 'مكة',
          suggestedMethod: 'Makkah',
        ),
      );
      await locating;
      expect(settings.state.settings.hasLocation, isFalse);
      expect(storage.readMap('settings'), isEmpty);
    },
  );
}
