import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Short foreground effects use native playback, independently of the single
/// player managed by just_audio_background for Quran and radio playback.
class TasbihCompletionSound {
  static const channel = MethodChannel('com.dakomn.mishkatapp/tasbih_sound');

  Future<void>? _ready;
  bool _disposed = false;

  Future<void> prepare() async {
    if (_disposed) return;
    try {
      await (_ready ??= channel.invokeMethod<void>('prepare'));
    } on Object catch (error) {
      _ready = null; // Allow a later completion to retry initialization.
      debugPrint('Tasbih sound preparation failed: $error');
    }
  }

  Future<void> play() async {
    await prepare();
    if (_disposed || _ready == null) return;
    try {
      await channel.invokeMethod<void>('play');
    } on Object catch (error) {
      debugPrint('Tasbih sound playback failed: $error');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    // Complete initialization before releasing its native resources.
    try {
      await _ready;
      await channel.invokeMethod<void>('dispose');
    } on Object {
      // The platform may already have detached its engine.
    }
  }
}
