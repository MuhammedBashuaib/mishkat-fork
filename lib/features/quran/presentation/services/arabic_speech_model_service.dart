import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ArabicSpeechModelAvailability {
  installed,
  downloadable,
  pending,
  unsupported,
  unknown,
}

class ArabicSpeechModelStatus {
  const ArabicSpeechModelStatus({
    this.availability = ArabicSpeechModelAvailability.unknown,
    this.localeId = 'ar-SA',
    this.reason,
    this.progress,
  });

  factory ArabicSpeechModelStatus.fromMap(Map<Object?, Object?> map) {
    final availability = ArabicSpeechModelAvailability.values.firstWhere(
      (value) => value.name == map['status'],
      orElse: () => ArabicSpeechModelAvailability.unknown,
    );
    final locale = map['localeId'];
    // Only a verified Arabic model can enable offline recitation.
    if (availability == ArabicSpeechModelAvailability.installed &&
        (locale is! String ||
            !RegExp(r'^ar(?:[-_]|$)', caseSensitive: false).hasMatch(locale))) {
      return const ArabicSpeechModelStatus(reason: 'invalidLocale');
    }
    return ArabicSpeechModelStatus(
      availability: availability,
      localeId: locale is String ? locale : 'ar-SA',
      reason: map['reason'] as String?,
      progress: map['progress'] is num
          ? (map['progress'] as num).toInt().clamp(0, 100)
          : null,
    );
  }

  final ArabicSpeechModelAvailability availability;
  final String localeId;
  final String? reason;
  final int? progress;

  bool get isInstalled =>
      availability == ArabicSpeechModelAvailability.installed;
  bool get isPending => availability == ArabicSpeechModelAvailability.pending;
  bool get canDownload =>
      availability == ArabicSpeechModelAvailability.downloadable;
}

/// Shares the platform model state between the download sheet and recognition.
/// Installed state is always checked with the OS, never inferred from a request
/// being accepted or a progress bar reaching 100%.
class ArabicSpeechModelService extends ChangeNotifier {
  ArabicSpeechModelService({
    this.channel = const MethodChannel('com.dakomn.mishkatapp/speech_settings'),
  }) {
    channel.setMethodCallHandler(_onNativeEvent);
  }

  static final instance = ArabicSpeechModelService();
  final MethodChannel channel;
  ArabicSpeechModelStatus _status = const ArabicSpeechModelStatus();
  Future<ArabicSpeechModelStatus>? _refreshOperation;
  Future<ArabicSpeechModelStatus>? _downloadOperation;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _foreground = true;
  bool _offlineOnly = false;
  int _revision = 0;

  ArabicSpeechModelStatus get status => _status;
  bool get isChecking => _refreshOperation != null;
  bool get isRequestingDownload => _downloadOperation != null;
  bool get offlineOnly => _offlineOnly;

  /// A real recognition failure takes precedence over a capability query.
  /// In particular, iOS may advertise local support before its assets work.
  void reportUnavailable() {
    _update(
      ArabicSpeechModelStatus(
        localeId: _status.localeId,
        reason: 'modelUnavailable',
      ),
    );
  }

  void setForeground(bool value) {
    _foreground = value;
    _syncPolling();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _syncPolling();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _syncPolling();
  }

  set offlineOnly(bool value) {
    if (_disposed || value == _offlineOnly) return;
    _offlineOnly = value;
    notifyListeners();
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    if (_disposed ||
        call.method != 'arabicModelStatus' ||
        call.arguments is! Map) {
      return;
    }
    _update(ArabicSpeechModelStatus.fromMap(call.arguments as Map));
  }

  void _update(ArabicSpeechModelStatus value) {
    if (_disposed) return;
    _revision++;
    // A support poll does not include byte progress; preserve native progress.
    if (value.isPending && _status.isPending && value.progress == null) {
      value = ArabicSpeechModelStatus(
        availability: value.availability,
        localeId: value.localeId,
        reason: value.reason,
        progress: _status.progress,
      );
    }
    _status = value;
    _syncPolling();
    notifyListeners();
  }

  void _syncPolling() {
    if (!_disposed && _foreground && hasListeners && _status.isPending) {
      _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(refresh());
      });
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<ArabicSpeechModelStatus> _invoke(
    String method, {
    Map<String, Object?>? arguments,
  }) async {
    final revision = _revision;
    try {
      final result = await channel
          .invokeMapMethod<Object?, Object?>(method, arguments)
          .timeout(const Duration(seconds: 10));
      if (!_disposed && revision == _revision) {
        _update(ArabicSpeechModelStatus.fromMap(result ?? const {}));
      }
    } on MissingPluginException {
      if (revision == _revision) {
        _update(
          const ArabicSpeechModelStatus(
            availability: ArabicSpeechModelAvailability.unsupported,
            reason: 'platformUnsupported',
          ),
        );
      }
    } catch (_) {
      if (revision == _revision) {
        _update(
          ArabicSpeechModelStatus(
            reason: method == 'downloadArabicModel'
                ? 'downloadFailed'
                : 'checkUnavailable',
          ),
        );
      }
    }
    return _status;
  }

  Future<ArabicSpeechModelStatus> refresh({
    bool retryUnavailable = false,
  }) async {
    if (_disposed) return _status;
    if (_status.reason == 'modelUnavailable' && !retryUnavailable) {
      return _status;
    }
    // A download result must not be discarded by an older support query.
    final downloading = _downloadOperation;
    if (downloading != null) return downloading;
    final pending = _refreshOperation;
    if (pending != null) return pending;
    final operation = _invoke('getArabicModelStatus');
    _refreshOperation = operation;
    notifyListeners();
    try {
      return await operation;
    } finally {
      _refreshOperation = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<ArabicSpeechModelStatus> download() async {
    if (_disposed) return _status;
    final pending = _downloadOperation;
    if (pending != null) return pending;
    final operation = _downloadAfterRefresh();
    _downloadOperation = operation;
    notifyListeners();
    try {
      return await operation;
    } finally {
      _downloadOperation = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<ArabicSpeechModelStatus> _downloadAfterRefresh() async {
    await _refreshOperation;
    if (_disposed || !_status.canDownload) return _status;
    return _invoke(
      'downloadArabicModel',
      arguments: {'localeId': _status.localeId},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
