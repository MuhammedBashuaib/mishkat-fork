import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_oral_recitation_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_mushaf.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_range_sheet.dart';

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

class _OfflineSpeech extends MockSpeechRecognitionService
    implements OfflineSpeechDiagnostics {
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();
}

void main() {
  late QuranRepository repository;
  late QuranData quran;

  setUpAll(() async {
    repository = QuranRepository();
    quran = await repository.load();
    await MushafLayoutRepository.instance.load();
    await OralRecitationMushaf.preloadCanonicalText();
  });

  Future<List<OralRecitationSelection>> openRangeSheet(
    WidgetTester tester, {
    int initialSurah = 1,
  }) async {
    final selections = <OralRecitationSelection>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => OralRecitationRangeSheet(
                  quranData: quran,
                  initialSurah: initialSurah,
                  onSelected: selections.add,
                ),
              ),
              child: const Text('اختر نطاق التسميع'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('اختر نطاق التسميع'));
    await tester.pumpAndSettle();
    return selections;
  }

  Future<void> enterPages(
    WidgetTester tester,
    String first,
    String last,
  ) async {
    await tester.tap(find.text('الصفحات'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('free-start-page')), first);
    await tester.enterText(find.byKey(const Key('free-end-page')), last);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.text('متابعة إلى التسميع');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('whole-surah selection keeps its canonical ayah boundaries', (
    tester,
  ) async {
    final selections = await openRangeSheet(tester, initialSurah: 114);
    expect(find.byKey(const ValueKey('free-surah-114')), findsOneWidget);
    expect(find.text('السورة كاملة'), findsOneWidget);
    await tester.tap(find.text('السورة كاملة'));
    await tester.pumpAndSettle();
    await submit(tester);

    final selected = selections.single;
    expect(selected.surahNumber, 114);
    expect(selected.startGlobalAyah, 6231);
    expect(selected.endGlobalAyah, 6236);
    expect(selected.startPage, isNull);
    expect(selected.endPage, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one page selects its complete canonical ayah range', (
    tester,
  ) async {
    final selections = await openRangeSheet(tester);
    await enterPages(tester, '1', '1');
    await submit(tester);

    final selected = selections.single;
    expect(selected.surahNumber, 1);
    expect(selected.startPage, 1);
    expect(selected.endPage, 1);
    expect(selected.startGlobalAyah, 1);
    expect(selected.endGlobalAyah, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page range crosses surahs and accepts Arabic and Persian digits',
    (tester) async {
      final selections = await openRangeSheet(tester, initialSurah: 114);
      await enterPages(tester, '١', '۲');
      await submit(tester);

      final selected = selections.single;
      expect(selected.surahNumber, 1);
      expect(selected.startPage, 1);
      expect(selected.endPage, 2);
      expect(selected.startGlobalAyah, 1);
      expect(selected.endGlobalAyah, 12);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('last mushaf page includes all three surahs through ayah 6236', (
    tester,
  ) async {
    final selections = await openRangeSheet(tester);
    await enterPages(tester, '٦٠٤', '۶۰۴');
    await submit(tester);

    final selected = selections.single;
    expect(selected.surahNumber, 112);
    expect(selected.startPage, 604);
    expect(selected.endPage, 604);
    expect(selected.startGlobalAyah, 6222);
    expect(selected.endGlobalAyah, 6236);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in <(String, String, String)>[
    ('empty', '', ''),
    ('nonnumeric', 'abc', '2'),
    ('zero start', '0', '2'),
    ('reversed', '3', '2'),
    ('start out of bounds', '605', '605'),
    ('end out of bounds', '1', '٦٠٥'),
  ]) {
    testWidgets('invalid ${invalid.$1} page range cannot start a session', (
      tester,
    ) async {
      final selections = await openRangeSheet(tester);
      await enterPages(tester, invalid.$2, invalid.$3);
      await submit(tester);

      expect(selections, isEmpty);
      expect(find.byType(OralRecitationRangeSheet), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The same form remains usable after a validation error.
      await tester.enterText(find.byKey(const Key('free-start-page')), '1');
      await tester.enterText(find.byKey(const Key('free-end-page')), '1');
      await submit(tester);
      expect(selections.single.startPage, 1);
      expect(selections.single.endPage, 1);
    });
  }

  testWidgets('page range remains usable on a narrow screen with keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    final selections = await openRangeSheet(tester);
    await tester.tap(find.text('الصفحات'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('free-start-page')), '603');
    await tester.enterText(find.byKey(const Key('free-end-page')), '604');
    await submit(tester);

    expect(selections.single.startPage, 603);
    expect(selections.single.endPage, 604);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finishing selected page opens its report without tapping end', (
    tester,
  ) async {
    final speech = _OfflineSpeech();
    final memorization = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: _MemoryStorage()),
    );
    await memorization.load();
    final cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: repository,
      memorizationCubit: memorization,
    );
    await cubit.prepareSession(surahNumber: 1, startPage: 1, endPage: 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: QuranOralRecitationPage(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('بدء التسميع'));
    await tester.pump();

    final pageText = quran.chapter(1).ayahs.join(' ');
    speech.emitTranscript(pageText);
    await tester.pump();
    expect(cubit.state.summary, isNull);
    expect(find.text('أتممت المقطع، بارك الله فيك'), findsNothing);

    speech.emitTranscript(pageText, isFinal: true);
    await tester.pumpAndSettle();

    expect(cubit.state.summary, isNotNull);
    expect(cubit.state.summary!.startPage, 1);
    expect(cubit.state.summary!.endPage, 1);
    expect(cubit.state.summary!.coveragePercentage, 100);
    expect(speech.isListening, isFalse);
    expect(find.text('أتممت المقطع، بارك الله فيك'), findsOneWidget);
    expect(find.text('بدء التسميع'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await cubit.close();
    await speech.dispose();
    await memorization.close();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
