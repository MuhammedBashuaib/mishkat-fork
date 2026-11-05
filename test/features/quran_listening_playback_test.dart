import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/quran_audio_station.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/domain/models/audio_repeat_config.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';

class _Audio implements QuranAudioService {
  final states = StreamController<PlayerState>.broadcast();
  final errors = StreamController<Object>.broadcast();
  Stream<Object> get playbackErrors => errors.stream;
  final ayahs = <int>[];
  final surahs = <int>[];
  final words = <(int, int, int)>[];
  final stations = <String>[];
  final speeds = <double>[];
  Future<void> Function(int)? onSurah;
  Future<void> Function(int)? onAyah;
  bool playing = false;
  int stops = 0;
  int pauses = 0;
  int resumes = 0;

  void event(ProcessingState state, {bool isPlaying = true}) {
    playing = isPlaying;
    states.add(PlayerState(isPlaying, state));
  }

  Future<void> playSurah({
    required String reciter,
    required int surah,
    String? title,
  }) async {
    surahs.add(surah);
    if (onSurah != null) {
      await onSurah!(surah);
      return;
    }
    event(ProcessingState.ready);
  }

  Future<void> playWord({
    required int surah,
    required int ayah,
    required int word,
  }) async {
    words.add((surah, ayah, word));
    event(ProcessingState.ready);
  }

  Future<void> playStreamUrl(String url) async {
    stations.add(url);
    event(ProcessingState.ready);
  }

  Future<void> setPlaybackSpeed(double speed) async => speeds.add(speed);

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {
    ayahs.add(globalAyah);
    if (onAyah != null) await onAyah!(globalAyah);
    event(ProcessingState.ready);
  }

  @override
  Stream<PlayerState> get playerState => states.stream;
  @override
  bool get isPlaying => playing;
  @override
  Future<void> pause() async {
    pauses++;
    event(ProcessingState.ready, isPlaying: false);
  }

  @override
  Future<void> resume() async {
    resumes++;
    event(ProcessingState.ready);
  }

  @override
  Future<void> stop() async {
    stops++;
    event(ProcessingState.idle, isPlaying: false);
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage extends LocalStorageService {
  final values = <String, Map<String, dynamic>>{};
  Completer<void>? repeatSave;
  @override
  Map<String, dynamic> readMap(String key) => values[key] ?? {};
  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    if (key == 'audio_repeat_config') await repeatSave?.future;
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = QuranRepository();
  late _Audio audio;
  late QuranCubit cubit;
  late _Storage storage;
  final radio = QuranAudioStation.defaultCatalog.firstWhere(
    (s) => s.isAudioPlayable,
  );

  setUpAll(repository.load);
  setUp(() async {
    audio = _Audio();
    storage = _Storage();
    cubit = QuranCubit(
      repository: repository,
      storage: storage,
      audio: audio,
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
    await cubit.load();
  });
  tearDown(() => cubit.close());

  test(
    'old completion during ayah load never skips the selected verse',
    () async {
      await cubit.playAyah(2, origin: QuranPlaybackOrigin.mushaf);
      final pending = Completer<void>();
      audio.onAyah = (_) => pending.future;
      final loading = cubit.playAyah(5, origin: QuranPlaybackOrigin.mushaf);
      audio.event(ProcessingState.loading);
      audio.event(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.audioGlobalAyah, 5);
      expect(cubit.state.audioStatus, QuranAudioStatus.loading);
      expect(audio.ayahs, [2, 5]);
      pending.complete();
      await loading;
      expect(cubit.state.audioGlobalAyah, 5);
    },
  );

  test(
    'reader exit cancels repeat start pending settings persistence',
    () async {
      storage.repeatSave = Completer<void>();
      final starting = cubit.startRepeatPlayback(
        AudioRepeatConfig.defaultConfig,
        initialGlobalAyah: 3,
        origin: QuranPlaybackOrigin.mushaf,
      );
      await cubit.stopAudioIfOwnedBy(QuranPlaybackOrigin.mushaf);
      storage.repeatSave!.complete();
      await starting;
      expect(audio.ayahs, isEmpty);
      expect(cubit.state.audioStatus, QuranAudioStatus.idle);
      expect(cubit.playbackOrigin, isNull);
    },
  );

  test('runtime audio errors keep same recording retryable', () async {
    await cubit.playSurah(7);
    audio.errors.add(StateError('network interrupted'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.audioStatus, QuranAudioStatus.failure);
    expect(cubit.state.audioSurah, 7);
    audio.event(ProcessingState.idle, isPlaying: false);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.audioSurah, 7);
    await cubit.toggleAudio(continuous: false);
    expect(audio.surahs, [7, 7]);
    expect(cubit.state.audioStatus, QuranAudioStatus.playing);
  });

  test('word pause resumes same word and failure retries it', () async {
    await cubit.playWord(globalAyah: 1, word: 2);
    await cubit.toggleWordAudio();
    expect(audio.pauses, 1);
    await cubit.toggleWordAudio();
    expect(audio.resumes, 1);
    expect(audio.words, [(1, 1, 2)]);
    audio.errors.add(StateError('word interrupted'));
    await Future<void>.delayed(Duration.zero);
    await cubit.toggleWordAudio();
    expect(audio.words, [(1, 1, 2), (1, 1, 2)]);
    expect(audio.ayahs, isEmpty);
  });

  test(
    'reader starts at page first ayah instead of previous playback',
    () async {
      await cubit.playAyah(1, origin: QuranPlaybackOrigin.audioPlayer);
      await cubit.openPage(50);
      final first = cubit.state.data!.page(50).first.global;
      await cubit.toggleReaderAudio();
      expect(audio.ayahs.last, first);
      expect(cubit.playbackOrigin, QuranPlaybackOrigin.mushaf);
    },
  );

  test(
    'tap selection starts there, advances, and then pauses without restarting',
    () async {
      await cubit.openPage(50);
      final selected = cubit.state.data!.page(50).first.global + 1;
      cubit.selectReaderAyah(selected);
      expect(audio.ayahs, isEmpty);
      await cubit.toggleReaderAudio(selectedGlobalAyah: selected);
      expect(audio.ayahs, [selected]);
      audio.event(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);
      expect(audio.ayahs, [selected, selected + 1]);
      await cubit.toggleReaderAudio(selectedGlobalAyah: selected);
      expect(audio.pauses, 1);
      expect(audio.ayahs, [selected, selected + 1]);
      cubit.selectReaderAyah(selected);
      await cubit.toggleReaderAudio(selectedGlobalAyah: selected);
      expect(audio.ayahs.last, selected);
      expect(audio.ayahs.length, 3);
    },
  );

  test('changing page drops old selection', () async {
    cubit.selectReaderAyah(3);
    await cubit.openPage(10);
    await cubit.toggleReaderAudio();
    expect(audio.ayahs.last, cubit.state.data!.page(10).first.global);
  });

  test('popup ayah and educational word stop after one item', () async {
    await cubit.playAyah(
      9,
      continuous: false,
      origin: QuranPlaybackOrigin.mushaf,
    );
    audio.event(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(audio.ayahs, [9]);
    expect(cubit.state.audioStatus, QuranAudioStatus.idle);
    await cubit.playWord(globalAyah: 9, word: 2);
    expect(audio.words, [(2, 2, 2)]);
    expect(cubit.state.audioWordIndex, 2);
    audio.event(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(audio.ayahs, [9]);
    expect(cubit.state.audioWordIndex, isNull);
    expect(cubit.state.audioStatus, QuranAudioStatus.idle);
  });

  test('full surah uses one recording and once mode ends', () async {
    await cubit.playSurah(2);
    expect(audio.surahs, [2]);
    expect(audio.ayahs, isEmpty);
    expect(cubit.state.audioSurah, 2);
    expect(cubit.state.audioGlobalAyah, isNull);
    audio.event(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(audio.surahs, [2]);
    expect(cubit.state.audioStatus, QuranAudioStatus.idle);
  });

  test('repeat reloads same recording and next advances whole surah', () async {
    await cubit.setListeningMode(QuranListeningMode.repeat);
    await cubit.playSurah(2);
    audio.event(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(audio.surahs, [2, 2]);
    await cubit.setListeningMode(QuranListeningMode.next);
    audio.event(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(audio.surahs, [2, 2, 3]);
    expect(audio.ayahs, isEmpty);
  });

  test('next mode stops at final surah and skip buttons use surahs', () async {
    await cubit.playSurah(112);
    await cubit.nextAudioAyah();
    await cubit.previousAudioAyah();
    expect(audio.surahs, [112, 113, 112]);
    await cubit.setListeningMode(QuranListeningMode.next);
    await cubit.playSurah(114);
    audio.event(ProcessingState.completed);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.audioStatus, QuranAudioStatus.idle);
    expect(audio.surahs.last, 114);
  });

  test(
    'reader exit leaves hub and radio alive but stops its own audio',
    () async {
      await cubit.playSurah(3);
      await cubit.stopAudioIfOwnedBy(QuranPlaybackOrigin.mushaf);
      expect(audio.stops, 0);
      expect(cubit.state.audioSurah, 3);
      await cubit.playStation(radio);
      await cubit.stopAudioIfOwnedBy(QuranPlaybackOrigin.mushaf);
      expect(audio.stops, 0);
      expect(cubit.state.activeStation, radio);
      await cubit.toggleReaderAudio();
      await cubit.stopAudioIfOwnedBy(QuranPlaybackOrigin.mushaf);
      expect(audio.stops, 1);
      expect(cubit.state.audioStatus, QuranAudioStatus.idle);
      audio.event(ProcessingState.ready);
      expect(cubit.state.audioStatus, QuranAudioStatus.idle);
    },
  );

  test(
    'late failed surah request cannot overwrite station or stopped state',
    () async {
      final pending = Completer<void>();
      audio.onSurah = (_) => pending.future;
      final load = cubit.playSurah(4);
      await cubit.playStation(radio);
      pending.completeError(StateError('old request'));
      await load;
      expect(cubit.state.activeStation, radio);
      expect(cubit.state.audioStatus, QuranAudioStatus.playing);
      expect(cubit.state.error, isNull);
    },
  );

  test(
    'full-surah failure retries same surah and preserves chosen speed',
    () async {
      audio.onSurah = (_) async => throw StateError('network');
      await cubit.playSurah(5);
      expect(cubit.state.audioStatus, QuranAudioStatus.failure);
      audio.event(ProcessingState.idle, isPlaying: false);
      expect(cubit.state.audioSurah, 5);
      audio.onSurah = null;
      await cubit.setPlaybackSpeed(1.25);
      await cubit.toggleAudio(continuous: true);
      expect(audio.surahs, [5, 5]);
      expect(audio.speeds.last, 1.25);
      expect(cubit.state.audioStatus, QuranAudioStatus.playing);
      expect(storage.readMap('quran_listening_settings')['speed'], 1.25);
    },
  );

  testWidgets(
    'sleep deadline stops repeated surahs while settings are unmounted',
    (tester) async {
      await cubit.setListeningMode(QuranListeningMode.repeat);
      await cubit.playSurah(1);
      cubit.setSleepTimer(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 5));
      audio.event(ProcessingState.completed);
      await tester.pump();
      expect(audio.surahs, [1, 1]);
      await tester.pump(const Duration(minutes: 5));
      expect(cubit.state.audioStatus, QuranAudioStatus.idle);
      expect(cubit.state.sleepTimerRemaining, isNull);
      expect(audio.stops, 1);
    },
  );

  testWidgets('sleep timer can be replaced, cancelled and applies to radio', (
    tester,
  ) async {
    await cubit.playStation(radio);
    cubit.setSleepTimer(const Duration(seconds: 1));
    cubit.setSleepTimer(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    expect(audio.stops, 0);
    cubit.setSleepTimer(null);
    await tester.pump(const Duration(seconds: 5));
    expect(audio.stops, 0);
    cubit.setSleepTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(audio.stops, 1);
    expect(cubit.state.activeStation, isNull);
  });

  testWidgets('switching to mushaf cancels listening timer', (tester) async {
    await cubit.playSurah(1);
    cubit.setSleepTimer(const Duration(seconds: 1));
    await cubit.toggleReaderAudio();
    await tester.pump(const Duration(seconds: 2));
    expect(audio.stops, 0);
    expect(cubit.state.sleepTimerRemaining, isNull);
    expect(cubit.playbackOrigin, QuranPlaybackOrigin.mushaf);
  });
}
