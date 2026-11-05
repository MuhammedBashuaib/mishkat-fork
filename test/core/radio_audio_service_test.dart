import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';
import 'package:mishkat_app/core/services/radio_stream_url_resolver.dart';

class _Player implements AudioPlayer {
  final sources = <AudioSource>[];
  final loadStarted = Completer<void>();
  Future<Duration?> Function()? onLoad;
  int playCalls = 0;
  int stopCalls = 0;
  final playback = Completer<void>();

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
    return playback.future;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {
    if (!playback.isCompleted) playback.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements QuranAudioCacheService {
  Future<bool> Function() checkConnection = () async => true;
  File? cachedFile;

  @override
  Future<File?> getCachedFile({
    required String reciter,
    required int globalAyah,
    bool updateAccessTime = true,
  }) async => cachedFile;

  @override
  Future<bool> isNetworkAvailable() => checkConnection();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingFile implements File {
  final checked = Completer<void>();
  final result = Completer<bool>();

  @override
  Future<bool> exists() {
    checked.complete();
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver implements RadioStreamUrlResolver {
  Future<Uri> Function(Uri) onResolve = (uri) async => uri;

  @override
  Future<Uri> resolve(Uri url) => onResolve(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  const stationUrl = 'https://radio.example/live';
  late _Player player;
  late _Cache cache;
  late _Resolver resolver;
  late QuranAudioService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sessionChannel, (_) async => null);
    player = _Player();
    cache = _Cache();
    resolver = _Resolver();
    service = QuranAudioService(
      player: player,
      cacheService: cache,
      streamUrlResolver: resolver,
      streamLoadTimeout: const Duration(milliseconds: 100),
    );
  });

  tearDown(() async {
    await service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sessionChannel, null);
  });

  test(
    'starts indefinite audio using the resolved URI and stable metadata',
    () async {
      final resolved = Uri.parse('https://node.example/live?temporary=token');
      resolver.onResolve = (_) async => resolved;

      await service.playStreamUrl(
        stationUrl,
        title: 'إذاعة القرآن',
        sourceLabel: 'مصدر البث',
      );

      final source = player.sources.single as UriAudioSource;
      final metadata = source.tag as MediaItem;
      expect(source.uri, resolved);
      expect(metadata.id, 'radio:$stationUrl');
      expect(metadata.title, 'إذاعة القرآن');
      expect(metadata.artist, 'مصدر البث');
      expect(metadata.isLive, isTrue);
      expect(player.playCalls, 1);
      expect(player.playback.isCompleted, isFalse);
      expect(player.stopCalls, 1);
    },
  );

  test(
    'times out and cancels a native load that never becomes ready',
    () async {
      final pendingLoad = Completer<Duration?>();
      player.onLoad = () => pendingLoad.future;

      await expectLater(
        service.playStreamUrl(stationUrl),
        throwsA(isA<TimeoutException>()),
      );

      expect(player.stopCalls, 2);
      expect(player.playCalls, 0);
      pendingLoad.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.playCalls, 0);

      player.onLoad = null;
      await service.playStreamUrl(stationUrl);
      expect(player.playCalls, 1);
    },
  );

  test('the preparation deadline also covers connectivity checks', () async {
    final connection = Completer<bool>();
    cache.checkConnection = () => connection.future;

    await expectLater(
      service.playStreamUrl(stationUrl),
      throwsA(isA<TimeoutException>()),
    );
    connection.complete(true);
    await Future<void>.delayed(Duration.zero);

    expect(player.sources, isEmpty);
    expect(player.playCalls, 0);
  });

  test(
    'stop during URL resolution prevents a late source from starting',
    () async {
      final resolving = Completer<void>();
      final resolvedUri = Completer<Uri>();
      resolver.onResolve = (_) {
        resolving.complete();
        return resolvedUri.future;
      };

      final attempt = service.playStreamUrl(stationUrl);
      await resolving.future;
      await service.stop();
      resolvedUri.complete(Uri.parse(stationUrl));
      await attempt;

      expect(player.sources, isEmpty);
      expect(player.playCalls, 0);
    },
  );

  test('an expired old request cannot stop a newer playing station', () async {
    final oldLoad = Completer<Duration?>();
    player.onLoad = () => oldLoad.future;
    final firstAttempt = service.playStreamUrl(stationUrl);
    await player.loadStarted.future;

    player.onLoad = null;
    await service.playStreamUrl('https://radio.example/second');
    final stopCalls = player.stopCalls;
    await firstAttempt;

    expect(player.stopCalls, stopCalls);
    expect(player.playCalls, 1);
    oldLoad.complete();
    await Future<void>.delayed(Duration.zero);
    expect(player.playCalls, 1);
  });

  test(
    'a source failure is propagated and the failed source is stopped',
    () async {
      final error = PlayerException(1, 'Source unavailable', 0);
      player.onLoad = () => Future<Duration?>.error(error);

      await expectLater(
        service.playStreamUrl(stationUrl),
        throwsA(same(error)),
      );
      expect(player.stopCalls, 2);
      expect(player.playCalls, 0);
    },
  );

  test('offline failure does not leave previous audio playing', () async {
    cache.checkConnection = () async => false;

    await expectLater(
      service.playStreamUrl(stationUrl),
      throwsA(isA<QuranAudioOfflineException>()),
    );
    expect(player.stopCalls, greaterThanOrEqualTo(1));
    expect(player.sources, isEmpty);
    expect(player.playCalls, 0);
  });

  test(
    'a late cached ayah cannot replace a newly playing radio station',
    () async {
      final file = _PendingFile();
      cache.cachedFile = file;
      final ayah = service.playAyah(reciter: 'ar.alafasy', globalAyah: 1);
      await file.checked.future;

      await service.playStreamUrl(stationUrl);
      file.result.complete(true);
      await ayah;

      expect(player.sources, hasLength(1));
      expect(
        (player.sources.single as UriAudioSource).uri,
        Uri.parse(stationUrl),
      );
      expect(player.playCalls, 1);
    },
  );
}
