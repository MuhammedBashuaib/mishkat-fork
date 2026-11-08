import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:mishkat_app/core/constants/app_constants.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';

class _Player implements AudioPlayer {
  final sources = <AudioSource>[];
  final speeds = <double>[];
  final loadStarted = Completer<void>();
  final playback = Completer<void>();
  final nativeErrors = StreamController<PlayerException>.broadcast();
  Future<Duration?> Function()? onLoad;
  Future<void> Function()? onPlay;
  int playCalls = 0;
  int stopCalls = 0;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) {
    sources.add(source);
    if (!loadStarted.isCompleted) loadStarted.complete();
    return onLoad?.call() ?? Future<Duration?>.value();
  }

  @override
  Future<void> play() {
    playCalls++;
    return onPlay?.call() ?? playback.future;
  }

  @override
  Stream<PlayerException> get errorStream => nativeErrors.stream;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  @override
  Future<void> dispose() async {
    if (!playback.isCompleted) playback.complete();
    await nativeErrors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReaderOnlyService implements QuranAudioService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements QuranAudioCacheService {
  Future<bool> Function() checkConnection = () async => true;
  bool failStorage = false;

  @override
  Future<bool> isNetworkAvailable() => checkConnection();

  @override
  Future<File?> getCachedFile({
    required String reciter,
    required int globalAyah,
    bool updateAccessTime = true,
  }) async {
    if (failStorage) throw const FileSystemException('Cache is unwritable');
    return null;
  }

  @override
  Future<File?> cacheAyah({
    required String reciter,
    required int globalAyah,
    Set<int> pinnedAyahs = const {},
    bool pin = false,
  }) async {
    if (failStorage) throw const FileSystemException('Cache is unwritable');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  late _Player player;
  late _Cache cache;
  late QuranAudioService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sessionChannel, (_) async => null);
    player = _Player();
    cache = _Cache();
    service = QuranAudioService(
      player: player,
      cacheService: cache,
      streamLoadTimeout: const Duration(milliseconds: 100),
    );
  });

  tearDown(() async {
    await service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sessionChannel, null);
  });

  test('all catalog reciters have independent complete-surah recordings', () {
    final urls = <String>{};
    for (final reciter in AppConstants.reciters) {
      final url = QuranSurahAudioUrlBuilder.buildUrl(
        reciter: reciter.id,
        surah: 2,
      );
      expect(Uri.parse(url).scheme, 'https');
      expect(url, isNot(contains('/quran/audio/')));
      expect(url, isNot(contains('everyayah.com')));
      urls.add(url);
    }
    expect(urls, hasLength(AppConstants.reciters.length));
  });

  test(
    'reader-only service fakes expose an empty compatible error stream',
    () async {
      expect(await _ReaderOnlyService().playbackErrors.toList(), isEmpty);
    },
  );

  test(
    'a native error and matching play Future failure are reported once',
    () async {
      final received = <Object>[];
      final subscription = service.playbackErrors.listen(received.add);
      final playing = Completer<void>();
      player.onPlay = () => playing.future;
      await service.playSurah(reciter: 'ar.alafasy', surah: 2);

      final error = PlayerException(2, 'Playback connection lost', 0);
      player.nativeErrors.add(error);
      playing.completeError(error);
      await Future<void>.delayed(Duration.zero);

      expect(received, [same(error)]);
      await subscription.cancel();
    },
  );

  test(
    'a runtime failure from an old play Future cannot fail the new source',
    () async {
      final received = <Object>[];
      final subscription = service.playbackErrors.listen(received.add);
      final oldPlaying = Completer<void>();
      player.onPlay = () => oldPlaying.future;
      await service.playSurah(reciter: 'ar.alafasy', surah: 2);
      player.onPlay = null;
      await service.playWord(surah: 1, ayah: 1, word: 1);

      oldPlaying.completeError(PlayerException(2, 'Old source failed', 0));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      final newError = PlayerException(2, 'Current word failed', 0);
      player.nativeErrors.add(newError);
      await Future<void>.delayed(Duration.zero);
      expect(received, [same(newError)]);
      await subscription.cancel();
    },
  );

  test('late native errors after explicit stop are ignored', () async {
    final received = <Object>[];
    final subscription = service.playbackErrors.listen(received.add);
    await service.playSurah(reciter: 'ar.alafasy', surah: 2);
    await service.stop();
    player.nativeErrors.add(PlayerException(2, 'Stopped source', 0));
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
    await subscription.cancel();
  });

  test(
    'resume reports asynchronous playback failure without uncaught errors',
    () async {
      final received = <Object>[];
      final subscription = service.playbackErrors.listen(received.add);
      await service.playSurah(reciter: 'ar.alafasy', surah: 2);
      final error = PlayerException(2, 'Resume failed', 0);
      player.onPlay = () => Future<void>.error(error);
      await service.resume();
      await Future<void>.delayed(Duration.zero);
      expect(received, [same(error)]);
      await subscription.cancel();
    },
  );

  test('continuous audio uses reciter and style specific editions', () {
    expect(
      QuranSurahAudioUrlBuilder.buildUrl(reciter: 'ar.parhizgar', surah: 114),
      'https://cdn.islamic.network/quran/audio-surah/'
      '128/ar.shahriarparhizgar/114.mp3',
    );
    expect(
      QuranSurahAudioUrlBuilder.buildUrl(
        reciter: 'ar.abdulbasitmurattal',
        surah: 2,
      ),
      'https://cdn.mp3quran.net/audio/abdulbasit-abdulsamad/r3/002.mp3',
    );
    expect(
      QuranSurahAudioUrlBuilder.buildUrl(reciter: 'ar.abdulsamad', surah: 2),
      'https://cdn.mp3quran.net/audio/abdulbasit-abdulsamad/r1/002.mp3',
    );
  });

  test('a Surah starts one uncut source with lock-screen metadata', () async {
    await service.playSurah(reciter: 'ar.alafasy', surah: 2, title: 'البقرة');
    final source = player.sources.single as UriAudioSource;
    expect(source, isNot(isA<ClippingAudioSource>()));
    expect(source.uri.path, '/audio/mishary-alafasy/r1/002.mp3');
    final item = source.tag as MediaItem;
    expect(item.title, 'البقرة');
    expect(item.artist, 'مشاري العفاسي');
    expect(item.extras, {'kind': 'surah', 'surah': 2});
    expect(item.isLive, false);
    expect(player.playCalls, 1);
    expect(player.stopCalls, 1);
    expect(player.playback.isCompleted, false);
  });

  test(
    'word plays one-based pronunciation and resets listening speed',
    () async {
      await service.setPlaybackSpeed(1.5);
      await service.playWord(surah: 2, ayah: 255, word: 9);
      final source = player.sources.single as UriAudioSource;
      expect(
        source.uri.toString(),
        'https://audio.qurancdn.com/wbw/002_255_009.mp3',
      );
      final item = source.tag as MediaItem;
      expect(item.artist, contains('Quran.com'));
      expect(item.extras, {'kind': 'word', 'surah': 2, 'ayah': 255, 'word': 9});
      expect(player.speeds, [1.5, 1.0]);
      expect(player.playCalls, 1);
    },
  );

  test('reader Ayah resets the dedicated listening playback speed', () async {
    await service.setPlaybackSpeed(0.75);
    await service.playAyah(reciter: 'ar.alafasy', globalAyah: 262);
    expect(player.speeds, [0.75, 1.0]);
    expect(player.playCalls, 1);
  });

  test(
    'unwritable optional cache does not prevent online Ayah playback',
    () async {
      cache.failStorage = true;
      await service.playAyah(reciter: 'ar.alafasy', globalAyah: 262);
      await Future<void>.delayed(Duration.zero);
      expect((player.sources.single as UriAudioSource).uri.scheme, 'https');
      expect(player.playCalls, 1);
    },
  );

  test('invalid addresses and speed fail before touching playback', () async {
    await expectLater(
      service.playSurah(reciter: 'ar.alafasy', surah: 0),
      throwsRangeError,
    );
    await expectLater(
      service.playWord(surah: 1, ayah: 8, word: 1),
      throwsRangeError,
    );
    await expectLater(
      service.playWord(surah: 1, ayah: 1, word: 0),
      throwsRangeError,
    );
    await expectLater(
      service.setPlaybackSpeed(double.nan),
      throwsArgumentError,
    );
    await expectLater(service.setPlaybackSpeed(0.1), throwsArgumentError);
    expect(player.sources, isEmpty);
    expect(player.stopCalls, 0);
  });

  test('stop during preparation cannot restart an old Surah', () async {
    final checking = Completer<void>();
    final online = Completer<bool>();
    cache.checkConnection = () {
      checking.complete();
      return online.future;
    };
    final attempt = service.playSurah(reciter: 'ar.alafasy', surah: 2);
    await checking.future;
    expect(player.stopCalls, 1);
    await service.stop();
    online.complete(true);
    await attempt;
    expect(player.sources, isEmpty);
    expect(player.playCalls, 0);
  });

  test('expired Surah preparation cannot stop a newer word', () async {
    final oldLoad = Completer<Duration?>();
    player.onLoad = () => oldLoad.future;
    final attempt = service.playSurah(reciter: 'ar.alafasy', surah: 2);
    await player.loadStarted.future;
    player.onLoad = null;
    await service.playWord(surah: 1, ayah: 1, word: 1);
    final stopCalls = player.stopCalls;
    await attempt;
    oldLoad.complete();
    await Future<void>.delayed(Duration.zero);
    expect(player.stopCalls, stopCalls);
    expect(player.playCalls, 1);
    expect(
      (player.sources.last as UriAudioSource).uri.path,
      '/wbw/001_001_001.mp3',
    );
  });

  test('timeout invalidates a late native source load', () async {
    final pending = Completer<Duration?>();
    player.onLoad = () => pending.future;
    await expectLater(
      service.playSurah(reciter: 'ar.alafasy', surah: 2),
      throwsA(isA<TimeoutException>()),
    );
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(player.playCalls, 0);
    expect(player.stopCalls, 2);
  });

  test(
    'offline replacement stops the previous source and reports failure',
    () async {
      cache.checkConnection = () async => false;
      await expectLater(
        service.playSurah(reciter: 'ar.alafasy', surah: 2),
        throwsA(isA<QuranAudioOfflineException>()),
      );
      expect(player.playCalls, 0);
      expect(player.sources, isEmpty);
      expect(player.stopCalls, 2);
    },
  );
}
