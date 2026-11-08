import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/constants/app_constants.dart';
import 'package:mishkat_app/core/services/offline_audio_download_controller.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'mishkat_cache_integrity_',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'rejects HTML, JSON and zero-filled responses larger than 1 KB',
    () async {
      final cache = QuranAudioCacheService(baseDirectory: directory);
      final payloads = [
        utf8.encode('<html>${'Server unavailable ' * 100}</html>'),
        utf8.encode(jsonEncode({'error': 'unavailable ' * 200})),
        List<int>.filled(2048, 0),
      ];
      for (var i = 0; i < payloads.length; i++) {
        expect(
          await cache.saveFile(
            reciter: 'ar.alafasy',
            globalAyah: i + 1,
            bytes: payloads[i],
            pinnedAyahs: {i + 1},
          ),
          isNull,
        );
      }
      expect(cache.entries, isEmpty);
    },
  );

  test('retains supported audio container signatures', () async {
    final headers = [
      [0x49, 0x44, 0x33, 3], // ID3 MP3
      [0xff, 0xfb, 0x90, 0], // MPEG audio frame
      ascii.encode('OggS'),
      ascii.encode('fLaC'),
      [...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WAVE')],
      [0, 0, 0, 24, ...ascii.encode('ftypM4A ')],
    ];
    for (var i = 0; i < headers.length; i++) {
      final file = File('${directory.path}/supported-$i');
      await file.writeAsBytes(_audioBytes(headers[i]));
      expect(await QuranAudioCacheService.isValidAudioFile(file), isTrue);
    }
  });

  test('HTTP 200 HTML is never counted as a durable download', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalClient(server.port);
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    server.listen((request) async {
      request.response.write('<html>${'Service error ' * 200}</html>');
      await request.response.close();
    });
    final cache = QuranAudioCacheService(
      baseDirectory: directory,
      httpClient: client,
    );
    expect(
      await cache.downloadAyah(reciter: 'ar.alafasy', globalAyah: 1),
      isNull,
    );
    expect(cache.entries, isEmpty);
    expect(
      await cache.cachedCount(
        reciter: 'ar.alafasy',
        startGlobalAyah: 1,
        endGlobalAyah: 1,
      ),
      0,
    );
  });

  test('explicit download upgrades an in-flight playback prefetch', () async {
    final requested = Completer<HttpRequest>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalClient(server.port);
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    var requestCount = 0;
    server.listen((request) {
      requestCount++;
      requested.complete(request);
    });
    final cache = _ObservedCache(directory: directory, client: client);
    final prefetch = cache.cacheAyah(reciter: 'ar.alafasy', globalAyah: 1);
    final request = await requested.future;
    cache.nextLookup = Completer<void>();
    final explicit = cache.downloadAyah(reciter: 'ar.alafasy', globalAyah: 1);
    await cache.nextLookup!.future;
    // Let the completed lookup's continuation join the existing operation.
    await Future<void>.delayed(Duration.zero);
    request.response.add(_audioBytes());
    await request.response.close();
    expect(await prefetch, isNotNull);
    expect(await explicit, isNotNull);
    expect(requestCount, 1);
    expect(cache.entries.single.pinned, isTrue);
    final restarted = QuranAudioCacheService(baseDirectory: directory);
    await restarted.init();
    expect(restarted.entries.single.pinned, isTrue);
  });

  test('erase cancels a stalled transfer and its remaining queue', () async {
    final started = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalClient(server.port);
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      client.close(force: true);
      await server.close(force: true);
    });
    var requestCount = 0;
    server.listen((request) async {
      requestCount++;
      try {
        if (requestCount == 1) {
          request.response.add(_audioBytes().sublist(0, 1024));
          await request.response.flush();
          started.complete();
          await releaseResponse.future;
        }
        request.response.add(_audioBytes());
        await request.response.close();
      } on Object {
        // The transfer is expected to be disconnected by clearAllDownloads.
      }
    });
    final cache = _ObservedCache(directory: directory, client: client);
    final controller = OfflineAudioDownloadController(cache);
    final download = controller.downloadRange(
      reciter: AppConstants.findReciter('ar.alafasy'),
      startAyah: 1,
      endAyah: 3,
      label: 'test',
    );
    await started.future;
    await _waitFor(
      () async =>
          await Directory('${directory.path}/audio_cache/tmp').list().isEmpty ==
          false,
    );
    await controller.clearAllDownloads().timeout(const Duration(seconds: 3));
    releaseResponse.complete();
    await download;
    expect(controller.state.status, OfflineDownloadStatus.idle);
    expect(requestCount, 1);
    expect(cache.entries, isEmpty);
    expect(
      await Directory('${directory.path}/audio_cache')
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.mp3'))
          .isEmpty,
      isTrue,
    );
    // A clear is not a permanent shutdown of downloads.
    await controller.downloadRange(
      reciter: AppConstants.findReciter('ar.alafasy'),
      startAyah: 4,
      endAyah: 4,
      label: 'new',
    );
    expect(controller.state.status, OfflineDownloadStatus.completed);
    expect(cache.entries.single.globalAyah, 4);
    controller.dispose();
  });

  test('erase drains an already-started local file write', () async {
    final cache = QuranAudioCacheService(baseDirectory: directory);
    await cache.init();
    final saving = cache.saveFile(
      reciter: 'ar.alafasy',
      globalAyah: 1,
      bytes: _audioBytes(),
    );
    await cache.clearCache();
    await saving;
    expect(cache.entries, isEmpty);
    final restarted = QuranAudioCacheService(baseDirectory: directory);
    await restarted.init();
    expect(restarted.entries, isEmpty);
    expect(
      await restarted.getCachedFile(reciter: 'ar.alafasy', globalAyah: 1),
      isNull,
    );
  });
}

List<int> _audioBytes([List<int> header = const [0xff, 0xfb, 0x90, 0]]) =>
    List<int>.filled(2048, 0)..setRange(0, header.length, header);

Future<void> _waitFor(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _LocalClient implements HttpClient {
  _LocalClient(this.port)
    : _client = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttpOverrides(),
      );
  final int port;
  final HttpClient _client;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _client.getUrl(
    Uri(scheme: 'http', host: '127.0.0.1', port: port, path: url.path),
  );
  @override
  void close({bool force = false}) => _client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedCache extends QuranAudioCacheService {
  _ObservedCache({required Directory directory, required HttpClient client})
    : super(baseDirectory: directory, httpClient: client);
  Completer<void>? nextLookup;
  @override
  Future<bool> isNetworkAvailable() async => true;
  @override
  Future<File?> getCachedFile({
    required String reciter,
    required int globalAyah,
    bool updateAccessTime = true,
  }) async {
    final result = await super.getCachedFile(
      reciter: reciter,
      globalAyah: globalAyah,
      updateAccessTime: updateAccessTime,
    );
    final pending = nextLookup;
    if (pending != null && !pending.isCompleted) pending.complete();
    return result;
  }
}

class _RealHttpOverrides extends HttpOverrides {}
