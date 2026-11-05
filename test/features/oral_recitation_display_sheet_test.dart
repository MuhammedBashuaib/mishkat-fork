import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_mushaf.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_colors.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_oral_recitation_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _MemoryStorage implements LocalStorageService {
  final _values = <String, dynamic>{};
  @override
  Future<void> init() async {}
  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_values[key] as Map? ?? {});
  @override
  List<dynamic> readList(String key) =>
      List<dynamic>.from(_values[key] as List? ?? []);
  @override
  int readInt(String key, [int fallback = 0]) =>
      _values[key] as int? ?? fallback;
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async =>
      _values[key] = value;
  @override
  Future<void> writeList(String key, List<dynamic> value) async =>
      _values[key] = value;
  @override
  Future<void> writeInt(String key, int value) async => _values[key] = value;
  @override
  Future<void> remove(String key) async => _values.remove(key);
  @override
  Future<void> clear() async => _values.clear();
}

class _QuranRepository extends QuranRepository {
  @override
  Future<QuranData> load() async => QuranData(
    chapters: [
      QuranChapter(
        number: 1,
        name: 'الفاتحة',
        englishName: 'Al-Fatiha',
        revelationType: 'Meccan',
        page: 1,
        globalStart: 1,
        ayahs: const [
          'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
          'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
        ],
      ),
    ],
    juz: const [],
    pages: const [],
  );
}

class _OfflineSpeech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics {
  int stopCount = 0;
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();
  @override
  Future<void> stopListening() async {
    stopCount++;
    await super.stopListening();
  }
}

void main() {
  late _OfflineSpeech speech;
  late QuranMemorizationCubit memorization;
  late QuranOralRecitationCubit cubit;

  setUpAll(() async {
    await MushafLayoutRepository.instance.load();
    await OralRecitationMushaf.preloadCanonicalText();
  });

  Finder modeOption(OralRecitationMode mode) =>
      find.byKey(ValueKey('recitation-mode-${mode.name}'));

  Future<void> showPage(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool compact = false,
  }) async {
    speech = _OfflineSpeech();
    memorization = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: _MemoryStorage()),
    );
    await memorization.load();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _QuranRepository(),
      memorizationCubit: memorization,
    );
    await cubit.prepareSession(
      surahNumber: 1,
      startGlobalAyah: 1,
      endGlobalAyah: 2,
    );
    tester.view.physicalSize = compact
        ? const Size(640, 1280)
        : const Size(1170, 2532);
    tester.view.devicePixelRatio = compact ? 2 : 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(compact ? 1.6 : 1)),
          child: child!,
        ),
        home: QuranOralRecitationPage(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('recitation-display-options')));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    final close = find.byKey(const ValueKey('recitation-display-sheet-close'));
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await cubit.close();
    await speech.dispose();
    await memorization.close();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Display options use RTL rows with a single selected mode', (
    tester,
  ) async {
    await showPage(tester);
    await openSheet(tester);
    expect(find.text('طريقة عرض المصحف'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      find.byKey(const ValueKey('recitation-mode-locked-note')),
      findsNothing,
    );
    final hidden = modeOption(OralRecitationMode.hidden);
    final firstWord = modeOption(OralRecitationMode.firstWord);
    final reading = modeOption(OralRecitationMode.reading);
    expect(Directionality.of(tester.element(hidden)), TextDirection.rtl);
    expect(
      tester.getBottomLeft(hidden).dy,
      lessThan(tester.getTopLeft(firstWord).dy),
    );
    expect(
      tester.getBottomLeft(firstWord).dy,
      lessThan(tester.getTopLeft(reading).dy),
    );
    expect(tester.widget<Semantics>(hidden).properties.selected, isTrue);

    for (final mode in OralRecitationMode.values) {
      await tester.tap(modeOption(mode));
      await tester.pumpAndSettle();
      expect(cubit.state.mode, mode);
      for (final other in OralRecitationMode.values) {
        final semantics = tester
            .widget<Semantics>(modeOption(other))
            .properties;
        expect(semantics.selected, mode == other);
        expect(semantics.enabled, isTrue);
        expect(semantics.inMutuallyExclusiveGroup, isTrue);
      }
    }
    await closeSheet(tester);
    expect(find.text('طريقة عرض المصحف'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('Opening settings keeps capture active and modes locked', (
    tester,
  ) async {
    await showPage(tester);
    await cubit.startRecitation();
    await tester.pumpAndSettle();
    final stopsBefore = speech.stopCount;
    await openSheet(tester);
    expect(cubit.state.isListening, isTrue);
    expect(speech.isListening, isTrue);
    expect(speech.stopCount, stopsBefore);
    expect(
      find.byKey(const ValueKey('recitation-mode-locked-note')),
      findsOneWidget,
    );
    for (final mode in OralRecitationMode.values) {
      final option = modeOption(mode);
      final semantics = tester.widget<Semantics>(option).properties;
      expect(semantics.enabled, isFalse);
      expect(semantics.onTap, isNull);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(cubit.state.mode, OralRecitationMode.hidden);
    }
    await closeSheet(tester);
    expect(speech.isListening, isTrue);
    expect(speech.stopCount, stopsBefore);
    await disposePage(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Display sheet scrolls at 320dp with text 1.6 in ${brightness.name} mode',
      (tester) async {
        await showPage(tester, brightness: brightness, compact: true);
        await openSheet(tester);
        expect(tester.takeException(), isNull);
        final expectedColors = brightness == Brightness.light
            ? MishkatColors.light
            : MishkatColors.dark;
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
          expectedColors.surface,
        );
        final reading = modeOption(OralRecitationMode.reading);
        await tester.ensureVisible(reading);
        await tester.pumpAndSettle();
        await tester.tap(reading);
        await tester.pumpAndSettle();
        expect(cubit.state.mode, OralRecitationMode.reading);
        expect(tester.takeException(), isNull);
        await closeSheet(tester);
        expect(find.text('طريقة عرض المصحف'), findsNothing);
        expect(tester.takeException(), isNull);
        await disposePage(tester);
      },
    );
  }
}
