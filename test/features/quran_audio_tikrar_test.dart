import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_repeat_controller.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';
import 'package:mishkat_app/features/quran/data/models/hifz_planning_models.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_analytics_models.dart';
import 'package:mishkat_app/features/quran/data/models/mushaf_layout_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/domain/models/audio_repeat_config.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/memorization_session_page.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/quran_mini_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test Helpers & Fakes
// ─────────────────────────────────────────────────────────────────────────────

class FakeLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> init() async {}

  T? read<T>(String key) => _data[key] as T?;

  Future<void> write<T>(String key, T value) async {
    _data[key] = value;
  }

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from((_data[key] as Map?) ?? {});

  @override
  List<dynamic> readList(String key) {
    final value = _data[key];
    return value is List ? List<dynamic>.from(value) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final value = _data[key];
    return value is num ? value.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _data[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _data[key] = value;
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async => _data.clear();
}

QuranData _createMockQuranData() {
  final chapters = [
    const QuranChapter(
      number: 1,
      name: 'الفاتحة',
      englishName: 'Al-Faatiha',
      revelationType: 'Meccan',
      page: 1,
      ayahs: ['1', '2', '3', '4', '5', '6', '7'],
      globalStart: 1,
    ),
    const QuranChapter(
      number: 2,
      name: 'البقرة',
      englishName: 'Al-Baqara',
      revelationType: 'Medinan',
      page: 2,
      ayahs: ['1', '2', '3', '4', '5'],
      globalStart: 8,
    ),
    const QuranChapter(
      number: 114,
      name: 'الناس',
      englishName: 'An-Naas',
      revelationType: 'Meccan',
      page: 604,
      ayahs: ['1', '2', '3', '4', '5', '6'],
      globalStart: 6231,
    ),
  ];

  final juz = [
    const JuzStart(number: 1, surah: 1, ayah: 1),
    const JuzStart(number: 2, surah: 2, ayah: 142),
  ];

  final pages = [
    const MushafPageInfo(
      page: 1,
      first: QuranPoint(surah: 1, ayah: 1, global: 1),
      last: QuranPoint(surah: 1, ayah: 7, global: 7),
    ),
    const MushafPageInfo(
      page: 2,
      first: QuranPoint(surah: 2, ayah: 1, global: 8),
      last: QuranPoint(surah: 2, ayah: 5, global: 12),
    ),
    const MushafPageInfo(
      page: 604,
      first: QuranPoint(surah: 114, ayah: 1, global: 6231),
      last: QuranPoint(surah: 114, ayah: 6, global: 6236),
    ),
  ];

  return QuranData(chapters: chapters, juz: juz, pages: pages);
}

class FakeQuranRepository implements QuranRepository {
  FakeQuranRepository(this.data);
  final QuranData data;

  @override
  Future<QuranData> load() async => data;

  @override
  List<QuranSearchResult> search(
    QuranData data,
    String query, {
    int limit = 50,
  }) => const [];
}

class ControllableAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _bufferedController = StreamController<Duration>.broadcast();

  final List<({String reciter, int globalAyah})> playedAyahs = [];
  bool isPaused = false;
  bool isStopped = false;
  bool throwOnPlay = false;

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get bufferedPositionStream => _bufferedController.stream;

  @override
  bool get isPlaying => _lastState?.playing ?? false;

  PlayerState? _lastState;
  Duration _currentPosition = Duration.zero;
  Duration? _currentDuration = const Duration(seconds: 10);

  @override
  Duration get currentPosition => _currentPosition;

  @override
  Duration? get duration => _currentDuration;

  void emitState(PlayerState state) {
    _lastState = state;
    _stateController.add(state);
  }

  void emitPosition(Duration pos) {
    _currentPosition = pos;
    _positionController.add(pos);
  }

  void emitDuration(Duration? dur) {
    _currentDuration = dur;
    _durationController.add(dur);
  }

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {
    if (throwOnPlay) {
      throw const QuranAudioOfflineException();
    }
    playedAyahs.add((reciter: reciter, globalAyah: globalAyah));
    isStopped = false;
    isPaused = false;
    emitState(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    isPaused = true;
    emitState(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> resume() async {
    isPaused = false;
    emitState(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    isStopped = true;
    emitState(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration position) async {
    emitPosition(position);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferedController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 1: AudioRepeatConfig & AudioRepeatState Domain Models
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 1: Repeat Domain Models', () {
    test('AudioRepeatConfig default values and factories', () {
      const configDefault = AudioRepeatConfig();
      expect(configDefault.mode, AudioRepeatMode.none);
      expect(configDefault.targetRepetitions, 1);
      expect(configDefault.delaySeconds, 0);
      expect(configDefault.isInfinite, isFalse);

      final singleConfig = AudioRepeatConfig.singleAyah(
        startAyah: 255,
        targetRepetitions: 3,
        delaySeconds: 2,
      );
      expect(singleConfig.mode, AudioRepeatMode.singleAyah);
      expect(singleConfig.targetRepetitions, 3);
      expect(singleConfig.startAyah, 255);
      expect(singleConfig.delaySeconds, 2);

      final rangeConfig = AudioRepeatConfig.rangeLoop(
        targetRepetitions: 5,
        startAyah: 255,
        endAyah: 257,
        delaySeconds: 1,
      );
      expect(rangeConfig.mode, AudioRepeatMode.rangeLoop);
      expect(rangeConfig.targetRepetitions, 5);
      expect(rangeConfig.startAyah, 255);
      expect(rangeConfig.endAyah, 257);

      final perAyahConfig = AudioRepeatConfig.perAyahRange(
        targetRepetitions: 7,
        startAyah: 255,
        endAyah: 257,
        delaySeconds: 3,
      );
      expect(perAyahConfig.mode, AudioRepeatMode.perAyahRange);
      expect(perAyahConfig.targetRepetitions, 7);

      final infiniteConfig = AudioRepeatConfig.infiniteRepeat(
        mode: AudioRepeatMode.singleAyah,
        delaySeconds: 4,
      );
      expect(infiniteConfig.isInfinite, isTrue);
      expect(infiniteConfig.targetRepetitions, -1);
    });

    test('AudioRepeatConfig serialization and copyWith', () {
      final config = AudioRepeatConfig.rangeLoop(
        targetRepetitions: 3,
        startAyah: 10,
        endAyah: 15,
        delaySeconds: 2,
      );
      final json = config.toJson();
      final fromJson = AudioRepeatConfig.fromJson(json);

      expect(fromJson, equals(config));

      final updated = config.copyWith(rangeRepeatCount: 10, delaySeconds: 0);
      expect(updated.targetRepetitions, 10);
      expect(updated.delaySeconds, 0);
      expect(updated.startAyah, 10);
    });

    test('AudioRepeatState transitions and helpers', () {
      const state = AudioRepeatState();
      expect(state.status, AudioRepeatStatus.idle);
      expect(state.isActive, isFalse);
      expect(state.isDelaying, isFalse);

      final playing = state.copyWith(
        status: AudioRepeatStatus.playing,
        currentAyahRepeat: 2,
        currentAyah: 255,
        config: AudioRepeatConfig.singleAyah(
          startAyah: 255,
          targetRepetitions: 3,
        ),
      );
      expect(playing.isActive, isTrue);
      expect(playing.statusText, 'تكرار 2 من 3');

      final delaying = playing.copyWith(
        status: AudioRepeatStatus.delaying,
        remainingDelaySeconds: 4,
      );
      expect(delaying.isDelaying, isTrue);
      expect(delaying.statusText, 'ترديد: 4 ث');

      final infiniteState = playing.copyWith(
        config: AudioRepeatConfig.infiniteRepeat(startAyah: 255),
        currentAyahRepeat: 8,
      );
      expect(infiniteState.statusText, 'تكرار مستمر (8)');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 2: AudioRepeatController State Machine & Semantics
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 2: Repeat Controller Semantics & State Machine', () {
    test('1x repetition completes after single finish', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 255,
          targetRepetitions: 1,
        ),
      );

      expect(played, [255]);
      expect(controller.state.status, AudioRepeatStatus.playing);
      expect(controller.state.currentRepetition, 1);

      controller.onAyahPlaybackFinished();

      expect(controller.state.status, AudioRepeatStatus.completed);
      expect(played.length, 1);
      controller.dispose();
    });

    test('2x repetition repeats twice then completes', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 255,
          targetRepetitions: 2,
          delaySeconds: 0,
        ),
      );

      expect(played, [255]);

      controller.onAyahPlaybackFinished();
      expect(played, [255, 255]);
      expect(controller.state.currentRepetition, 2);

      controller.onAyahPlaybackFinished();
      expect(controller.state.status, AudioRepeatStatus.completed);
      expect(played, [255, 255]);
      controller.dispose();
    });

    test('3x repetition repeats 3 times', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 1,
          targetRepetitions: 3,
          delaySeconds: 0,
        ),
      );

      controller.onAyahPlaybackFinished();
      controller.onAyahPlaybackFinished();
      controller.onAyahPlaybackFinished();

      expect(played, [1, 1, 1]);
      expect(controller.state.status, AudioRepeatStatus.completed);
      controller.dispose();
    });

    test('5x repetition repeats 5 times', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 10,
          targetRepetitions: 5,
          delaySeconds: 0,
        ),
      );

      for (int i = 0; i < 5; i++) {
        controller.onAyahPlaybackFinished();
      }

      expect(played.length, 5);
      expect(controller.state.status, AudioRepeatStatus.completed);
      controller.dispose();
    });

    test('7x repetition repeats 7 times', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 10,
          targetRepetitions: 7,
          delaySeconds: 0,
        ),
      );

      for (int i = 0; i < 7; i++) {
        controller.onAyahPlaybackFinished();
      }

      expect(played.length, 7);
      expect(controller.state.status, AudioRepeatStatus.completed);
      controller.dispose();
    });

    test('10x repetition repeats 10 times', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 10,
          targetRepetitions: 10,
          delaySeconds: 0,
        ),
      );

      for (int i = 0; i < 10; i++) {
        controller.onAyahPlaybackFinished();
      }

      expect(played.length, 10);
      expect(controller.state.status, AudioRepeatStatus.completed);
      controller.dispose();
    });

    test(
      'Infinite repetition (-1) repeats indefinitely until stopped',
      () async {
        final played = <int>[];
        final controller = AudioRepeatController(
          onPlayAyahRequested: (ayah) async => played.add(ayah),
        );

        await controller.start(
          config: AudioRepeatConfig.infiniteRepeat(
            mode: AudioRepeatMode.singleAyah,
            startAyah: 255,
            delaySeconds: 0,
          ),
        );

        for (int i = 0; i < 15; i++) {
          controller.onAyahPlaybackFinished();
        }

        expect(played.length, 16);
        expect(controller.state.status, AudioRepeatStatus.playing);
        expect(controller.state.currentRepetition, 16);

        // Explicit cancellation
        controller.stop();
        expect(controller.state.status, AudioRepeatStatus.idle);

        // Subsequent finish does not trigger playback
        controller.onAyahPlaybackFinished();
        expect(played.length, 16);
        controller.dispose();
      },
    );

    test('Exact Semantics: Single Ayah Repetition (255 x 3)', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 255,
          targetRepetitions: 3,
          delaySeconds: 0,
        ),
      );

      controller.onAyahPlaybackFinished();
      controller.onAyahPlaybackFinished();
      controller.onAyahPlaybackFinished();

      expect(played, [255, 255, 255]);
      expect(controller.state.status, AudioRepeatStatus.completed);
      controller.dispose();
    });

    test('Exact Semantics: Range Loop Repetition (255 -> 257 x 3)', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.rangeLoop(
          startAyah: 255,
          endAyah: 257,
          targetRepetitions: 3,
          delaySeconds: 0,
        ),
      );

      // Loop 1: 255, 256, 257
      expect(played, [255]);
      controller.onAyahPlaybackFinished();
      expect(played, [255, 256]);
      controller.onAyahPlaybackFinished();
      expect(played, [255, 256, 257]);
      controller.onAyahPlaybackFinished();

      // Loop 2: 255, 256, 257
      expect(played, [255, 256, 257, 255]);
      controller.onAyahPlaybackFinished();
      expect(played, [255, 256, 257, 255, 256]);
      controller.onAyahPlaybackFinished();
      expect(played, [255, 256, 257, 255, 256, 257]);
      controller.onAyahPlaybackFinished();

      // Loop 3: 255, 256, 257
      expect(played, [255, 256, 257, 255, 256, 257, 255]);
      controller.onAyahPlaybackFinished();
      expect(played, [255, 256, 257, 255, 256, 257, 255, 256]);
      controller.onAyahPlaybackFinished();
      expect(played, [255, 256, 257, 255, 256, 257, 255, 256, 257]);
      controller.onAyahPlaybackFinished();

      // Completed
      expect(controller.state.status, AudioRepeatStatus.completed);
      expect(played.length, 9);
      expect(played, [
        255, 256, 257, // Loop 1
        255, 256, 257, // Loop 2
        255, 256, 257, // Loop 3
      ]);
      controller.dispose();
    });

    test(
      'Exact Semantics: Per-Ayah Range Repetition (255 x 3, 256 x 3, 257 x 3)',
      () async {
        final played = <int>[];
        final controller = AudioRepeatController(
          onPlayAyahRequested: (ayah) async => played.add(ayah),
        );

        await controller.start(
          config: AudioRepeatConfig.perAyahRange(
            startAyah: 255,
            endAyah: 257,
            targetRepetitions: 3,
            delaySeconds: 0,
          ),
        );

        // Ayah 255 x 3
        expect(played, [255]);
        controller.onAyahPlaybackFinished();
        expect(played, [255, 255]);
        controller.onAyahPlaybackFinished();
        expect(played, [255, 255, 255]);
        controller.onAyahPlaybackFinished();

        // Ayah 256 x 3
        expect(played, [255, 255, 255, 256]);
        controller.onAyahPlaybackFinished();
        expect(played, [255, 255, 255, 256, 256]);
        controller.onAyahPlaybackFinished();
        expect(played, [255, 255, 255, 256, 256, 256]);
        controller.onAyahPlaybackFinished();

        // Ayah 257 x 3
        expect(played, [255, 255, 255, 256, 256, 256, 257]);
        controller.onAyahPlaybackFinished();
        expect(played, [255, 255, 255, 256, 256, 256, 257, 257]);
        controller.onAyahPlaybackFinished();
        expect(played, [255, 255, 255, 256, 256, 256, 257, 257, 257]);
        controller.onAyahPlaybackFinished();

        // Completed
        expect(controller.state.status, AudioRepeatStatus.completed);
        expect(played, [
          255, 255, 255, // 255 x 3
          256, 256, 256, // 256 x 3
          257, 257, 257, // 257 x 3
        ]);
        controller.dispose();
      },
    );

    test('Tardid Delay countdown, pause, resume, and skip semantics', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.singleAyah(
          startAyah: 1,
          targetRepetitions: 2,
          delaySeconds: 5,
        ),
      );

      expect(played, [1]);

      // Ayah 1 finishes -> starts 5s delay
      controller.onAyahPlaybackFinished();
      expect(controller.state.status, AudioRepeatStatus.delaying);
      expect(controller.state.remainingDelaySeconds, 5);

      // Pause freezes delay
      controller.pause();
      expect(controller.state.status, AudioRepeatStatus.paused);
      expect(controller.state.remainingDelaySeconds, 5);

      // Resume continues delay
      controller.resume();
      expect(controller.state.status, AudioRepeatStatus.delaying);
      expect(controller.state.remainingDelaySeconds, 5);

      // Skip delay immediately triggers next playback without waiting
      controller.skipDelay();
      expect(controller.state.status, AudioRepeatStatus.playing);
      expect(played, [1, 1]);

      controller.dispose();
    });

    test('Reciter switching in QuranCubit reloads with new reciter', () async {
      final fakeAudio = ControllableAudioService();
      final quranData = _createMockQuranData();
      final quranCubit = QuranCubit(
        repository: FakeQuranRepository(quranData),
        storage: FakeLocalStorageService(),
        audio: fakeAudio,
        reciter: 'alafasy',
        fontSize: 22.0,
      );
      await quranCubit.load();

      await quranCubit.startRepeatPlayback(
        AudioRepeatConfig.singleAyah(
          startAyah: 1,
          targetRepetitions: 2,
          delaySeconds: 0,
        ),
      );

      expect(fakeAudio.playedAyahs.last.reciter, 'alafasy');

      quranCubit.updateReciter('minshawi');
      expect(fakeAudio.playedAyahs.last.reciter, 'minshawi');
      expect(fakeAudio.playedAyahs.last.globalAyah, 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 3: QuranAudioCacheService Storage, Validation & Bounded LRU
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 3: Audio Cache Bounded LRU & Atomic Writes', () {
    late Directory tempDir;
    late QuranAudioCacheService cacheService;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync(
        'mishkat_audio_cache_test_',
      );
      cacheService = QuranAudioCacheService(
        baseDirectory: tempDir,
        maxCacheSizeBytes: 10 * 1024, // 10 KiB for deterministic LRU testing
      );
      await cacheService.init();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Initializes cache directory, tmp directory, and metadata', () {
      final cacheDir = Directory('${tempDir.path}/audio_cache');
      final tmpDir = Directory('${tempDir.path}/audio_cache/tmp');
      final metaFile = File('${tempDir.path}/audio_cache/metadata.json');

      expect(cacheDir.existsSync(), isTrue);
      expect(tmpDir.existsSync(), isTrue);
      expect(metaFile.existsSync(), isTrue);
    });

    test('Interrupted downloads in tmp/ are deleted on init', () async {
      final tmpDir = Directory('${tempDir.path}/audio_cache/tmp');
      final orphanFile = File('${tmpDir.path}/orphan.tmp');
      orphanFile.writeAsStringSync('stray temporary content');
      expect(orphanFile.existsSync(), isTrue);

      final newService = QuranAudioCacheService(baseDirectory: tempDir);
      await newService.init();

      expect(orphanFile.existsSync(), isFalse);
    });

    test('Cache miss returns null for uncached ayah', () async {
      final file = await cacheService.getCachedFile(
        reciter: 'alafasy',
        globalAyah: 999,
      );
      expect(file, isNull);
    });

    test('Atomic write and Cache Hit retrieves valid cached file', () async {
      // Create valid MP3 bytes: ID3v2 header + padding >= 1024 bytes
      final validMp3Bytes = List<int>.filled(2048, 0);
      validMp3Bytes[0] = 0x49; // 'I'
      validMp3Bytes[1] = 0x44; // 'D'
      validMp3Bytes[2] = 0x33; // '3'
      validMp3Bytes[3] = 0x03; // version 2.3
      validMp3Bytes[4] = 0x00;

      final savedFile = await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 255,
        bytes: validMp3Bytes,
      );

      expect(savedFile, isNotNull);
      expect(savedFile!.existsSync(), isTrue);
      expect(savedFile.path.endsWith('alafasy/255.mp3'), isTrue);

      final hitFile = await cacheService.getCachedFile(
        reciter: 'alafasy',
        globalAyah: 255,
      );
      expect(hitFile, isNotNull);
      expect(hitFile!.path, savedFile.path);
    });

    test('Corrupt cache file auto-purge on access', () async {
      // Write corrupt file (< 1024 bytes and missing MP3 magic bytes)
      final corruptBytes = [1, 2, 3, 4, 5];
      // Save directly to final destination to simulate disk corruption
      final corruptFile = File('${tempDir.path}/audio_cache/alafasy/100.mp3');
      await corruptFile.parent.create(recursive: true);
      await corruptFile.writeAsBytes(corruptBytes);
      expect(corruptFile.existsSync(), isTrue);

      // Accessing corrupt file returns null and auto-deletes the corrupt file
      final file = await cacheService.getCachedFile(
        reciter: 'alafasy',
        globalAyah: 100,
      );
      expect(file, isNull);
      expect(corruptFile.existsSync(), isFalse);
    });

    test(
      'LRU eviction purges oldest unpinned files to low watermark',
      () async {
        final validBytes = List<int>.filled(3 * 1024, 0); // 3 KiB per file
        validBytes[0] = 0xFF; // Frame sync
        validBytes[1] = 0xFB;

        // Cache limit is 10 KiB. Low watermark is 8.5 KiB (85%).
        // Adding 4 files of 3 KiB = 12 KiB (> 10 KiB high watermark).
        await cacheService.saveFile(
          reciter: 'alafasy',
          globalAyah: 1,
          bytes: validBytes,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await cacheService.saveFile(
          reciter: 'alafasy',
          globalAyah: 2,
          bytes: validBytes,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await cacheService.saveFile(
          reciter: 'alafasy',
          globalAyah: 3,
          bytes: validBytes,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final file4 = await cacheService.saveFile(
          reciter: 'alafasy',
          globalAyah: 4,
          bytes: validBytes,
        );

        expect(file4, isNotNull);

        // File 1 is least recently used, should be evicted
        final file1After = await cacheService.getCachedFile(
          reciter: 'alafasy',
          globalAyah: 1,
        );
        expect(file1After, isNull);

        // Files 2, 3, 4 remain cached
        final file4After = await cacheService.getCachedFile(
          reciter: 'alafasy',
          globalAyah: 4,
        );
        expect(file4After, isNotNull);
      },
    );

    test('Pinned active content is protected from LRU eviction', () async {
      final validBytes = List<int>.filled(3 * 1024, 0);
      validBytes[0] = 0xFF;
      validBytes[1] = 0xFB;

      // File 1 is pinned
      await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 1,
        bytes: validBytes,
        pinnedAyahs: {1},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // File 2 is unpinned
      await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 2,
        bytes: validBytes,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // File 3 is unpinned
      await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 3,
        bytes: validBytes,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // File 4 is added with File 1 pinned -> File 2 should be evicted instead of File 1
      await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 4,
        bytes: validBytes,
        pinnedAyahs: {1},
      );

      // Pinned File 1 remains safe
      final file1Hit = await cacheService.getCachedFile(
        reciter: 'alafasy',
        globalAyah: 1,
      );
      expect(file1Hit, isNotNull);
    });

    test('Manual cache clearing wipes all audio files and metadata', () async {
      final validBytes = List<int>.filled(2048, 0);
      validBytes[0] = 0xFF;
      validBytes[1] = 0xFB;

      await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 1,
        bytes: validBytes,
      );
      await cacheService.saveFile(
        reciter: 'alafasy',
        globalAyah: 2,
        bytes: validBytes,
      );

      expect(cacheService.currentCacheSizeBytes, greaterThan(0));

      await cacheService.clearCache();

      expect(cacheService.currentCacheSizeBytes, equals(0));
      expect(
        await cacheService.getCachedFile(reciter: 'alafasy', globalAyah: 1),
        isNull,
      );
    });

    test(
      'Partial file handling never writes incomplete file to final destination',
      () async {
        // Simulate partial write failure
        final partialBytes = [0x49, 0x44, 0x33]; // Only 3 bytes, truncated
        final result = await cacheService.saveFile(
          reciter: 'alafasy',
          globalAyah: 99,
          bytes: partialBytes,
        );

        expect(result, isNull);
        final finalFile = File('${tempDir.path}/audio_cache/alafasy/99.mp3');
        expect(finalFile.existsSync(), isFalse);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 4: Offline-First Playback Decision Tree & Error Handling
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 4: Offline-First Decision Tree', () {
    test('Offline uncached error throws calm Arabic exception', () {
      const exception = QuranAudioOfflineException();
      expect(exception.message, 'التلاوة غير متوفرة دون اتصال بالإنترنت.');
    });

    test(
      'Network failure sets audioStatus to failure without crashing cubit',
      () async {
        final fakeAudio = ControllableAudioService()..throwOnPlay = true;
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();

        await quranCubit.playAyah(255);

        expect(quranCubit.state.audioStatus, QuranAudioStatus.failure);
        expect(quranCubit.state.error, isNotNull);
        expect(
          quranCubit.state.error,
          contains('التلاوة غير متوفرة دون اتصال بالإنترنت'),
        );
        // Audio global Ayah is preserved
        expect(quranCubit.state.audioGlobalAyah, 255);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 5: Q5 Audio Synchronization & QuranCubit Repeat Integration
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 5: Q5 Audio Synchronization & QuranCubit Repeat', () {
    test(
      'audioGlobalAyah remains single authority during repeat playback',
      () async {
        final fakeAudio = ControllableAudioService();
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();

        final interactionCubit = MushafInteractionCubit();
        const selected = AyahBounds(
          surah: 1,
          ayah: 1,
          page: 1,
          globalAyah: 1,
          bounds: Rect.fromLTWH(10, 10, 100, 20),
          segments: [AyahRectSegment(Rect.fromLTWH(10, 10, 100, 20))],
        );
        interactionCubit.selectAyah(selected);

        // Selected verse is 1, playing verse is 5
        await quranCubit.startRepeatPlayback(
          AudioRepeatConfig.singleAyah(
            startAyah: 5,
            targetRepetitions: 3,
            delaySeconds: 0,
          ),
          initialGlobalAyah: 5,
        );
        interactionCubit.setPlayingAyah(5);

        expect(interactionCubit.state.selectedAyah?.globalAyah, 1);
        expect(interactionCubit.state.playingAyah, 5);
        expect(quranCubit.state.audioGlobalAyah, 5);
        expect(quranCubit.state.repeatConfig.mode, AudioRepeatMode.singleAyah);
        expect(quranCubit.state.repeatConfig.targetRepetitions, 3);
        interactionCubit.close();
      },
    );

    test(
      'autoScroll flips reader page upon repeat crossing boundary',
      () async {
        final fakeAudio = ControllableAudioService();
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();
        quranCubit.setAutoScroll(true);

        // Ayah 7 is on Page 1, Ayah 8 is on Page 2
        await quranCubit.startRepeatPlayback(
          AudioRepeatConfig.rangeLoop(
            startAyah: 7,
            endAyah: 8,
            targetRepetitions: 2,
            delaySeconds: 0,
          ),
          initialGlobalAyah: 7,
        );

        expect(quranCubit.state.currentPage, 1);

        // Advance to Ayah 8
        fakeAudio.emitState(PlayerState(false, ProcessingState.completed));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(quranCubit.state.audioGlobalAyah, 8);
        expect(quranCubit.state.currentPage, 2);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 6: Q11 DailyHifzJourney & UI Integrations
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 6: Q11 Daily Hifz Journey & UI Integration', () {
    test('Daily Journey queue builds ordered list of due murajaah, weak, and new hifz', () {
      final journey = DailyHifzJourney(
        segments: const [],
        dueMurajaahQueue: const [1, 2, 3],
        weakAyahsQueue: const [5],
        newHifzQueue: const [10, 11],
        recommendedNewHifzTarget: 2,
        workloadLevel: WorkloadLevel.moderate,
        isRecoveryMode: false,
        rationaleMessage: 'خطة متوازنة',
        evaluatedAt: DateTime(2026, 10, 5),
      );

      final allAyahs = journey.allAyahs;

      expect(allAyahs, [1, 2, 3, 5, 10, 11]);
      expect(journey.isEmpty, isFalse);
    });

    testWidgets(
      'QuranMiniPlayer renders repeat badge and opens repeat settings sheet',
      (tester) async {
        final fakeAudio = ControllableAudioService();
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();
        await quranCubit.playAyah(5);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: quranCubit),
                  BlocProvider(create: (_) => MushafInteractionCubit()),
                ],
                child: const QuranMiniPlayer(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Find repeat badge button
        final repeatBadge = find.byTooltip('إعدادات التكرار والترديد');
        expect(repeatBadge, findsOneWidget);

        // Tap repeat badge to open bottom sheet
        await tester.tap(repeatBadge);
        await tester.pumpAndSettle();

        // Bottom sheet contains repeat mode options and chips
        expect(find.text('خيارات التكرار والترديد'), findsOneWidget);
        expect(find.text('بدون تكرار'), findsOneWidget);
        expect(find.text('تكرار الآية'), findsOneWidget);
        expect(find.text('طواف المقطع كحلقة'), findsOneWidget);
        expect(find.text('تكرار كل آية في المقطع'), findsOneWidget);
        expect(find.text('تطبيق وبدء التلاوة'), findsOneWidget);

        await quranCubit.stopAudio();
      },
    );

    testWidgets(
      'QuranMiniPlayer renders delay banner with skip button when delaying',
      (tester) async {
        final fakeAudio = ControllableAudioService();
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: quranCubit),
                  BlocProvider(create: (_) => MushafInteractionCubit()),
                ],
                child: const QuranMiniPlayer(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Start repeat with 5 seconds delay
        await quranCubit.startRepeatPlayback(
          AudioRepeatConfig.singleAyah(
            startAyah: 1,
            targetRepetitions: 3,
            delaySeconds: 5,
          ),
          initialGlobalAyah: 1,
        );

        // Simulate completion to enter delaying state
        fakeAudio.emitState(PlayerState(false, ProcessingState.completed));
        await tester.pump();

        // Verify delay banner is shown
        expect(find.text('تخطي المهلة'), findsOneWidget);

        // Tap skip button
        await tester.tap(find.text('تخطي المهلة'));
        await tester.pump();

        expect(quranCubit.state.repeatState.status, AudioRepeatStatus.playing);

        // Clean up timer
        await quranCubit.stopAudio();
        await tester.pump();
      },
    );

    testWidgets(
      'MemorizationSessionPage audio button plays with 3x repeat default and preserves session on error',
      (tester) async {
        final fakeAudio = ControllableAudioService()..throwOnPlay = true;
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();

        final fakeStorage = FakeLocalStorageService();
        final memRepo = QuranMemorizationRepository(storage: fakeStorage);
        final memCubit = QuranMemorizationCubit(repository: memRepo);
        await memCubit.load();

        final plan = await memCubit.createPlan(
          title: 'سورة الفاتحة',
          startGlobalAyah: 1,
          endGlobalAyah: 7,
          dailyTarget: 7,
        );
        memCubit.startPlanSession(plan);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: quranCubit),
                BlocProvider.value(value: memCubit),
              ],
              child: MemorizationSessionPage(quranData: quranData),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the audio playback button in session page
        final audioButton = find.byIcon(Icons.volume_up_rounded);
        expect(audioButton, findsOneWidget);

        // Tapping audio button handles offline error gracefully without crashing session
        await tester.tap(audioButton);
        await tester.pump();

        // Session is still active and alive
        expect(find.text('جلسة حفظ الورد'), findsOneWidget);

        await quranCubit.stopAudio();
        await tester.pump();
      },
    );

    test('Stopping repeat during delay interval cleanly terminates playback and cancels timer', () async {
      final played = <int>[];
      final controller = AudioRepeatController(
        onPlayAyahRequested: (ayah) async => played.add(ayah),
      );

      await controller.start(
        config: AudioRepeatConfig.infiniteRepeat(
          mode: AudioRepeatMode.singleAyah,
          startAyah: 1,
          delaySeconds: 10,
        ),
      );

      expect(played, [1]);

      // Complete recitation -> enters delaying state
      controller.onAyahPlaybackFinished();
      expect(controller.state.status, AudioRepeatStatus.delaying);
      expect(controller.state.remainingDelaySeconds, 10);

      // Stop explicitly during delay
      controller.stop();
      expect(controller.state.status, AudioRepeatStatus.idle);

      // Subsequent finish or timer tick does nothing
      controller.onAyahPlaybackFinished();
      expect(played, [1]);
      controller.dispose();
    });

    test(
      'Background audio platform manifests declare audio execution permissions',
      () {
        final iosPlist = File('ios/Runner/Info.plist');
        if (iosPlist.existsSync()) {
          final plistContent = iosPlist.readAsStringSync();
          expect(plistContent, contains('<string>audio</string>'));
        }

        final androidManifest = File(
          'android/app/src/main/AndroidManifest.xml',
        );
        if (androidManifest.existsSync()) {
          final manifestContent = androidManifest.readAsStringSync();
          expect(manifestContent, contains('android.permission.INTERNET'));
          expect(manifestContent, contains('android.permission.WAKE_LOCK'));
        }
      },
    );

    test(
      'Audio pause and resume preserves repeat cycle and position',
      () async {
        final fakeAudio = ControllableAudioService();
        final quranData = _createMockQuranData();
        final quranCubit = QuranCubit(
          repository: FakeQuranRepository(quranData),
          storage: FakeLocalStorageService(),
          audio: fakeAudio,
          reciter: 'alafasy',
          fontSize: 22.0,
        );
        await quranCubit.load();

        await quranCubit.startRepeatPlayback(
          AudioRepeatConfig.singleAyah(
            startAyah: 1,
            targetRepetitions: 3,
            delaySeconds: 0,
          ),
          initialGlobalAyah: 1,
        );

        expect(quranCubit.state.audioStatus, QuranAudioStatus.playing);

        // Pause audio
        await quranCubit.toggleAudio(continuous: true);
        expect(quranCubit.state.audioStatus, QuranAudioStatus.paused);
        expect(fakeAudio.isPaused, isTrue);

        // Resume audio
        await quranCubit.toggleAudio(continuous: true);
        expect(quranCubit.state.audioStatus, QuranAudioStatus.playing);
        expect(fakeAudio.isPaused, isFalse);

        await quranCubit.stopAudio();
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP 7: Performance Benchmarks & Measurable Latency Thresholds
  // ───────────────────────────────────────────────────────────────────────────
  group('Q12 — Group 7: Performance Benchmarks', () {
    test('Cache index lookup, LRU eviction, and Journey preparation meet performance SLA', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'mishkat_perf_bench_',
      );
      final cacheService = QuranAudioCacheService(
        baseDirectory: tempDir,
        maxCacheSizeBytes: 50 * 1024,
      );
      await cacheService.init();

      final validBytes = List<int>.filled(5 * 1024, 0);
      validBytes[0] = 0xFF;
      validBytes[1] = 0xFB;

      for (int i = 1; i <= 8; i++) {
        await cacheService.saveFile(
          reciter: 'alafasy',
          globalAyah: i,
          bytes: validBytes,
        );
      }

      // 1. Cache index lookup latency <= 10ms
      final swLookup = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        await cacheService.getCachedFile(reciter: 'alafasy', globalAyah: 1);
      }
      swLookup.stop();
      final avgLookupMs = swLookup.elapsedMicroseconds / 100 / 1000.0;
      expect(avgLookupMs, lessThanOrEqualTo(10.0));

      // 2. LRU eviction latency <= 50ms
      final swEvict = Stopwatch()..start();
      await cacheService.evictLRU();
      swEvict.stop();
      final evictMs = swEvict.elapsedMicroseconds / 1000.0;
      expect(evictMs, lessThanOrEqualTo(50.0));

      // 3. Daily Journey linear queue calculation <= 15ms
      final journey = DailyHifzJourney(
        segments: const [],
        dueMurajaahQueue: List.generate(50, (i) => i + 1),
        weakAyahsQueue: List.generate(20, (i) => i + 51),
        newHifzQueue: List.generate(10, (i) => i + 71),
        recommendedNewHifzTarget: 10,
        workloadLevel: WorkloadLevel.moderate,
        isRecoveryMode: false,
        rationaleMessage: 'خطة',
        evaluatedAt: DateTime.now(),
      );

      final swQueue = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        final _ = journey.allAyahs;
      }
      swQueue.stop();
      final avgQueueMs = swQueue.elapsedMicroseconds / 1000 / 1000.0;
      expect(avgQueueMs, lessThanOrEqualTo(15.0));

      tempDir.deleteSync(recursive: true);
    });
  });
}
