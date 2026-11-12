import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
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
          'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
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
  Future<void> stopListening() async {
    stopCount++;
    await super.stopListening();
  }

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
  setUpAll(() async {
    await MushafLayoutRepository.instance.load();
    await OralRecitationMushaf.preloadCanonicalText();
  });

  testWidgets(
    'repeat prompt waits for final uncertainty while confirmed mistakes stay visible',
    (tester) async {
      final speech = _OfflineSpeech();
      final memorization = QuranMemorizationCubit(
        repository: QuranMemorizationRepository(storage: _MemoryStorage()),
      );
      await memorization.load();
      final cubit = QuranOralRecitationCubit(
        speechService: speech,
        quranRepository: _QuranRepository(),
        memorizationCubit: memorization,
      );
      await cubit.prepareSession(
        surahNumber: 1,
        startGlobalAyah: 1,
        // Keep an unread final Ayah: this test covers correction while the
        // session is still underway, before automatic report completion.
        endGlobalAyah: 3,
      );
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: QuranOralRecitationPage(cubit: cubit),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('بدء التسميع'));
      await tester.pumpAndSettle();

      // A changing word ending is normal while the reader is still speaking.
      speech.emitTranscript('بسم الله الرحمن الرحي');
      await tester.pumpAndSettle();
      expect(cubit.state.correctionWordIndex, 3);
      expect(cubit.state.isCorrectionProvisional, isTrue);
      expect(find.byKey(const ValueKey('recitation-correction')), findsNothing);
      expect(find.text('أعد آخر كلمة بوضوح'), findsNothing);

      speech.emitTranscript('بسم الله الرحمن الرحيم', isFinal: true);
      await tester.pumpAndSettle();
      expect(cubit.state.committedTargetIndex, 4);
      speech.emitTranscript('الحمد لله ر');
      await tester.pumpAndSettle();
      expect(cubit.state.correctionWordIndex, 6);
      expect(cubit.state.isCorrectionProvisional, isTrue);
      expect(find.byKey(const ValueKey('recitation-correction')), findsNothing);

      // An unanchored final result can ask for help without declaring a mistake.
      speech.emitTranscript('كلام بعيد', isFinal: true);
      await tester.pumpAndSettle();
      expect(cubit.state.correctionWordIndex, 4);
      expect(cubit.state.isCorrectionProvisional, isFalse);
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
      expect(find.text('لم تتضح كلمة في المقطع الأخير'), findsOneWidget);
      expect(find.text('تلميح الكلمة').hitTestable(), findsOneWidget);

      speech.emitTranscript('الحمد لله');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recitation-correction')), findsNothing);
      expect(speech.isListening, isTrue);
      expect(speech.stopCount, 0);

      // A confirmed omission is still actionable while its retry is provisional.
      speech.emitTranscript('الحمد لله العالمين', isFinal: true);
      await tester.pumpAndSettle();
      expect(cubit.state.unresolvedMistakeWordIndices, {6});
      expect(find.text('الصحيح:'), findsOneWidget);
      speech.emitTranscript('رب العالمين');
      await tester.pumpAndSettle();
      expect(cubit.state.isCorrectionProvisional, isFalse);
      expect(cubit.state.unresolvedMistakeWordIndices, {6});
      expect(find.text('الصحيح:'), findsOneWidget);

      speech.emitTranscript('رب العالمين', isFinal: true);
      await tester.pumpAndSettle();
      expect(cubit.state.unresolvedMistakeWordIndices, isEmpty);
      expect(cubit.state.mistakeWordIndices, {6});
      expect(find.byKey(const ValueKey('recitation-correction')), findsNothing);
      expect(cubit.state.isListening, isTrue);
      expect(cubit.state.summary, isNull);
      expect(cubit.state.completedGlobalAyahs, isNot(contains(3)));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await cubit.close();
      await speech.dispose();
      await memorization.close();
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  for (final viewport in [
    (name: 'Short enlarged-text', size: const Size(320, 520), scale: 1.6),
    (name: 'Landscape', size: const Size(640, 360), scale: 1.0),
  ]) {
    testWidgets(
      '${viewport.name} screen keeps error controls reachable and details preserve capture',
      (tester) async {
        final speech = _OfflineSpeech();
        final memorization = QuranMemorizationCubit(
          repository: QuranMemorizationRepository(storage: _MemoryStorage()),
        );
        await memorization.load();
        final cubit = QuranOralRecitationCubit(
          speechService: speech,
          quranRepository: _QuranRepository(),
          memorizationCubit: memorization,
        );
        await cubit.prepareSession(
          surahNumber: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 2,
        );
        tester.view.physicalSize = viewport.size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.scale)),
              child: child!,
            ),
            home: QuranOralRecitationPage(cubit: cubit),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          MediaQuery.textScalerOf(
            tester.element(
              find.byKey(const ValueKey('recitation-control-dock')),
            ),
          ).scale(10),
          10 * viewport.scale,
        );
        await tester.tap(find.text('بدء التسميع'));
        await tester.pumpAndSettle();
        speech.emitTranscript('بسم الرحمن الرحيم', isFinal: true);
        await tester.pumpAndSettle();
        expect(cubit.state.unresolvedMistakeWordIndices, contains(1));
        expect(
          find.byKey(const ValueKey('recitation-correction')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        for (final label in ['إيقاف مؤقت', 'تلميح', 'إنهاء']) {
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        for (final key in ['oral-mushaf-next', 'oral-mushaf-previous']) {
          expect(
            find.byKey(Key(key)).hitTestable(),
            findsOneWidget,
            reason: 'Page navigation must remain reachable while correcting a word.',
          );
        }
        expect(
          tester.getSize(find.byKey(const Key('oral-mushaf-page-1'))).width,
          greaterThan(viewport.size.width * .85),
          reason: 'The Quran page should use the available phone width.',
        );

        final stopsBefore = speech.stopCount;
        await tester.tap(
          find.byKey(const ValueKey('recitation-session-details')),
        );
        await tester.pumpAndSettle();
        expect(find.text('تفاصيل التسميع'), findsOneWidget);
        expect(cubit.state.isListening, isTrue);
        expect(speech.isListening, isTrue);
        expect(speech.stopCount, stopsBefore);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.text('تفاصيل التسميع'))).pop();
        await tester.pumpAndSettle();
        expect(speech.stopCount, stopsBefore);
        expect(find.text('إيقاف مؤقت').hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await cubit.close();
        await speech.dispose();
        await memorization.close();
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  }
}
