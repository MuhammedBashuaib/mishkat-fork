import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/quran_audio_station.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';

class _RadioAudioService implements QuranAudioService {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final playedUrls = <String>[];
  Future<void> Function(String)? onPlay;
  bool playing = false;
  int pauseCalls = 0;

  void emit(PlayerState state) {
    playing = state.playing;
    _states.add(state);
  }

  // Matches the legacy test adapter supported by QuranAudioStreamExtension.
  Future<void> playStreamUrl(String url) async {
    playedUrls.add(url);
    if (onPlay case final handler?) {
      await handler(url);
    } else {
      emit(PlayerState(true, ProcessingState.ready));
    }
  }

  @override
  Stream<PlayerState> get playerState => _states.stream;
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  bool get isPlaying => playing;
  @override
  Duration? get duration => null;
  @override
  Duration get currentPosition => Duration.zero;
  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async => throw UnimplementedError('Radio-only test adapter');
  @override
  Future<void> pause() async {
    pauseCalls++;
    emit(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> resume() async => emit(PlayerState(true, ProcessingState.ready));
  @override
  Future<void> stop() async => emit(PlayerState(false, ProcessingState.idle));
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async => _states.close();
}

void main() {
  final stations = QuranAudioStation.defaultCatalog
      .where((station) => station.isAudioPlayable)
      .take(2)
      .toList();
  final first = stations[0];
  final second = stations[1];
  late _RadioAudioService audio;
  late QuranCubit cubit;

  setUp(() {
    audio = _RadioAudioService();
    cubit = QuranCubit(
      repository: QuranRepository(),
      storage: LocalStorageService(),
      audio: audio,
      reciter: 'ar.alafasy',
      fontSize: 32,
    );
  });
  tearDown(() => cubit.close());

  test(
    'timeout keeps a retryable station even after a late idle event',
    () async {
      audio.onPlay = (_) async => throw TimeoutException('Stream preparation');

      await cubit.playStation(first);

      expect(cubit.state.audioStatus, QuranAudioStatus.failure);
      expect(cubit.state.error, contains('وقتاً طويلاً'));
      expect(cubit.state.error, contains('للمحاولة مجدداً'));
      expect(cubit.state.activeStation, first);
      audio.emit(PlayerState(false, ProcessingState.idle));
      expect(cubit.state.audioStatus, QuranAudioStatus.failure);
      expect(cubit.state.activeStation, first);

      await cubit.stopAudio();
      expect(cubit.state.audioStatus, QuranAudioStatus.idle);
      expect(cubit.state.activeStation, isNull);
    },
  );

  test('adapter load errors propagate to the station failure state', () async {
    audio.onPlay = (_) async => throw StateError('Cannot decode stream');

    await cubit.playStation(first);

    expect(cubit.state.audioStatus, QuranAudioStatus.failure);
    expect(cubit.state.error, contains('تعذّر الاتصال بالبث المباشر'));
    expect(cubit.state.activeStation, first);
  });

  test('offline radio errors retain their explanatory message', () async {
    audio.onPlay = (_) async =>
        throw const QuranAudioOfflineException('البث يحتاج اتصالاً بالإنترنت.');

    await cubit.playStation(first);

    expect(cubit.state.audioStatus, QuranAudioStatus.failure);
    expect(cubit.state.error, 'البث يحتاج اتصالاً بالإنترنت.');
  });

  test(
    'timeout from a replaced station cannot overwrite the new one',
    () async {
      final firstLoad = Completer<void>();
      audio.onPlay = (url) async {
        if (url == first.streamUrl) {
          await firstLoad.future;
        } else {
          audio.emit(PlayerState(true, ProcessingState.ready));
        }
      };

      final pending = cubit.playStation(first);
      await cubit.playStation(second);
      firstLoad.completeError(TimeoutException('Old stream preparation'));
      await pending;

      expect(cubit.state.audioStatus, QuranAudioStatus.playing);
      expect(cubit.state.activeStation, second);
      expect(cubit.state.error, isNull);
    },
  );

  test(
    'play retries failure even when the player retains its playing flag',
    () async {
      audio.onPlay = (_) async {
        audio.playing = true;
        throw TimeoutException('Stream preparation');
      };
      await cubit.playStation(first);
      audio.onPlay = null;

      await cubit.toggleAudio(continuous: false);

      expect(audio.playedUrls, [first.streamUrl, first.streamUrl]);
      expect(audio.pauseCalls, 0);
      expect(cubit.state.audioStatus, QuranAudioStatus.playing);
      expect(cubit.state.activeStation, first);
      expect(cubit.state.error, isNull);
    },
  );

  test(
    'radio buffering stays loading and pausing preserves the paused state',
    () async {
      audio.onPlay = (_) async {};
      await cubit.playStation(first);
      audio.emit(PlayerState(false, ProcessingState.ready));
      expect(cubit.state.audioStatus, QuranAudioStatus.loading);
      audio.emit(PlayerState(true, ProcessingState.loading));
      expect(cubit.state.audioStatus, QuranAudioStatus.loading);
      audio.emit(PlayerState(true, ProcessingState.buffering));
      expect(cubit.state.audioStatus, QuranAudioStatus.loading);
      audio.emit(PlayerState(true, ProcessingState.ready));
      expect(cubit.state.audioStatus, QuranAudioStatus.playing);
      audio.emit(PlayerState(true, ProcessingState.buffering));
      expect(cubit.state.audioStatus, QuranAudioStatus.loading);

      await cubit.toggleAudio(continuous: false);
      expect(cubit.state.audioStatus, QuranAudioStatus.paused);
      audio.emit(PlayerState(false, ProcessingState.buffering));
      expect(cubit.state.audioStatus, QuranAudioStatus.paused);
      audio.emit(PlayerState(false, ProcessingState.ready));
      expect(cubit.state.audioStatus, QuranAudioStatus.paused);

      await cubit.toggleAudio(continuous: false);
      expect(cubit.state.audioStatus, QuranAudioStatus.playing);
    },
  );

  test('stopping a pending station ignores its later timeout', () async {
    final load = Completer<void>();
    audio.onPlay = (_) => load.future;
    final pending = cubit.playStation(first);
    await cubit.stopAudio();
    load.completeError(TimeoutException('Cancelled stream preparation'));
    await pending;

    expect(cubit.state.audioStatus, QuranAudioStatus.idle);
    expect(cubit.state.activeStation, isNull);
    expect(cubit.state.error, isNull);
  });
}
