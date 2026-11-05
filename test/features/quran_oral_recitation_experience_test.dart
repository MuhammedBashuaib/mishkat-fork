import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
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
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_word_page.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/oral_recitation_mushaf.dart';

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
  final levels = StreamController<double>.broadcast(sync: true);
  final processing = StreamController<bool>.broadcast(sync: true);
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => levels.stream;
  @override
  Stream<bool> get processingStream => processing.stream;
  @override
  Future<void> dispose() async {
    await levels.close();
    await processing.close();
    await super.dispose();
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

  OralRecitationWordsPainter wordPainter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const Key('oral-word-page-paint')),
              )
              .painter!
          as OralRecitationWordsPainter;

  Set<int> maskedGlobals(WidgetTester tester) =>
      wordPainter(tester).words
          .where((word) => !word.visible)
          .map((word) => word.globalAyah)
          .toSet();

  Future<void> openDisplayOptions(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('recitation-display-options')));
    await tester.pumpAndSettle();
  }

  Future<void> closeDisplayOptions(WidgetTester tester) async {
    final choice = find.byKey(const ValueKey('recitation-mode-hidden'));
    if (choice.evaluate().isNotEmpty) {
      Navigator.of(tester.element(choice)).pop();
      await tester.pumpAndSettle();
    }
  }

  Future<void> selectMode(WidgetTester tester, OralRecitationMode mode) async {
    await openDisplayOptions(tester);
    await tester.tap(find.byKey(ValueKey('recitation-mode-${mode.name}')));
    await tester.pumpAndSettle();
    await closeDisplayOptions(tester);
  }

  Future<void> createSession() async {
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
  }

  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await cubit.close();
    await speech.dispose();
    await memorization.close();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> showPage(WidgetTester tester, {bool compact = false}) async {
    await createSession();
    await cubit.prepareSession(
      surahNumber: 1,
      startGlobalAyah: 1,
      endGlobalAyah: 2,
      planId: 'practice-plan',
    );
    tester.view.physicalSize = compact
        ? const Size(640, 1280)
        : const Size(1080, 2160);
    tester.view.devicePixelRatio = compact ? 2 : 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
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

  testWidgets(
    'Mushaf starts hidden and only explicit hints or peeks reveal its verses',
    (tester) async {
      await showPage(tester);
      expect(cubit.state.mode, OralRecitationMode.hidden);
      expect(maskedGlobals(tester), {1, 2, 3, 4, 5, 6, 7});
      expect(find.text('بِسْمِ'), findsNothing);
      expect(find.text('ٱللَّهِ'), findsNothing);

      await openDisplayOptions(tester);
      expect(
        find.text('معالجة محلية · دون إنترنت · لا يُحفظ صوتك'),
        findsOneWidget,
      );
      for (final mode in OralRecitationMode.values) {
        expect(
          find.byKey(ValueKey('recitation-mode-${mode.name}')),
          findsOneWidget,
        );
      }
      await closeDisplayOptions(tester);
      await selectMode(tester, OralRecitationMode.reading);
      expect(maskedGlobals(tester), {3, 4, 5, 6, 7});
      await selectMode(tester, OralRecitationMode.firstWord);
      expect(maskedGlobals(tester), {1, 2, 3, 4, 5, 6, 7});
      expect(
        wordPainter(tester).words
            .singleWhere((word) => word.targetIndex == 0)
            .visible,
        isTrue,
      );
      await selectMode(tester, OralRecitationMode.hidden);
      expect(
        wordPainter(tester).words
            .singleWhere((word) => word.targetIndex == 0)
            .visible,
        isFalse,
      );

      await tester.tap(find.text('تلميح'));
      await tester.pumpAndSettle();
      expect(
        wordPainter(tester).words
            .singleWhere((word) => word.targetIndex == 0)
            .visible,
        isTrue,
      );
      expect(
        wordPainter(tester).words
            .singleWhere((word) => word.targetIndex == 1)
            .visible,
        isFalse,
      );
      expect(maskedGlobals(tester), {1, 2, 3, 4, 5, 6, 7});
      expect(cubit.state.hintCount, 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('تلميح')),
      );
      await tester.pump(const Duration(milliseconds: 650));
      expect(cubit.state.revealedGlobals, contains(1));
      expect(maskedGlobals(tester), {2, 3, 4, 5, 6, 7});
      await gesture.up();
      await tester.pumpAndSettle();
      expect(maskedGlobals(tester), {1, 2, 3, 4, 5, 6, 7});
      expect(cubit.state.hintedGlobalAyahs, contains(1));
      await closePage(tester);
    },
  );

  testWidgets(
    'Capture locks mode choice, updates microphone level and pauses safely',
    (tester) async {
      await showPage(tester);
      await tester.tap(find.text('بدء التسميع'));
      await tester.pumpAndSettle();
      expect(
        cubit.state.isListening,
        isTrue,
        reason:
            '${cubit.state.lifecycle}: ${cubit.state.errorMessage}; starts=${speech.startListeningCount}',
      );
      await openDisplayOptions(tester);
      final mode = tester.widget<Semantics>(
        find.byKey(const ValueKey('recitation-mode-reading')),
      );
      expect(mode.properties.enabled, isFalse);
      expect(mode.properties.onTap, isNull);
      await closeDisplayOptions(tester);
      speech.levels.add(.72);
      await tester.pumpAndSettle();
      expect(cubit.state.audioLevel, .72);
      final meter = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('recitation-audio-level')),
      );
      expect(meter.value, .72);
      await tester.tap(find.text('إيقاف مؤقت'));
      await tester.pumpAndSettle();
      expect(speech.isListening, isFalse);
      await openDisplayOptions(tester);
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('recitation-mode-reading')),
            )
            .properties
            .onTap,
        isNull,
      );
      await closeDisplayOptions(tester);
      await closePage(tester);
    },
  );

  testWidgets(
    'Partial session separates coverage from accuracy and retries only the unread ayah',
    (tester) async {
      await showPage(tester);
      await tester.tap(find.text('بدء التسميع'));
      await tester.pump();
      speech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await tester.pumpAndSettle();
      expect(maskedGlobals(tester), {2, 3, 4, 5, 6, 7});
      await tester.tap(find.text('إنهاء'));
      await tester.pumpAndSettle();
      expect(cubit.state.summary!.accuracyPercentage, 100);
      expect(cubit.state.summary!.coveragePercentage, 50);
      expect(find.text('50٪'), findsOneWidget);
      expect(find.text('100٪'), findsOneWidget);
      expect(find.text('لم تُقرأ بعد'), findsWidgets);
      final retry = find.byKey(const ValueKey('retry-ayah-2'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        cubit.state.targetWords.every((word) => word.globalAyah == 2),
        isTrue,
      );
      expect(cubit.state.planId, 'practice-plan');
      expect(cubit.state.mode, OralRecitationMode.hidden);
      await closePage(tester);
    },
  );

  testWidgets(
    'A confirmed mistake reveals its canonical word and remains red after correction',
    (tester) async {
      await showPage(tester);
      await tester.tap(find.text('بدء التسميع'));
      await tester.pumpAndSettle();
      speech.emitTranscript('بسم الرحمن الرحيم', isFinal: true);
      await tester.pumpAndSettle();
      expect(cubit.state.correctionWordIndex, 1);
      expect(find.text('ٱللَّهِ'), findsOneWidget);
      final mistake = wordPainter(tester).words
          .singleWhere((word) => word.targetIndex == 1);
      expect(mistake.visible, isTrue);
      expect(mistake.mistake, isTrue);
      expect(mistake.unresolved, isTrue);
      expect(maskedGlobals(tester), {2, 3, 4, 5, 6, 7});
      speech.emitTranscript('الله', isFinal: true);
      await tester.pumpAndSettle();
      expect(cubit.state.alignedWords[1].status, WordAlignmentStatus.matched);
      expect(cubit.state.assistedWordIndices, contains(1));
      expect(cubit.state.correctionWordIndex, isNull);
      final corrected = wordPainter(tester).words
          .singleWhere((word) => word.targetIndex == 1);
      expect(corrected.mistake, isTrue);
      expect(corrected.unresolved, isFalse);
      expect(cubit.state.committedTargetIndex, 4);
      expect(cubit.state.isListening, isTrue);
      await closePage(tester);
    },
  );

  testWidgets(
    'Compact Arabic layout keeps controls reachable with enlarged text',
    (tester) async {
      await showPage(tester, compact: true);
      expect(tester.takeException(), isNull);
      expect(find.text('بدء التسميع').hitTestable(), findsOneWidget);
      expect(find.text('تلميح').hitTestable(), findsOneWidget);
      await tester.tap(find.text('بدء التسميع'));
      await tester.pumpAndSettle();
      expect(find.text('إيقاف مؤقت').hitTestable(), findsOneWidget);
      await closePage(tester);
    },
  );
}
