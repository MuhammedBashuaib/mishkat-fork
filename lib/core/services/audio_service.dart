import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../constants/app_constants.dart';
import 'quran_audio_cache_service.dart';
import 'quran_listening_sources.dart';
import 'radio_stream_url_resolver.dart';

export 'quran_listening_sources.dart';

/// Exception thrown when audio playback is requested offline but the file is not cached.
class QuranAudioOfflineException implements Exception {
  const QuranAudioOfflineException([
    this.message = 'التلاوة غير متوفرة دون اتصال بالإنترنت.',
  ]);
  final String message;

  @override
  String toString() => message;
}

class QuranAudioUrlBuilder {
  const QuranAudioUrlBuilder._();

  static const String defaultCdnHost = 'https://cdn.islamic.network';
  static const String everyAyahHost = 'https://everyayah.com/data';
  static const String quranicAudioHost =
      'https://download.quranicaudio.com/quran';

  static String buildUrl({
    required String reciter,
    required int globalAyah,
    String cdnHost = defaultCdnHost,
  }) {
    final safeAyah = globalAyah.clamp(1, AppConstants.totalAyahs);
    final reciterInfo = AppConstants.findReciter(reciter);
    final address = QuranAyahIndex.fromGlobal(safeAyah);

    return switch (reciterInfo.source) {
      ReciterAudioSource.alQuranCloud =>
        '$cdnHost/quran/audio/${reciterInfo.bitrate}/${reciterInfo.id}/$safeAyah.mp3',
      ReciterAudioSource.everyAyah =>
        '$everyAyahHost/${reciterInfo.audioPath}/${address.surah.toString().padLeft(3, '0')}${address.ayah.toString().padLeft(3, '0')}.mp3',
      ReciterAudioSource.segmentedSurah =>
        '$quranicAudioHost/${reciterInfo.audioPath}/${address.surah.toString().padLeft(3, '0')}.mp3',
    };
  }
}

class QuranAudioSegment {
  const QuranAudioSegment({
    required this.audioUrl,
    required this.start,
    required this.end,
  });

  final String audioUrl;
  final Duration start;
  final Duration end;
}

/// Resolves timestamped Ayahs inside a continuous Surah recording.
///
/// QUL publishes the audio URL and verified Ayah boundaries. A full Surah is
/// fetched only by the player; this resolver caches its small metadata response.
class QuranAudioSegmentResolver {
  QuranAudioSegmentResolver({HttpClient? httpClient})
    : _client = httpClient ?? HttpClient();

  static const _apiHost = 'https://qul.tarteel.ai';

  final HttpClient _client;
  final Map<String, Map<int, QuranAudioSegment>> _chapterCache = {};

  Future<QuranAudioSegment> resolve({
    required ReciterInfo reciter,
    required QuranAyahAddress address,
  }) async {
    final recitationId = reciter.segmentRecitationId;
    if (recitationId == null) {
      throw StateError('Missing segment recitation ID for ${reciter.id}.');
    }

    final cacheKey = '$recitationId:${address.surah}';
    var chapter = _chapterCache[cacheKey];
    if (chapter == null) {
      chapter = await _loadChapter(
        recitationId: recitationId,
        surah: address.surah,
      );
      _chapterCache[cacheKey] = chapter;
    }

    final segment = chapter[address.ayah];
    if (segment == null) {
      throw StateError('Missing segment for ${address.surah}:${address.ayah}.');
    }
    return segment;
  }

  Future<Map<int, QuranAudioSegment>> _loadChapter({
    required int recitationId,
    required int surah,
  }) async {
    final ayahCount = QuranAyahIndex.ayahsPerSurah[surah - 1];
    final uri = Uri.parse(
      '$_apiHost/api/v1/audio/surah_segments/$recitationId'
      '?surah=$surah&per_page=$ayahCount',
    );
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('Segment server returned ${response.statusCode}.');
    }

    final body = await utf8.decoder.bind(response).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final audio = Map<String, dynamic>.from(json['audio'] as Map);
    final audioUrl = audio['url'] as String;
    final rawSegments = Map<String, dynamic>.from(json['segments'] as Map);
    final result = <int, QuranAudioSegment>{};

    for (final entry in rawSegments.entries) {
      final verseKey = entry.key.split(':');
      if (verseKey.length != 2) continue;
      final ayah = int.tryParse(verseKey[1]);
      if (ayah == null) continue;
      final value = Map<String, dynamic>.from(entry.value as Map);
      final fromMs = (value['time_from'] as num).toInt();
      final toMs = (value['time_to'] as num).toInt();
      if (toMs <= fromMs) continue;
      result[ayah] = QuranAudioSegment(
        audioUrl: audioUrl,
        start: Duration(milliseconds: fromMs),
        end: Duration(milliseconds: toMs),
      );
    }

    if (result.isEmpty) {
      throw const FormatException('Segment response contains no Ayahs.');
    }
    return result;
  }

  void dispose() => _client.close(force: true);
}

class QuranAudioService {
  QuranAudioService({
    AudioPlayer? player,
    QuranAudioCacheService? cacheService,
    QuranAudioSegmentResolver? segmentResolver,
    RadioStreamUrlResolver? streamUrlResolver,
    Duration? streamLoadTimeout,
  }) : _player = player ?? AudioPlayer(),
       _cache = cacheService ?? QuranAudioCacheService(),
       _segmentResolver = segmentResolver ?? QuranAudioSegmentResolver(),
       _streamUrlResolver = streamUrlResolver ?? RadioStreamUrlResolver(),
       _streamLoadTimeout = streamLoadTimeout ?? const Duration(seconds: 25);

  final AudioPlayer _player;
  final QuranAudioCacheService _cache;
  final QuranAudioSegmentResolver _segmentResolver;
  final RadioStreamUrlResolver _streamUrlResolver;
  final Duration _streamLoadTimeout;
  int _activeRequestId = 0;
  final _playbackErrors =
      StreamController<({int requestId, Object error})>.broadcast();
  StreamSubscription<PlayerException>? _nativeErrorSubscription;
  int? _listeningForRequestId;
  int? _failedRequestId;
  bool _disposed = false;

  Stream<PlayerState> get playerState => _player.playerStateStream;
  Stream<Duration> get position => _player.positionStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  bool get isPlaying => _player.playing;
  Duration? get duration => _player.duration;
  Duration get currentPosition => _player.position;

  void _reportPlaybackError(int requestId, Object error) {
    if (_disposed ||
        requestId != _activeRequestId ||
        requestId == _failedRequestId) {
      return;
    }
    // A native failure may appear both on errorStream and the play Future.
    // Report only once for this source and ignore canceled source failures.
    _failedRequestId = requestId;
    _playbackErrors.add((requestId: requestId, error: error));
  }

  void _launchPlayback(int requestId) {
    if (_disposed || requestId != _activeRequestId) return;
    if (_listeningForRequestId != requestId) {
      unawaited(_nativeErrorSubscription?.cancel());
      _nativeErrorSubscription = null;
      _listeningForRequestId = requestId;
      try {
        _nativeErrorSubscription = _player.errorStream.listen(
          (error) => _reportPlaybackError(requestId, error),
          onError: (Object error) => _reportPlaybackError(requestId, error),
        );
      } on NoSuchMethodError {
        // Reader-only AudioPlayer test doubles predate the native error stream.
      }
    }
    try {
      unawaited(
        _player.play().catchError((Object error) {
          _reportPlaybackError(requestId, error);
        }),
      );
    } on Object catch (error) {
      _reportPlaybackError(requestId, error);
    }
  }

  Future<void> _configurePlaybackSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  MediaItem _ayahMediaItem({
    required ReciterInfo reciter,
    required QuranAyahAddress address,
  }) {
    return MediaItem(
      id: 'quran:${reciter.id}:${address.global}',
      album: 'القرآن الكريم · مشكاة',
      title: 'السورة ${address.surah} · الآية ${address.ayah}',
      artist: reciter.name,
      extras: <String, dynamic>{
        'kind': 'ayah',
        'surah': address.surah,
        'ayah': address.ayah,
        'globalAyah': address.global,
      },
    );
  }

  MediaItem _stationMediaItem({
    required String url,
    String? title,
    String? sourceLabel,
  }) {
    return MediaItem(
      id: 'radio:$url',
      album: 'إذاعات القرآن · مشكاة',
      title: title ?? 'إذاعة القرآن الكريم',
      artist: sourceLabel ?? 'مشكاة',
      isLive: true,
      extras: const <String, dynamic>{'kind': 'radio'},
    );
  }

  /// Plays the audio for [globalAyah] using an offline-first strategy.
  ///
  /// 1. Checks local cache for a valid file.
  /// 2. If present, plays from disk immediately.
  /// 3. If absent and network is online, streams from CDN and caches in the background.
  /// 4. If absent and network is offline, throws [QuranAudioOfflineException] gracefully.
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {
    final requestId = ++_activeRequestId;
    final safeAyah = globalAyah.clamp(1, AppConstants.totalAyahs);
    final reciterInfo = AppConstants.findReciter(reciter);
    final address = QuranAyahIndex.fromGlobal(safeAyah);
    final mediaItem = _ayahMediaItem(reciter: reciterInfo, address: address);

    await _player.stop();
    if (requestId != _activeRequestId) return;
    await _player.setSpeed(1);
    if (requestId != _activeRequestId) return;
    await _configurePlaybackSession();
    if (requestId != _activeRequestId) return;

    if (reciterInfo.source == ReciterAudioSource.segmentedSurah) {
      final isOnline = await _cache.isNetworkAvailable();
      if (requestId != _activeRequestId) return;
      if (!isOnline) {
        throw const QuranAudioOfflineException(
          'هذه التلاوة المتصلة تحتاج إلى اتصال بالإنترنت.',
        );
      }
      final segment = await _segmentResolver.resolve(
        reciter: reciterInfo,
        address: address,
      );
      if (requestId != _activeRequestId) return;
      await _player.setAudioSource(
        ClippingAudioSource(
          child: AudioSource.uri(Uri.parse(segment.audioUrl), tag: mediaItem),
          start: segment.start,
          end: segment.end,
          tag: mediaItem,
        ),
      );
      if (requestId != _activeRequestId) return;
      _launchPlayback(requestId);
      return;
    }

    // 1. Try local cache
    File? localFile;
    try {
      localFile = await _cache.getCachedFile(
        reciter: reciter,
        globalAyah: safeAyah,
      );
    } on FileSystemException {
      // Optional caching may be unavailable on a full/unwritable device.
      // Online playback can still use the original source.
    }

    if (requestId != _activeRequestId) return;

    if (localFile != null && await localFile.exists()) {
      if (requestId != _activeRequestId) return;
      try {
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(localFile.path), tag: mediaItem),
        );
        if (requestId != _activeRequestId) return;
        // Playback completion is reported by playerStateStream. Do not keep
        // this command pending for the full Ayah duration; the QuranCubit
        // needs to be free to prepare and start the following Ayah.
        _launchPlayback(requestId);
        return;
      } catch (_) {
        if (requestId != _activeRequestId) return;
        // If local playback failed due to unexpected corruption, fall through to stream
        try {
          await localFile.delete();
        } catch (_) {}
      }
    }

    // 2. Check network connectivity
    final isOnline = await _cache.isNetworkAvailable();
    if (requestId != _activeRequestId) return;
    if (!isOnline) {
      throw const QuranAudioOfflineException(
        'التلاوة غير متوفرة دون اتصال بالإنترنت. يرجى الاتصال بالشبكة لتحميلها.',
      );
    }

    // 3. Stream from CDN
    final url = QuranAudioUrlBuilder.buildUrl(
      reciter: reciter,
      globalAyah: safeAyah,
    );

    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url), tag: mediaItem),
    );
    if (requestId != _activeRequestId) return;
    _launchPlayback(requestId);

    // 4. Trigger background cache download
    unawaited(
      _cache
          .cacheAyah(
            reciter: reciter,
            globalAyah: safeAyah,
            pinnedAyahs: {safeAyah},
          )
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _prepareStream(
    int requestId,
    String url, {
    String? title,
    String? sourceLabel,
  }) async {
    // Cancel the previous source even if the new station is unreachable.
    await _player.stop();
    if (requestId != _activeRequestId) return;
    await _player.setSpeed(1);
    if (requestId != _activeRequestId) return;
    await _configurePlaybackSession();
    if (requestId != _activeRequestId) return;
    final isOnline = await _cache.isNetworkAvailable();
    if (requestId != _activeRequestId) return;
    if (!isOnline) {
      throw const QuranAudioOfflineException(
        'البث غير متوفر دون اتصال بالإنترنت. يرجى الاتصال بالشبكة للاستماع.',
      );
    }
    final streamUri = await _streamUrlResolver.resolve(Uri.parse(url));
    if (requestId != _activeRequestId) return;
    await _player.setAudioSource(
      AudioSource.uri(
        streamUri,
        tag: _stationMediaItem(
          url: url,
          title: title,
          sourceLabel: sourceLabel,
        ),
      ),
    );
  }

  Future<void> _playRecording({
    required int requestId,
    required String url,
    required MediaItem mediaItem,
  }) async {
    Future<void> prepare() async {
      await _player.stop();
      if (requestId != _activeRequestId) return;
      if (mediaItem.extras?['kind'] == 'word') {
        await _player.setSpeed(1);
        if (requestId != _activeRequestId) return;
      }
      await _configurePlaybackSession();
      if (requestId != _activeRequestId) return;
      final online = await _cache.isNetworkAvailable();
      if (requestId != _activeRequestId) return;
      if (!online) {
        throw const QuranAudioOfflineException(
          'هذا التسجيل يحتاج إلى اتصال بالإنترنت.',
        );
      }
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(url), tag: mediaItem),
      );
    }

    try {
      await prepare().timeout(_streamLoadTimeout);
      if (requestId != _activeRequestId) return;
      // The source is one recording, not a list of ayahs or clipped segments.
      _launchPlayback(requestId);
    } on Object catch (error, stackTrace) {
      if (requestId != _activeRequestId) return;
      _activeRequestId++;
      try {
        await _player.stop();
      } catch (_) {
        // Keep the preparation error if native cleanup fails as well.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() async => _launchPlayback(_activeRequestId);
  Future<void> stop() async {
    _activeRequestId++;
    await _player.stop();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> dispose() async {
    _disposed = true;
    _activeRequestId++;
    await _nativeErrorSubscription?.cancel();
    _segmentResolver.dispose();
    await _player.dispose();
    await _playbackErrors.close();
  }
}

/// Full-Surah and educational word playback share the one background player.
/// Extensions preserve compatibility with existing reader-only service fakes.
extension QuranListeningExtension on QuranAudioService {
  Stream<Object> get playbackErrors {
    try {
      return _playbackErrors.stream
          // Recheck at delivery as a listener may select a new source while
          // a previous source's error is waiting in the asynchronous queue.
          .where((event) => !_disposed && event.requestId == _activeRequestId)
          .map((event) => event.error);
    } on NoSuchMethodError {
      // Existing QuranAudioService fakes do not have implementation fields.
      try {
        return (this as dynamic).playbackErrors as Stream<Object>;
      } on NoSuchMethodError {
        return const Stream<Object>.empty();
      }
    }
  }

  Future<void> playSurah({
    required String reciter,
    required int surah,
    String? title,
  }) async {
    final url = QuranSurahAudioUrlBuilder.buildUrl(
      reciter: reciter,
      surah: surah,
    );
    final int requestId;
    try {
      requestId = ++_activeRequestId;
    } on NoSuchMethodError {
      await (this as dynamic).playSurah(
        reciter: reciter,
        surah: surah,
        title: title,
      );
      return;
    }
    final reciterInfo = AppConstants.findReciter(reciter);
    await _playRecording(
      requestId: requestId,
      url: url,
      mediaItem: MediaItem(
        id: 'surah:${reciterInfo.id}:$surah',
        album: 'القرآن الكريم · مشكاة',
        title: title ?? 'السورة $surah',
        artist: reciterInfo.name,
        isLive: false,
        extras: <String, dynamic>{'kind': 'surah', 'surah': surah},
      ),
    );
  }

  Future<void> playWord({
    required int surah,
    required int ayah,
    required int word,
  }) async {
    final url = QuranWordAudioUrlBuilder.buildUrl(
      surah: surah,
      ayah: ayah,
      word: word,
    );
    final int requestId;
    try {
      requestId = ++_activeRequestId;
    } on NoSuchMethodError {
      await (this as dynamic).playWord(surah: surah, ayah: ayah, word: word);
      return;
    }
    await _playRecording(
      requestId: requestId,
      url: url,
      mediaItem: MediaItem(
        id: 'word:$surah:$ayah:$word',
        album: 'نطق الكلمات التعليمي · مشكاة',
        title: 'السورة $surah · الآية $ayah · الكلمة $word',
        artist: 'Quran.com · نطق الكلمات',
        isLive: false,
        extras: <String, dynamic>{
          'kind': 'word',
          'surah': surah,
          'ayah': ayah,
          'word': word,
        },
      ),
    );
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!speed.isFinite || speed < 0.5 || speed > 2) {
      throw ArgumentError.value(speed, 'speed', 'Must be between 0.5 and 2.');
    }
    final AudioPlayer player;
    try {
      player = _player;
    } on NoSuchMethodError {
      await (this as dynamic).setPlaybackSpeed(speed);
      return;
    }
    await player.setSpeed(speed);
  }
}

/// Stream playback capabilities on [QuranAudioService].
///
/// Implemented as an extension so that existing mocks and fakes of [QuranAudioService]
/// across the test suite remain completely unbroken.
extension QuranAudioStreamExtension on QuranAudioService {
  /// Plays an audio live stream or radio station directly via [url].
  ///
  /// Guarantees that any ongoing Ayah playback or previous stream is cleanly stopped.
  Future<void> playStreamUrl(
    String url, {
    String? title,
    String? sourceLabel,
  }) async {
    final int requestId;
    try {
      requestId = ++_activeRequestId;
    } on NoSuchMethodError {
      // Existing fakes implement the public service without its private fields.
      // Only this access uses the compatibility path; playback errors propagate.
      await (this as dynamic).playStreamUrl(url);
      return;
    }
    try {
      await _prepareStream(
        requestId,
        url,
        title: title,
        sourceLabel: sourceLabel,
      ).timeout(_streamLoadTimeout);
      if (requestId != _activeRequestId) return;
      // A live stream never completes. Only source preparation is awaited.
      _launchPlayback(requestId);
    } on Object catch (error, stackTrace) {
      if (requestId != _activeRequestId) return;
      // Future.timeout does not cancel native loading. Invalidate the request
      // and release it so a late result cannot start audio after an error/retry.
      _activeRequestId++;
      try {
        await _player.stop();
      } catch (_) {
        // Preserve the original connection/timeout error if cleanup also fails.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
