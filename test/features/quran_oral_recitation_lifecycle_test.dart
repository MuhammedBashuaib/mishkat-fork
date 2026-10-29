import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';

class _MemoryStorage implements LocalStorageService {
  final Map<String, dynamic> _values = {};

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

class _Repository extends QuranRepository {
  @override
  Future<QuranData> load() async => QuranData(
    chapters: [
      QuranChapter(
        number: 1,
        name: 'الفاتحة',
        englishName: 'Al-Faatiha',
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

class _DelayedAudio extends QuranAudioService {
  Completer<void>? stopBarrier;
  int stopCount = 0;

  @override
  Future<void> stop() async {
    stopCount++;
    await stopBarrier?.future;
  }
}

/// Models native calls that can complete after the user has left or paused.
class _DelayedSpeech extends MockSpeechRecognitionService {
  Completer<void>? startBarrier;
  Completer<bool>? permissionBarrier;
  SpeechRecognitionFailure? startFailure;
  int startRequests = 0;
  int cancelCount = 0;

  @override
  Future<bool> hasPermission() =>
      permissionBarrier?.future ?? super.hasPermission();

  @override
  Future<bool> startListening({
    String localeId = 'ar_SA',
    List<String> contextualPhrases = const [],
  }) async {
    startRequests++;
    await startBarrier?.future;
    final failure = startFailure;
    if (failure != null) {
      emitError(
        failure.message,
        type: failure.type,
        isPermanent: failure.isPermanent,
      );
      await Future<void>.delayed(Duration.zero);
      return false;
    }
    return super.startListening(
      localeId: localeId,
      contextualPhrases: contextualPhrases,
    );
  }

  @override
  Future<void> cancelListening() async {
    cancelCount++;
    await super.cancelListening();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DelayedSpeech speech;
  late _DelayedAudio audio;
  late QuranMemorizationCubit memorization;
  late QuranOralRecitationCubit cubit;

  setUp(() async {
    speech = _DelayedSpeech();
    audio = _DelayedAudio();
    memorization = QuranMemorizationCubit(
      repository: QuranMemorizationRepository(storage: _MemoryStorage()),
    );
    await memorization.load();
    cubit = QuranOralRecitationCubit(
      speechService: speech,
      quranRepository: _Repository(),
      memorizationCubit: memorization,
      audioService: audio,
    );
    await cubit.prepareSession(surahNumber: 1);
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    await speech.dispose();
    await memorization.close();
  });

  test(
    'repeated start taps during audio shutdown start the microphone once',
    () async {
      final barrier = Completer<void>();
      audio.stopBarrier = barrier;

      final first = cubit.startRecitation();
      final second = cubit.startRecitation();
      await pumpEventQueue();
      barrier.complete();
      await Future.wait([first, second]);

      expect(speech.startRequests, 1);
      expect(cubit.state.lifecycle, OralRecitationLifecycle.listening);
      expect(speech.isListening, isTrue);
    },
  );

  test(
    'repeated resume taps during audio shutdown start the microphone once',
    () async {
      await cubit.startRecitation();
      await cubit.pauseRecitation();
      audio.stopBarrier = Completer<void>();

      final first = cubit.resumeRecitation();
      final second = cubit.resumeRecitation();
      await pumpEventQueue();
      audio.stopBarrier!.complete();
      await Future.wait([first, second]);

      expect(speech.startRequests, 2);
      expect(cubit.state.lifecycle, OralRecitationLifecycle.listening);
    },
  );

  test(
    'pause during native startup cancels the microphone after startup returns',
    () async {
      speech.startBarrier = Completer<void>();
      final starting = cubit.startRecitation();
      await pumpEventQueue();
      expect(speech.startRequests, 1);

      await cubit.pauseRecitation();
      speech.startBarrier!.complete();
      await starting;
      await pumpEventQueue();

      expect(cubit.state.lifecycle, OralRecitationLifecycle.paused);
      expect(speech.isListening, isFalse);
    },
  );

  test(
    'backgrounding while playback stops prevents native capture from starting',
    () async {
      audio.stopBarrier = Completer<void>();
      final starting = cubit.startRecitation();
      await pumpEventQueue();

      await cubit.pauseRecitation();
      audio.stopBarrier!.complete();
      await starting;

      expect(cubit.state.lifecycle, OralRecitationLifecycle.paused);
      expect(speech.startRequests, 0);
      expect(speech.isListening, isFalse);
    },
  );

  test('finishing during native startup preserves the summary and releases capture', () async {
    speech.startBarrier = Completer<void>();
    final starting = cubit.startRecitation();
    await pumpEventQueue();

    await cubit.finishSession();
    final summary = cubit.state.summary;
    speech.startBarrier!.complete();
    await starting;
    await pumpEventQueue();

    expect(cubit.state.lifecycle, OralRecitationLifecycle.completed);
    expect(cubit.state.summary, same(summary));
    expect(speech.isListening, isFalse);
  });

  test(
    'leaving the page during native startup cannot leave capture running',
    () async {
      speech.startBarrier = Completer<void>();
      final starting = cubit.startRecitation();
      await pumpEventQueue();

      await cubit.close();
      speech.startBarrier!.complete();
      await expectLater(starting, completes);
      await pumpEventQueue();

      expect(speech.isListening, isFalse);
    },
  );

  test('permission refresh never resets a completed session', () async {
    await cubit.startRecitation();
    await cubit.finishSession();
    final summary = cubit.state.summary;

    await cubit.checkAndRefreshPermission();

    expect(cubit.state.lifecycle, OralRecitationLifecycle.completed);
    expect(cubit.state.summary, same(summary));
  });

  test(
    'an older permission refresh cannot overwrite newly active capture',
    () async {
      final barrier = Completer<bool>();
      speech.permissionBarrier = barrier;
      final refreshing = cubit.checkAndRefreshPermission();
      await pumpEventQueue();

      await cubit.startRecitation();
      barrier.complete(true);
      await refreshing;

      expect(cubit.state.lifecycle, OralRecitationLifecycle.listening);
      expect(speech.isListening, isTrue);
    },
  );

  test(
    'late recognizer errors and statuses cannot resume a paused session',
    () async {
      await cubit.startRecitation();
      await cubit.pauseRecitation();

      speech.emitError('خطأ متأخر', type: SpeechRecognitionFailureType.network);
      speech.emitStatus('done');
      speech.emitTranscript('بسم الله الرحمن الرحيم الحمد لله رب العالمين');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(cubit.state.lifecycle, OralRecitationLifecycle.paused);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.matchedWordsCount, 0);
      expect(speech.startRequests, 1);
      expect(speech.isListening, isFalse);
    },
  );

  test(
    'pausing during automatic restart also cancels the delayed native capture',
    () async {
      await cubit.startRecitation();
      speech.startBarrier = Completer<void>();
      speech.emitStatus('done');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(speech.startRequests, 2);

      await cubit.pauseRecitation();
      speech.startBarrier!.complete();
      await pumpEventQueue();

      expect(cubit.state.lifecycle, OralRecitationLifecycle.paused);
      expect(speech.isListening, isFalse);
    },
  );

  test(
    'specific Arabic language failure survives an unsuccessful start',
    () async {
      speech.startFailure = const SpeechRecognitionFailure(
        type: SpeechRecognitionFailureType.languageUnavailable,
        message: 'العربية غير متاحة في خدمة التعرف الصوتي.',
        isPermanent: true,
      );

      await cubit.startRecitation();

      expect(
        cubit.state.lifecycle,
        OralRecitationLifecycle.languageUnavailable,
      );
      expect(cubit.state.errorMessage, speech.startFailure!.message);
      expect(speech.isListening, isFalse);
    },
  );

  test('persistent recognizer busy errors stop claiming to listen after bounded retries', () async {
    await cubit.startRecitation();
    for (var attempt = 0; attempt < 4; attempt++) {
      speech.emitError(
        'محرك التعرف مشغول.',
        type: SpeechRecognitionFailureType.busy,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    expect(cubit.state.lifecycle, OralRecitationLifecycle.paused);
    expect(cubit.state.errorMessage, isNotEmpty);
    expect(speech.startRequests, lessThanOrEqualTo(4));
    expect(speech.isListening, isFalse);
  });
}
