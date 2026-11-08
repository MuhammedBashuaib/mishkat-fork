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
import 'package:mishkat_app/features/library/data/models/library_models.dart';
import 'package:mishkat_app/features/library/data/repositories/library_repository.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_cubit.dart';
import 'package:mishkat_app/features/library/presentation/cubit/library_state.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_state.dart';
import 'package:mishkat_app/features/shell/presentation/cubit/shell_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_state.dart';

import '../features/quran_bookmarks_test.dart' show DummyAudioService;

/// Pause after erasing the real store but before reset may replace live state.
/// A stale producer writing in this interval must not resurrect durable data.
class _BlockedClearStorage extends LocalStorageService {
  _BlockedClearStorage({required super.directory});

  final erased = Completer<void>();
  final allowClearToReturn = Completer<void>();

  @override
  Future<void> clear() async {
    await super.clear();
    erased.complete();
    await allowClearToReturn.future;
  }
}

class _DelayedNotifications extends LocalNotificationService {
  final precisionRequested = Completer<void>();
  final precisionResult = Completer<bool>();
  int cancellations = 0;
  final schedules = <List<ScheduledAppNotification>>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> canSchedulePrecisely() {
    if (!precisionRequested.isCompleted) precisionRequested.complete();
    return precisionResult.future;
  }

  @override
  Future<void> scheduleAll(List<ScheduledAppNotification> notifications) async {
    schedules.add(List.of(notifications));
  }

  @override
  Future<void> cancelAll() async => cancellations++;
}

const _book = LibraryBook(
  id: 'pending-book',
  title: 'كتاب الاختبار',
  author: 'مؤلف',
  category: 'أذكار',
  description: '',
  contentPath: 'pending-book.json',
  contentType: 'entries',
  itemLabel: 'ذكر',
  availableItems: 1,
  expectedItems: 1,
  sourceName: '',
  sourceUrl: '',
);

class _DelayedBookRepository extends LibraryRepository {
  final bookRequested = Completer<void>();
  final bookResult = Completer<List<LibraryEntry>>();

  @override
  Future<List<LibraryBook>> loadCatalog() async => [_book];

  @override
  Future<List<LibraryEntry>> loadBook(LibraryBook book) {
    bookRequested.complete();
    return bookResult.future;
  }
}

class _Downloads extends OfflineAudioDownloadController {
  _Downloads() : super(QuranAudioCacheService());

  @override
  Future<void> clearAllDownloads() async {}
}

class _Widgets extends HomeWidgetService {
  _Widgets() : super(adhkarRepository: AdhkarRepository());

  @override
  Future<void> sync(AppSettings settings) async {}
  @override
  Future<void> syncWird(KhatmaPlan? plan) async {}
  @override
  Future<void> syncTasbih(TasbihState state) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late _BlockedClearStorage storage;
  late _DelayedNotifications notifications;
  late _DelayedBookRepository books;
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
  late AppDataResetService reset;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mishkat-reset-race-');
    storage = _BlockedClearStorage(directory: directory);
    await storage.init();
    notifications = _DelayedNotifications();
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
    books = _DelayedBookRepository();
    library = LibraryCubit(books, storage);
    shell = ShellCubit();
    downloads = _Downloads();
    widgets = _Widgets();
    reset = AppDataResetService(
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
    await Future.wait([
      quran.load(),
      memorization.load(),
      adhkar.load(),
      library.load(),
    ]);
  });

  tearDown(() async {
    reset.dispose();
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

  for (final fails in [false, true]) {
    test('a delayed precision ${fails ? 'failure' : 'result'} cannot schedule '
        'or alter settings while reset is clearing storage', () async {
      final enabling = settings.setNotificationsEnabled(true);
      await notifications.precisionRequested.future;
      final erasing = reset.clearAllData();
      await storage.erased.future;

      // Keep old settings visible until erase completes: equality checks
      // alone cannot distinguish this response from the current generation.
      expect(settings.state.settings.notificationsEnabled, isTrue);
      expect(storage.readMap('settings'), isEmpty);
      expect(notifications.cancellations, 1);
      final stateBeforeResponse = settings.state;
      if (fails) {
        notifications.precisionResult.completeError(
          StateError('delayed platform response'),
        );
      } else {
        notifications.precisionResult.complete(true);
      }
      await enabling;

      expect(notifications.schedules, isEmpty);
      expect(settings.state, stateBeforeResponse);
      storage.allowClearToReturn.complete();
      await erasing;
      expect(settings.state.status, SettingsStatus.ready);
      expect(settings.state.settings.notificationsEnabled, isFalse);
      expect(notifications.schedules, isEmpty);
      final reopened = LocalStorageService(directory: directory);
      await reopened.init();
      expect(reopened.readMap('settings'), isEmpty);
    });
  }

  test(
    'book loading completed during erase cannot resurrect library history',
    () async {
      await library.toggleFavorite(_book.id);
      await library.saveReadingPosition(_book.id, 'old-entry');
      final opening = library.openBook(_book);
      await books.bookRequested.future;
      final erasing = reset.clearAllData();
      await storage.erased.future;
      expect(reset.isResetting, isTrue);
      expect(library.state.favorites, contains(_book.id));
      expect(storage.readMap('library'), isEmpty);

      books.bookResult.complete(const [
        LibraryEntry(
          id: 'late-entry',
          number: 1,
          title: 'ذكر',
          chapter: '',
          text: 'سبحان الله',
          reference: '',
          sourceUrl: '',
        ),
      ]);
      await opening;
      expect(storage.readMap('library'), isEmpty);

      storage.allowClearToReturn.complete();
      await erasing;
      expect(library.state.status, LibraryStatus.ready);
      expect(library.state.books, [_book]);
      expect(library.state.selectedBook, isNull);
      expect(library.state.entries, isEmpty);
      expect(library.state.history, isEmpty);
      expect(library.state.favorites, isEmpty);
      expect(library.state.readingPositions, isEmpty);
      final reopened = LocalStorageService(directory: directory);
      await reopened.init();
      expect(reopened.readMap('library'), isEmpty);
    },
  );
}
