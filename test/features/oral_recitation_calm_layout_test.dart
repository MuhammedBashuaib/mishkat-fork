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
