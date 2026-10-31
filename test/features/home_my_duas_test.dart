import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_notification_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/location_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/adhkar/data/models/adhkar_models.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';
import 'package:mishkat_app/features/adhkar/presentation/pages/adhkar_reader_page.dart';
import 'package:mishkat_app/features/home/presentation/cubit/home_cubit.dart';
import 'package:mishkat_app/features/home/presentation/pages/home_page.dart';
import 'package:mishkat_app/features/home/presentation/models/home_dhikr_moment.dart';
import 'package:mishkat_app/features/khatma/presentation/cubit/khatma_cubit.dart';
import 'package:mishkat_app/features/qibla/presentation/cubit/qibla_cubit.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';
import 'package:mishkat_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mishkat_app/features/shell/presentation/cubit/shell_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_cubit.dart';
import 'package:mishkat_app/features/tasbih/presentation/pages/tasbih_page.dart';

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

class FakeLocationService implements LocationService {
  @override
  Future<AppPosition> currentPosition() async {
    return const AppPosition(
      latitude: 21.4225,
      longitude: 39.8262,
      label: 'مكة المكرمة',
      suggestedMethod: 'MWL',
    );
  }

  @override
  NearbyCity closestCity(double latitude, double longitude) {
    return const NearbyCity('مكة المكرمة', 21.4225, 39.8262, 'MWL', 0);
  }
}

class FakeNotificationService implements LocalNotificationService {
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

class FakeQuranAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

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
    await _stateController.close();
    await _positionController.close();
  }
}

class FakeAdhkarRepository extends AdhkarRepository {
  @override
  Future<List<AdhkarCategory>> load() async => const [
    AdhkarCategory(id: 1, name: 'أذكار الصباح', items: []),
    AdhkarCategory(id: 133, name: 'أذكار المساء', items: []),
    AdhkarCategory(id: 2, name: 'أذكار النوم', items: []),
  ];
}

Future<void> _loadFonts() async {
  final fontFile = File(
    '/Users/muhammedbashuaib/Developer/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (fontFile.existsSync()) {
    final fontData = fontFile.readAsBytesSync();
    final fontLoader = FontLoader('MaterialIcons');
    fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
    await fontLoader.load();
  }

  final cairoFiles = [
    'assets/fonts/Cairo-Regular.ttf',
    'assets/fonts/Cairo-SemiBold.ttf',
    'assets/fonts/Cairo-Bold.ttf',
    'assets/fonts/Cairo-Light.ttf',
    'assets/fonts/Cairo-Black.ttf',
  ];
  final cairoLoader = FontLoader('Cairo');
  for (final path in cairoFiles) {
    final file = File(path);
    if (file.existsSync()) {
      cairoLoader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
  }
  await cairoLoader.load();

  final arabicFile = File('/System/Library/Fonts/SFArabic.ttf');
  if (arabicFile.existsSync()) {
    final fontData = arabicFile.readAsBytesSync();
    final fontLoader = FontLoader('SF Arabic');
    fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
    await fontLoader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocalStorageService storage;
  late FakeAdhkarRepository adhkarRepo;
  late AdhkarCubit adhkarCubit;
  late SettingsCubit settingsCubit;
  late HomeCubit homeCubit;
  late QuranRepository quranRepo;
  late QuranCubit quranCubit;
  late FakeQuranAudioService audioService;
  late ShellCubit shellCubit;
  late QiblaCubit qiblaCubit;
  late TasbihCubit tasbihCubit;
  late KhatmaCubit khatmaCubit;
  late DateTime now;

  setUpAll(() async {
    await _loadFonts();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (message) async => ['wifi'],
        );

    quranRepo = QuranRepository();
    await quranRepo.load();
  });

  setUp(() async {
    storage = FakeLocalStorageService();
    adhkarRepo = FakeAdhkarRepository();
    adhkarCubit = AdhkarCubit(adhkarRepo, storage);
    await adhkarCubit.load();

    const settings = AppSettings(
      city: 'مكة المكرمة',
      latitude: 21.4225,
      longitude: 39.8262,
      onboardingSeen: true,
      method: 'MWL',
    );
    await storage.writeMap('settings', settings.toJson());

    settingsCubit = SettingsCubit(
      storage: storage,
      locationService: FakeLocationService(),
      notifications: FakeNotificationService(),
    );
    await settingsCubit.load();

    now = DateTime(2026, 10, 31, 9);
    homeCubit = HomeCubit(settingsCubit.state.settings, now: () => now);

    audioService = FakeQuranAudioService();
    quranCubit = QuranCubit(
      repository: quranRepo,
      storage: storage,
      audio: audioService,
      reciter: 'alafasy',
      fontSize: 22.0,
    );
    await quranCubit.load();

    shellCubit = ShellCubit();
    qiblaCubit = QiblaCubit()..setLocation(21.4225, 39.8262);
    tasbihCubit = TasbihCubit(storage);
    khatmaCubit = KhatmaCubit(storage);
  });

  tearDown(() async {
    await homeCubit.close();
    await settingsCubit.close();
    await adhkarCubit.close();
    await quranCubit.close();
    await audioService.dispose();
    await shellCubit.close();
    await qiblaCubit.close();
    await tasbihCubit.close();
    await khatmaCubit.close();
  });

  Widget buildApp() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: settingsCubit),
        BlocProvider.value(value: shellCubit),
        BlocProvider.value(value: homeCubit),
        BlocProvider.value(value: adhkarCubit),
        BlocProvider.value(value: quranCubit),
        BlocProvider.value(value: qiblaCubit),
        BlocProvider.value(value: tasbihCubit),
        BlocProvider.value(value: khatmaCubit),
      ],
      child: MaterialApp(
        theme: AppTheme.light(1.0),
        locale: const Locale('ar'),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HomePage(),
        ),
      ),
    );
  }

  testWidgets(
    'My Duas section on Home Page: empty state, adding dua, counter, and latest 3 duas',
    (tester) async {
      tester.view.physicalSize = const Size(840, 3200);
      tester.view.devicePixelRatio = 2.0;

      // 1. Initial State: Empty state
      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('أدعيتي'), findsOneWidget);
      expect(find.text('إضافة دعاء'), findsOneWidget);
      expect(find.text('لا توجد أدعية مضافة بعد'), findsOneWidget);
      expect(find.text('إضافة أول دعاء'), findsOneWidget);

      // 2. Add first dua via shortcut
      await tester.tap(find.text('إضافة دعاء'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('إضافة دعاء جديد'), findsOneWidget);
      expect(find.text('حفظ في أدعيتي'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'عنوان الدعاء (اختياري)'),
        'دعاء تيسير الأمور',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'نص الدعاء أو الذكر *'),
        'اللهم لا سهل إلا ما جعلته سهلا وأنت تجعل الحزن إذا شئت سهلا',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'عدد مرات التكرار'),
        '3',
      );

      await tester.tap(find.text('حفظ في أدعيتي'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(adhkarCubit.state.customItems.length, 1);
      expect(adhkarCubit.state.customItems.first.title, 'دعاء تيسير الأمور');
      expect(
        find.text('دعاء تيسير الأمور', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text(
          'اللهم لا سهل إلا ما جعلته سهلا وأنت تجعل الحزن إذا شئت سهلا',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.text('3×', skipOffstage: false), findsOneWidget);

      // 3. Increment counter by tapping repetition badge
      await tester.tap(find.text('3×', skipOffstage: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 / 3', skipOffstage: false), findsOneWidget);

      // 4. Add 4 more duas (total 5) and verify only latest 3 are shown
      await adhkarCubit.saveCustom(
        title: 'الدعاء الثاني',
        text: 'اللهم اهدني وسددني',
        count: 1,
      );
      await adhkarCubit.saveCustom(
        title: 'الدعاء الثالث',
        text: 'يا مقلب القلوب ثبت قلبي على دينك',
        count: 1,
      );
      await adhkarCubit.saveCustom(
        title: 'الدعاء الرابع',
        text: 'اللهم إني أسألك الهدى والتقى والعفاف والغنى',
        count: 1,
      );
      await adhkarCubit.saveCustom(
        title: 'الدعاء الخامس',
        text: 'اللهم إنك عفو تحب العفو فاعف عني',
        count: 1,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The latest 3 are: الخامس, الرابع, الثالث
      expect(find.text('الدعاء الخامس', skipOffstage: false), findsOneWidget);
      expect(find.text('الدعاء الرابع', skipOffstage: false), findsOneWidget);
      expect(find.text('الدعاء الثالث', skipOffstage: false), findsOneWidget);

      // Older ones (دعاء تيسير الأمور, الدعاء الثاني) are NOT displayed among the 3 cards
      expect(find.text('دعاء تيسير الأمور', skipOffstage: false), findsNothing);
      expect(find.text('الدعاء الثاني', skipOffstage: false), findsNothing);

      // Shows total link
      expect(
        find.text('عرض جميع أدعيتي (5)', skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('Home Page exposes a shortcut to the tasbih session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('المسبحة'), findsOneWidget);
    await tester.tap(find.text('المسبحة'));
    await tester.pumpAndSettle();

    expect(find.text('هدف الجلسة'), findsOneWidget);
    expect(find.text('اضغط للتسبيح'), findsOneWidget);
  });

  for (final hour in [0, 5, 12, 13, 14, 15, 16, 22]) {
    testWidgets('daily dhikr at $hour opens its displayed destination', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(840, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      now = DateTime(2026, 10, 31, hour);
      homeCubit.refresh();
      final moment = HomeDhikrMoment.forTime(now);
      // Start with a different chapter and dhikr to catch stale selections.
      adhkarCubit.select(0);
      await tasbihCubit.selectDhikr('allahu_akbar');
      await tasbihCubit.increment();
      await tester.pumpWidget(buildApp());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(moment.title));
      await tester.pumpAndSettle();

      if (moment.categoryId != null) {
        expect(find.byType(AdhkarReaderPage), findsOneWidget);
        expect(adhkarCubit.state.selectedId, moment.categoryId);
        expect(adhkarCubit.state.selected?.name, moment.title);
        expect(tasbihCubit.state.count, 1);
      } else {
        expect(find.byType(TasbihPage), findsOneWidget);
        expect(tasbihCubit.state.dhikrId, moment.dhikrId);
        expect(tasbihCubit.state.dhikr.text, moment.title);
        expect(tasbihCubit.state.count, 0);
        expect(tasbihCubit.state.total, 1);
        expect(adhkarCubit.state.selectedId, 0);
      }
    });
  }

  testWidgets('daily dhikr updates across time boundaries without a location', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    now = DateTime(2026, 10, 31, 11, 59, 59);
    homeCubit.updateSettings(const AppSettings());
    await tester.pumpWidget(buildApp());
    expect(find.text('أذكار الصباح'), findsOneWidget);

    now = DateTime(2026, 10, 31, 12);
    homeCubit.refresh();
    await tester.pumpAndSettle();
    expect(find.text('أذكار الصباح'), findsNothing);
    expect(find.text('سبحان الله'), findsOneWidget);

    for (final hour in [13, 14, 16, 22, 5]) {
      now = DateTime(2026, 11, 1, hour);
      homeCubit.refresh();
      await tester.pumpAndSettle();
      expect(find.text(HomeDhikrMoment.forTime(now).title), findsOneWidget);
    }
  });

  testWidgets('opening the same suggested dhikr preserves its session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    now = DateTime(2026, 10, 31, 12);
    homeCubit.refresh();
    await tasbihCubit.increment();
    await tasbihCubit.setTarget(50);
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('سبحان الله'));
    await tester.pumpAndSettle();
    expect(find.byType(TasbihPage), findsOneWidget);
    expect(tasbihCubit.state.count, 1);
    expect(tasbihCubit.state.target, 50);
  });
}
