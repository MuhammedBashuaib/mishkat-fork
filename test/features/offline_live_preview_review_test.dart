import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/offline_speech_recognition_service.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

const _basmala = 'بسم الله الرحمن الرحيم';
const _passage = '$_basmala الحمد لله رب العالمين الرحمن الرحيم';

class _Quran extends QuranRepository {
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
  @override
  bool get isOffline => true;
  @override
  Stream<double> get soundLevelStream => const Stream.empty();
  @override
  Stream<bool> get processingStream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live reveal confidence and assistance', () {
    late Directory temp;
    late _OfflineSpeech speech;
    late QuranMemorizationCubit memory;
    late QuranOralRecitationCubit cubit;

    Future<void> say(String text, {bool isFinal = false}) async {
      speech.emitTranscript(text, isFinal: isFinal);
      await pumpEventQueue();
    }

    Future<void> showPreview() async {
      await say(_basmala);
      await say(_basmala);
      expect(cubit.state.previewCompletedGlobalAyahs, {1});
      expect(cubit.state.completedGlobalAyahs, isEmpty);
      expect(cubit.state.committedTargetIndex, 0);
    }

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('mishkat-preview-review-');
      final storage = LocalStorageService(directory: temp);
      await storage.init();
      memory = QuranMemorizationCubit(
        repository: QuranMemorizationRepository(storage: storage),
      );
      await memory.load();
      speech = _OfflineSpeech();
      cubit = QuranOralRecitationCubit(
        speechService: speech,
        quranRepository: _Quran(),
        memorizationCubit: memory,
      );
      await cubit.prepareSession(surahNumber: 1);
      await cubit.startRecitation();
    });

    tearDown(() async {
      await cubit.close();
      await speech.dispose();
      await memory.close();
      await temp.delete(recursive: true);
    });

    test(
      'empty partial breaks consecutive recognition without inventing help',
      () async {
        await say(_basmala);
        await say('');
        await say(_basmala);
        expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
        expect(cubit.state.hintedGlobalAyahs, isEmpty);
        expect(cubit.state.hintCount, 0);
        await say(_basmala);
        expect(cubit.state.previewCompletedGlobalAyahs, {1});
      },
    );

    test(
      'empty partial retracts visible text and remembers its assistance',
      () async {
        await showPreview();
        await say('');
        expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
        expect(cubit.state.completedGlobalAyahs, isEmpty);
        expect(cubit.state.committedTargetIndex, 0);
        expect(cubit.state.matchedWordsCount, 0);
        expect(cubit.state.hintedGlobalAyahs, {1});
        expect(cubit.state.hintCount, 1);
        await say('');
        expect(cubit.state.hintCount, 1);
      },
    );

    test(
      'final rejection cannot become unassisted mastery on rereading',
      () async {
        await showPreview();
        await say('بسم الله', isFinal: true);
        expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
        expect(cubit.state.completedGlobalAyahs, isEmpty);
        expect(cubit.state.hintedGlobalAyahs, {1});
        await say(_passage, isFinal: true);
        expect(cubit.state.summary, isNotNull);
        expect(cubit.state.summary!.coveragePercentage, 100);
        expect(cubit.state.summary!.hintCount, 1);
        expect(cubit.state.summary!.suggestedOutcome, ReviewOutcome.difficult);
      },
    );

    test(
      'a final confirming live reveal keeps ordinary unassisted credit',
      () async {
        await showPreview();
        await say(_passage, isFinal: true);
        expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
        expect(cubit.state.completedGlobalAyahs, {1, 2, 3});
        expect(cubit.state.hintedGlobalAyahs, isEmpty);
        expect(cubit.state.summary!.hintCount, 0);
        expect(cubit.state.summary!.suggestedOutcome, ReviewOutcome.easy);
      },
    );

    test(
      'pause with no final retracts exposed text and remembers help',
      () async {
        await showPreview();
        await cubit.pauseRecitation();
        expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
        expect(cubit.state.completedGlobalAyahs, isEmpty);
        expect(cubit.state.hintedGlobalAyahs, {1});
        expect(cubit.state.hintCount, 1);
      },
    );

    test(
      'empty final clears candidate so the next phrase needs two previews',
      () async {
        await say(_basmala);
        await say('', isFinal: true);
        await say(_basmala);
        expect(cubit.state.previewCompletedGlobalAyahs, isEmpty);
        expect(cubit.state.hintedGlobalAyahs, isEmpty);
        await say(_basmala);
        expect(cubit.state.previewCompletedGlobalAyahs, {1});
      },
    );
  });

  test('offline service forwards an empty live hypothesis to revoke its predecessor', () async {
    const channel = MethodChannel('test/mishkat_live_preview_review');
    final audio = StreamController<Object?>.broadcast(sync: true);
    final texts = <String>[_basmala, ''];
    String? session;
    final results = <SpeechRecognitionResultData>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
            case 'hasPermission':
              return true;
            case 'start':
              session = (call.arguments as Map)['sessionId'] as String;
              return true;
            case 'transcribe':
              return texts.removeAt(0);
            case 'stop':
            case 'release':
              return null;
          }
          throw StateError('Unexpected ${call.method}');
        });
    final service = OfflineSpeechRecognitionService(
      channel: channel,
      audioEvents: audio.stream,
    );
    service.resultsStream.listen(results.add);
    void packet() {
      final bytes = ByteData(3200);
      for (var i = 0; i < 1600; i++) {
        bytes.setInt16(i * 2, i.isEven ? 1200 : -1200, Endian.little);
      }
      audio.add({'sessionId': session, 'pcm': bytes.buffer.asUint8List()});
    }

    try {
      await service.startListening();
      for (var i = 0; i < 19; i++) packet();
      await pumpEventQueue();
      for (var i = 0; i < 12; i++) packet();
      await pumpEventQueue();
      expect(results.map((result) => result.recognizedWords), [_basmala, '']);
      expect(results.every((result) => !result.isFinal), isTrue);
      expect(service.isListening, isTrue);
    } finally {
      await service.dispose();
      await audio.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
