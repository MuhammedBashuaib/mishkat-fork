import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../../features/quran/data/models/quran_models.dart';
import 'quran_audio_cache_service.dart';

enum OfflineDownloadStatus {
  idle,
  checking,
  downloading,
  completed,
  failed,
  cancelled,
}

@immutable
class OfflineDownloadState {
  const OfflineDownloadState({
    this.status = OfflineDownloadStatus.idle,
    this.label = '',
    this.reciter = '',
    this.startAyah = 0,
    this.endAyah = 0,
    this.completed = 0,
    this.total = 0,
    this.error,
  });

  final OfflineDownloadStatus status;
  final String label;
  final String reciter;
  final int startAyah;
  final int endAyah;
  final int completed;
  final int total;
  final String? error;

  bool get isRunning =>
      status == OfflineDownloadStatus.checking ||
      status == OfflineDownloadStatus.downloading;
  double get progress => total == 0 ? 0 : completed / total;
}

/// Coordinates durable Quran audio downloads. A single queue is intentional:
/// it avoids saturating the connection and remains predictable on mobile data.
class OfflineAudioDownloadController extends ChangeNotifier {
  OfflineAudioDownloadController(this._cache);

  final QuranAudioCacheService _cache;
  OfflineDownloadState _state = const OfflineDownloadState();
  int _operationId = 0;
  bool _clearing = false;

  OfflineDownloadState get state => _state;
  QuranAudioCacheService get cache => _cache;

  Future<void> initialize() async {
    await _cache.init();
    notifyListeners();
  }

  Future<int> cachedCount({
    required String reciter,
    required int startAyah,
    required int endAyah,
  }) => _cache.cachedCount(
    reciter: reciter,
    startGlobalAyah: startAyah,
    endGlobalAyah: endAyah,
  );

  int cachedCountNow({
    required String reciter,
    required int startAyah,
    required int endAyah,
  }) => _cache.cachedCountNow(
    reciter: reciter,
    startGlobalAyah: startAyah,
    endGlobalAyah: endAyah,
  );

  Future<void> downloadSurah({
    required ReciterInfo reciter,
    required QuranChapter chapter,
  }) => downloadRange(
    reciter: reciter,
    startAyah: chapter.globalStart,
    endAyah: chapter.globalStart + chapter.ayahs.length - 1,
    label: 'سورة ${chapter.name}',
  );

  Future<void> downloadPages({
    required ReciterInfo reciter,
    required QuranData data,
    required int startPage,
    required int endPage,
    required String label,
  }) {
    final first = data.page(startPage.clamp(1, 604)).first.global;
    final last = data.page(endPage.clamp(startPage, 604)).last.global;
    return downloadRange(
      reciter: reciter,
      startAyah: first,
      endAyah: last,
      label: label,
    );
  }

  Future<void> downloadRange({
    required ReciterInfo reciter,
    required int startAyah,
    required int endAyah,
    required String label,
  }) async {
    if (_clearing || _state.isRunning) return;
    if (reciter.source == ReciterAudioSource.segmentedSurah) {
      _setState(
        OfflineDownloadState(
          status: OfflineDownloadStatus.failed,
          label: label,
          reciter: reciter.id,
          startAyah: startAyah,
          endAyah: endAyah,
          error: 'هذا القارئ متاح كبث متصل فقط. اختر قارئًا آية بآية للتنزيل.',
        ),
      );
      return;
    }

    final operationId = ++_operationId;
    final total = endAyah - startAyah + 1;
    _setState(
      OfflineDownloadState(
        status: OfflineDownloadStatus.checking,
        label: label,
        reciter: reciter.id,
        startAyah: startAyah,
        endAyah: endAyah,
        total: total,
      ),
    );

    if (!await _cache.isNetworkAvailable()) {
      if (operationId != _operationId) return;
      _setState(
        OfflineDownloadState(
          status: OfflineDownloadStatus.failed,
          label: label,
          reciter: reciter.id,
          startAyah: startAyah,
          endAyah: endAyah,
          total: total,
          error: 'لا يوجد اتصال الآن. اتصل بالإنترنت مرة واحدة لإكمال التنزيل.',
        ),
      );
      return;
    }

    var completed = 0;
    var failures = 0;
    for (var ayah = startAyah; ayah <= endAyah; ayah++) {
      if (operationId != _operationId) return;
      _setState(
        OfflineDownloadState(
          status: OfflineDownloadStatus.downloading,
          label: label,
          reciter: reciter.id,
          startAyah: startAyah,
          endAyah: endAyah,
          completed: completed,
          total: total,
        ),
      );
      final file = await _cache.downloadAyah(
        reciter: reciter.id,
        globalAyah: ayah,
      );
      if (operationId != _operationId) return;
      if (file == null) {
        failures++;
        // Stop early when the source or connection is consistently failing.
        if (failures >= 3) break;
      } else {
        completed++;
        failures = 0;
      }
    }

    if (operationId != _operationId) return;
    final saved = await cachedCount(
      reciter: reciter.id,
      startAyah: startAyah,
      endAyah: endAyah,
    );
    if (operationId != _operationId) return;
    _setState(
      OfflineDownloadState(
        status: saved == total
            ? OfflineDownloadStatus.completed
            : OfflineDownloadStatus.failed,
        label: label,
        reciter: reciter.id,
        startAyah: startAyah,
        endAyah: endAyah,
        completed: saved,
        total: total,
        error: saved == total
            ? null
            : 'اكتمل حفظ $saved من $total. يمكنك المحاولة مجددًا لإكمال الباقي.',
      ),
    );
  }

  void cancel() {
    if (!_state.isRunning) return;
    _operationId++;
    _setState(
      OfflineDownloadState(
        status: OfflineDownloadStatus.cancelled,
        label: _state.label,
        reciter: _state.reciter,
        startAyah: _state.startAyah,
        endAyah: _state.endAyah,
        completed: _state.completed,
        total: _state.total,
      ),
    );
  }

  /// Invalidates the queue before clearing its files. In-flight completion
  /// cannot start another Ayah or restore progress after a user data reset.
  Future<void> clearAllDownloads() async {
    _clearing = true;
    _operationId++;
    _setState(const OfflineDownloadState());
    try {
      await _cache.clearCache();
    } finally {
      _clearing = false;
    }
  }

  Future<void> removeRange({
    required String reciter,
    required int startAyah,
    required int endAyah,
  }) => _cache.removeDownloadRange(
    reciter: reciter,
    startGlobalAyah: startAyah,
    endGlobalAyah: endAyah,
  );

  void _setState(OfflineDownloadState value) {
    _state = value;
    notifyListeners();
  }
}
