import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_service.dart';

/// Metadata entry for a single cached Quran recitation file.
class QuranAudioCacheEntry extends Equatable {
  const QuranAudioCacheEntry({
    required this.reciterId,
    required this.globalAyah,
    required this.fileSizeBytes,
    required this.cachedAt,
    required this.lastAccessedAt,
    this.pinned = false,
  });

  final String reciterId;
  final int globalAyah;
  final int fileSizeBytes;
  final DateTime cachedAt;
  final DateTime lastAccessedAt;

  /// User downloads are pinned so normal playback caching never evicts them.
  final bool pinned;

  String get key => '${reciterId}_$globalAyah';

  QuranAudioCacheEntry copyWith({
    int? fileSizeBytes,
    DateTime? lastAccessedAt,
    bool? pinned,
  }) {
    return QuranAudioCacheEntry(
      reciterId: reciterId,
      globalAyah: globalAyah,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      cachedAt: cachedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'reciterId': reciterId,
    'globalAyah': globalAyah,
    'fileSizeBytes': fileSizeBytes,
    'cachedAt': cachedAt.toIso8601String(),
    'lastAccessedAt': lastAccessedAt.toIso8601String(),
    'pinned': pinned,
  };

  factory QuranAudioCacheEntry.fromJson(Map<String, dynamic> json) {
    return QuranAudioCacheEntry(
      reciterId: json['reciterId'] as String,
      globalAyah: (json['globalAyah'] as num).toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    reciterId,
    globalAyah,
    fileSizeBytes,
    cachedAt,
    lastAccessedAt,
    pinned,
  ];
}

/// User configurable settings for offline Quran audio caching.
class AudioCacheSettings extends Equatable {
  const AudioCacheSettings({
    this.enabled = true,
    this.wifiOnly = true,
    this.maxSizeMb = 150,
  });

  final bool enabled;
  final bool wifiOnly;
  final int maxSizeMb;

  int get maxSizeBytes => maxSizeMb * 1024 * 1024;

  AudioCacheSettings copyWith({bool? enabled, bool? wifiOnly, int? maxSizeMb}) {
    return AudioCacheSettings(
      enabled: enabled ?? this.enabled,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      maxSizeMb: maxSizeMb ?? this.maxSizeMb,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'wifiOnly': wifiOnly,
    'maxSizeMb': maxSizeMb,
  };

  factory AudioCacheSettings.fromJson(Map<String, dynamic> json) {
    return AudioCacheSettings(
      enabled: json['enabled'] as bool? ?? true,
      wifiOnly: json['wifiOnly'] as bool? ?? true,
      maxSizeMb: (json['maxSizeMb'] as num?)?.toInt() ?? 150,
    );
  }

  @override
  List<Object?> get props => [enabled, wifiOnly, maxSizeMb];
}

/// Bounded offline-first audio caching engine with deterministic LRU eviction.
class QuranAudioCacheService {
  QuranAudioCacheService({
    Directory? baseDirectory,
    HttpClient? httpClient,
    Connectivity? connectivity,
    int? maxCacheSizeBytes,
  }) : _customBaseDir = baseDirectory,
       _client = httpClient ?? HttpClient(),
       _connectivity = connectivity ?? Connectivity(),
       maxCacheSizeBytes = maxCacheSizeBytes ?? defaultMaxCacheSizeBytes;

  /// Default high watermark: 150 MiB (157,286,400 bytes).
  static const int defaultMaxCacheSizeBytes = 150 * 1024 * 1024;

  /// Low watermark ratio: 85% of high watermark when eviction occurs.
  static const double lowWatermarkRatio = 0.85;

  final Directory? _customBaseDir;
  final HttpClient _client;
  final Connectivity _connectivity;
  final int maxCacheSizeBytes;

  Directory? _cacheDir;
  Directory? _tmpDir;
  File? _metadataFile;

  final Map<String, QuranAudioCacheEntry> _entries = {};
  final Map<String, _CacheDownload> _activeDownloads = {};
  final Set<Future<Object?>> _operations = {};
  Future<void>? _initializing;
  Future<void>? _clearing;
  Future<void> _metadataWrites = Future.value();

  Future<T> _track<T>(Future<T> Function() action) {
    late final Future<T> operation;
    operation = Future<T>.sync(action).whenComplete(() {
      _operations.remove(operation);
    });
    _operations.add(operation);
    return operation;
  }

  final StreamController<int> _changes = StreamController<int>.broadcast();
  int _revision = 0;
  bool _isInitialized = false;

  /// Total size of all cached audio files in bytes.
  int get currentCacheSizeBytes =>
      _entries.values.fold(0, (sum, entry) => sum + entry.fileSizeBytes);

  /// Human-readable cache size formatted in megabytes.
  double get currentCacheSizeMb => currentCacheSizeBytes / (1024 * 1024);

  List<QuranAudioCacheEntry> get entries =>
      List<QuranAudioCacheEntry>.unmodifiable(_entries.values);

  Stream<int> get changes => _changes.stream;

  void _notifyChanged() {
    _revision++;
    if (!_changes.isClosed) _changes.add(_revision);
  }

  /// Initializes directories and loads existing metadata.
  Future<void> init() {
    if (_isInitialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    if (_customBaseDir != null) {
      _cacheDir = Directory('${_customBaseDir.path}/audio_cache');
    } else {
      final appSupport = await getApplicationSupportDirectory();
      _cacheDir = Directory('${appSupport.path}/audio_cache');
    }

    _tmpDir = Directory('${_cacheDir!.path}/tmp');
    _metadataFile = File('${_cacheDir!.path}/metadata.json');

    await _cacheDir!.create(recursive: true);
    await _tmpDir!.create(recursive: true);
    if (!await _metadataFile!.exists()) {
      await _metadataFile!.writeAsString(jsonEncode([]));
    }

    await _cleanInterruptedDownloads();
    await _loadMetadata();
    _isInitialized = true;
  }

  /// Checks whether a valid local audio file exists for [reciter] and [globalAyah].
  ///
  /// Returns the validated [File] on cache hit, or null on cache miss.
  Future<File?> getCachedFile({
    required String reciter,
    required int globalAyah,
    bool updateAccessTime = true,
  }) {
    if (_clearing != null) return Future.value();
    return _track(
      () => _getCachedFile(
        reciter: reciter,
        globalAyah: globalAyah,
        updateAccessTime: updateAccessTime,
      ),
    );
  }

  Future<File?> _getCachedFile({
    required String reciter,
    required int globalAyah,
    required bool updateAccessTime,
  }) async {
    await init();
    final file = _getFinalFile(reciter, globalAyah);
    if (!await file.exists()) {
      _removeEntry('${reciter}_$globalAyah');
      return null;
    }

    final isValid = await isValidAudioFile(file);
    if (!isValid) {
      // Corrupt or partial file found; purge it
      try {
        await file.delete();
      } catch (_) {}
      _removeEntry('${reciter}_$globalAyah');
      return null;
    }

    if (updateAccessTime) {
      final key = '${reciter}_$globalAyah';
      final existing = _entries[key];
      final size = await file.length();
      if (existing != null) {
        _entries[key] = existing.copyWith(
          lastAccessedAt: DateTime.now(),
          fileSizeBytes: size,
        );
      } else {
        _entries[key] = QuranAudioCacheEntry(
          reciterId: reciter,
          globalAyah: globalAyah,
          fileSizeBytes: size,
          cachedAt: DateTime.now(),
          lastAccessedAt: DateTime.now(),
        );
      }
      await _saveMetadata();
    }

    return file;
  }

  /// Downloads and caches the audio for [reciter] and [globalAyah] in the background.
  ///
  /// Uses deduplication to avoid redundant downloads if already in flight.
  /// Validates file size (>1024 bytes) and header before atomic rename.
  Future<File?> cacheAyah({
    required String reciter,
    required int globalAyah,
    Set<int> pinnedAyahs = const {},
    bool pin = false,
  }) {
    if (_clearing != null) return Future.value();
    return _track(
      () => _cacheAyah(
        reciter: reciter,
        globalAyah: globalAyah,
        pinnedAyahs: pinnedAyahs,
        pin: pin,
      ),
    );
  }

  Future<File?> _cacheAyah({
    required String reciter,
    required int globalAyah,
    required Set<int> pinnedAyahs,
    required bool pin,
  }) async {
    await init();
    final key = '${reciter}_$globalAyah';

    // 1. Check if already cached
    final existing = await getCachedFile(
      reciter: reciter,
      globalAyah: globalAyah,
    );
    if (_clearing != null) return null;
    if (existing != null) {
      final entry = _entries[key];
      if (pin && entry != null && !entry.pinned) {
        _entries[key] = entry.copyWith(pinned: true);
        await _saveMetadata();
        _notifyChanged();
      }
      return existing;
    }

    // An explicit download upgrades a playback prefetch already in flight.
    final active = _activeDownloads[key];
    if (active != null) {
      active.pin = active.pin || pin;
      active.pinnedAyahs.addAll(pinnedAyahs);
      return active.result;
    }

    final operation = _CacheDownload(pin: pin, pinnedAyahs: pinnedAyahs);
    _activeDownloads[key] = operation;
    operation.result = _executeDownload(
      reciter: reciter,
      globalAyah: globalAyah,
      operation: operation,
    );
    try {
      return await operation.result;
    } finally {
      _activeDownloads.remove(key);
    }
  }

  Future<File?> _executeDownload({
    required String reciter,
    required int globalAyah,
    required _CacheDownload operation,
  }) async {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tmpFile = File(
      '${_tmpDir!.path}/${reciter}_${globalAyah}_$timestamp.tmp',
    );
    final finalFile = _getFinalFile(reciter, globalAyah);
    RandomAccessFile? output;
    try {
      final urlString = QuranAudioUrlBuilder.buildUrl(
        reciter: reciter,
        globalAyah: globalAyah,
      );
      final request = await _client
          .getUrl(Uri.parse(urlString))
          .then((request) {
            operation.request = request;
            if (operation.cancelled) operation.abortRequest();
            return request;
          })
          .timeout(const Duration(seconds: 15));
      operation.request = request;
      if (operation.cancelled) return null;
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final chunks = StreamIterator(
        response.timeout(const Duration(seconds: 15)),
      );
      operation.chunks = chunks;
      if (operation.cancelled || response.statusCode != HttpStatus.ok) {
        return null;
      }

      output = await tmpFile.open(mode: FileMode.write);
      while (await chunks.moveNext()) {
        if (operation.cancelled) return null;
        await output.writeFrom(chunks.current);
      }
      await output.close();
      output = null;
      if (operation.cancelled || !await isValidAudioFile(tmpFile)) return null;

      await finalFile.parent.create(recursive: true);
      await tmpFile.rename(finalFile.path);
      final size = await finalFile.length();
      final now = DateTime.now();
      _entries['${reciter}_$globalAyah'] = QuranAudioCacheEntry(
        reciterId: reciter,
        globalAyah: globalAyah,
        fileSizeBytes: size,
        cachedAt: now,
        lastAccessedAt: now,
        pinned: operation.pin,
      );
      await _saveMetadata();
      _notifyChanged();
      if (currentCacheSizeBytes > maxCacheSizeBytes) {
        await evictLRU(pinnedAyahs: operation.pinnedAyahs);
      }
      return operation.cancelled ? null : finalFile;
    } catch (_) {
      return null;
    } finally {
      operation.cancelled = true;
      operation.abortRequest();
      await operation.chunks?.cancel();
      await output?.close();
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
    }
  }

  /// Atomically saves audio bytes directly to the cache, with full integrity validation and LRU enforcement.
  Future<File?> saveFile({
    required String reciter,
    required int globalAyah,
    required List<int> bytes,
    Set<int> pinnedAyahs = const {},
  }) {
    if (_clearing != null) return Future.value();
    return _track(
      () => _saveFile(
        reciter: reciter,
        globalAyah: globalAyah,
        bytes: bytes,
        pinnedAyahs: pinnedAyahs,
      ),
    );
  }

  Future<File?> _saveFile({
    required String reciter,
    required int globalAyah,
    required List<int> bytes,
    required Set<int> pinnedAyahs,
  }) async {
    await init();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tmpFile = File(
      '${_tmpDir!.path}/${reciter}_${globalAyah}_$timestamp.tmp',
    );
    final finalFile = _getFinalFile(reciter, globalAyah);

    try {
      await tmpFile.writeAsBytes(bytes);

      // Validate integrity
      final isValid = await isValidAudioFile(tmpFile);
      if (!isValid) {
        if (await tmpFile.exists()) await tmpFile.delete();
        return null;
      }

      await finalFile.parent.create(recursive: true);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tmpFile.rename(finalFile.path);

      final size = await finalFile.length();
      final now = DateTime.now();
      _entries['${reciter}_$globalAyah'] = QuranAudioCacheEntry(
        reciterId: reciter,
        globalAyah: globalAyah,
        fileSizeBytes: size,
        cachedAt: now,
        lastAccessedAt: now,
        pinned: pinnedAyahs.contains(globalAyah),
      );

      await _saveMetadata();
      _notifyChanged();

      if (currentCacheSizeBytes > maxCacheSizeBytes) {
        await evictLRU(pinnedAyahs: pinnedAyahs);
      }

      return finalFile;
    } catch (_) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      return null;
    }
  }

  /// Evicts least-recently-used audio files until cache is below 85% of max capacity.
  ///
  /// Protects any Ayahs provided in [pinnedAyahs] (currently playing or active session).
  Future<int> evictLRU({Set<int> pinnedAyahs = const {}}) {
    if (_clearing != null) return Future.value(0);
    return _track(() => _evictLRU(pinnedAyahs: pinnedAyahs));
  }

  Future<int> _evictLRU({required Set<int> pinnedAyahs}) async {
    await init();
    final targetSize = (maxCacheSizeBytes * lowWatermarkRatio).toInt();
    if (currentCacheSizeBytes <= maxCacheSizeBytes) return 0;

    // Sort entries ascending by lastAccessedAt (oldest first)
    final sortedEntries = _entries.values.toList()
      ..sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));

    int evictedBytes = 0;

    for (final entry in sortedEntries) {
      if (currentCacheSizeBytes <= targetSize) break;

      // Pinned protection: skip currently playing or active session Ayahs
      if (entry.pinned || pinnedAyahs.contains(entry.globalAyah)) {
        continue;
      }

      final file = _getFinalFile(entry.reciterId, entry.globalAyah);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      _entries.remove(entry.key);
      evictedBytes += entry.fileSizeBytes;
    }

    await _saveMetadata();
    if (evictedBytes > 0) _notifyChanged();
    return evictedBytes;
  }

  /// Pins an existing item, or downloads it as a durable user-owned download.
  Future<File?> downloadAyah({
    required String reciter,
    required int globalAyah,
  }) => cacheAyah(
    reciter: reciter,
    globalAyah: globalAyah,
    pinnedAyahs: {globalAyah},
    pin: true,
  );

  Future<int> cachedCount({
    required String reciter,
    required int startGlobalAyah,
    required int endGlobalAyah,
    bool pinnedOnly = true,
  }) async {
    await init();
    var count = 0;
    for (var ayah = startGlobalAyah; ayah <= endGlobalAyah; ayah++) {
      final entry = _entries['${reciter}_$ayah'];
      if (entry != null && (!pinnedOnly || entry.pinned)) count++;
    }
    return count;
  }

  int cachedCountNow({
    required String reciter,
    required int startGlobalAyah,
    required int endGlobalAyah,
    bool pinnedOnly = true,
  }) {
    var count = 0;
    for (var ayah = startGlobalAyah; ayah <= endGlobalAyah; ayah++) {
      final entry = _entries['${reciter}_$ayah'];
      if (entry != null && (!pinnedOnly || entry.pinned)) count++;
    }
    return count;
  }

  /// Removes only explicit downloads in a range; opportunistic cache is left intact.
  Future<void> removeDownloadRange({
    required String reciter,
    required int startGlobalAyah,
    required int endGlobalAyah,
  }) {
    if (_clearing != null) return Future.value();
    return _track(
      () => _removeDownloadRange(
        reciter: reciter,
        startGlobalAyah: startGlobalAyah,
        endGlobalAyah: endGlobalAyah,
      ),
    );
  }

  Future<void> _removeDownloadRange({
    required String reciter,
    required int startGlobalAyah,
    required int endGlobalAyah,
  }) async {
    await init();
    for (var ayah = startGlobalAyah; ayah <= endGlobalAyah; ayah++) {
      final key = '${reciter}_$ayah';
      final entry = _entries[key];
      if (entry == null || !entry.pinned) continue;
      final file = _getFinalFile(reciter, ayah);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _entries.remove(key);
    }
    await _saveMetadata();
    _notifyChanged();
  }

  /// Rejects new work, cancels network transfers and drains every older write
  /// before deleting. No pre-clear task can recreate a removed file afterwards.
  Future<void> clearCache() {
    return _clearing ??= _clearCache().whenComplete(() {
      _clearing = null;
    });
  }

  Future<void> _clearCache() async {
    await init();
    await Future.wait([
      for (final operation in _activeDownloads.values.toList())
        operation.cancel(),
    ]);
    await Future.wait(_operations.toList());
    await _metadataWrites;
    if (await _cacheDir!.exists()) {
      await for (final entity in _cacheDir!.list()) {
        await entity.delete(recursive: true);
      }
    }
    _entries.clear();
    await _tmpDir!.create(recursive: true);
    await _saveMetadata();
    _notifyChanged();
  }

  /// Validates that [file] is a non-empty, authentic audio stream.
  static Future<bool> isValidAudioFile(File file) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length < 1024) return false;

    // Inspect first few bytes for ID3 tag or MP3 frame sync
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final header = await raf.read(12);
      if (header.length < 3) return false;

      // Check ID3 header: 'I', 'D', '3'
      if (header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) {
        return true;
      }

      // Check MPEG sync word (11 bits set: 0xFF followed by 0xE0 mask)
      if (header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
        return true;
      }

      // These containers are also supported by the native audio players.
      // Never treat an arbitrary HTTP 200 error page as a saved recitation.
      bool signature(int offset, String value) {
        if (header.length < offset + value.length) return false;
        for (var i = 0; i < value.length; i++) {
          if (header[offset + i] != value.codeUnitAt(i)) return false;
        }
        return true;
      }

      return signature(0, 'OggS') ||
          signature(0, 'fLaC') ||
          (signature(0, 'RIFF') && signature(8, 'WAVE')) ||
          signature(4, 'ftyp');
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  /// Checks if the device is currently on Wi-Fi for preloading.
  Future<bool> isWifiAvailable() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  /// Checks if network connectivity is available (Wi-Fi, cellular, or ethernet).
  Future<bool> isNetworkAvailable() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet,
      );
    } catch (_) {
      return false;
    }
  }

  File _getFinalFile(String reciter, int globalAyah) {
    return File('${_cacheDir!.path}/$reciter/$globalAyah.mp3');
  }

  void _removeEntry(String key) {
    if (_entries.remove(key) != null) {
      unawaited(_saveMetadata());
      _notifyChanged();
    }
  }

  Future<void> _cleanInterruptedDownloads() async {
    if (_tmpDir != null && await _tmpDir!.exists()) {
      try {
        final tmpEntities = _tmpDir!.listSync();
        for (final entity in tmpEntities) {
          if (entity is File) {
            await entity.delete();
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _loadMetadata() async {
    _entries.clear();
    if (_metadataFile == null || !await _metadataFile!.exists()) return;

    try {
      final content = await _metadataFile!.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            _entries[entry.key] = QuranAudioCacheEntry.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      }
    } catch (_) {
      _entries.clear();
    }
  }

  Future<void> _saveMetadata() {
    _metadataWrites = _metadataWrites.then((_) => _writeMetadata());
    return _metadataWrites;
  }

  Future<void> _writeMetadata() async {
    if (_metadataFile == null) return;
    try {
      final data = {
        for (final entry in _entries.entries) entry.key: entry.value.toJson(),
      };
      final raw = jsonEncode(data);
      final tmp = File(
        '${_metadataFile!.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await tmp.writeAsString(raw, flush: true);
      await tmp.rename(_metadataFile!.path);
    } catch (_) {}
  }
}

class _CacheDownload {
  _CacheDownload({required this.pin, required Set<int> pinnedAyahs})
    : pinnedAyahs = Set.of(pinnedAyahs);

  bool pin;
  bool cancelled = false;
  final Set<int> pinnedAyahs;
  HttpClientRequest? request;
  StreamIterator<List<int>>? chunks;
  late Future<File?> result;

  Future<void> cancel() async {
    cancelled = true;
    abortRequest();
    await chunks?.cancel();
  }

  void abortRequest() {
    final pending = request;
    if (pending == null) return;
    // A connection can finish after cancellation while getUrl was pending.
    // Observe done even when close() was never reached.
    unawaited(
      pending.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    pending.abort();
  }
}
