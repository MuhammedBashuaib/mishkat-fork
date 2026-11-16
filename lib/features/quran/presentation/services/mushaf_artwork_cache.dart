import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Owns a bounded set of decoded pages. A displayed picture is never evicted.
class MushafArtworkCache {
  factory MushafArtworkCache({
    required AssetBundle bundle,
    int maxEntries = 5,
    Future<PictureInfo> Function(int page)? decoder,
  }) => MushafArtworkCache._(bundle, maxEntries, decoder);

  MushafArtworkCache._(this._bundle, this.maxEntries, this._decoder)
    : assert(maxEntries > 0);

  static final _bundles = Expando<MushafArtworkCache>();

  static MushafArtworkCache forBundle(AssetBundle bundle) =>
      _bundles[bundle] ??= MushafArtworkCache(bundle: bundle);

  final AssetBundle _bundle;
  final int maxEntries;
  final Future<PictureInfo> Function(int page)? _decoder;
  final _entries = <int, _PageEntry>{};

  Future<MushafArtworkLease> acquire(int page) {
    if (page < 1 || page > 604) {
      throw RangeError.range(page, 1, 604, 'page');
    }
    final entry = _entries.remove(page) ?? _PageEntry();
    _entries[page] = entry;
    entry.references++;
    final picture = entry.picture;
    if (picture != null) {
      return SynchronousFuture(
        MushafArtworkLease._(picture, () => _release(page, entry)),
      );
    }
    entry.pending ??= _load(page, entry);
    return entry.pending!.then(
      (picture) => MushafArtworkLease._(picture, () => _release(page, entry)),
      onError: (Object error, StackTrace stack) {
        _release(page, entry);
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  Future<void> prefetch(int page) async {
    if (page < 1 || page > 604) return;
    final lease = await acquire(page);
    lease.release();
  }

  Future<PictureInfo> _load(int page, _PageEntry entry) async {
    try {
      final picture = await (_decoder?.call(page) ?? _decode(page));
      entry.picture = picture;
      return picture;
    } catch (_) {
      if (identical(_entries[page], entry)) _entries.remove(page);
      rethrow;
    } finally {
      entry.pending = null;
      _trim();
    }
  }

  Future<PictureInfo> _decode(int page) async {
    final bytes = await _bundle.load(
      'assets/mushaf/pages/${page.toString().padLeft(3, '0')}.svg',
    );
    // SvgLoader's release-mode compiler captures its loader in an isolate.
    // Pass bytes only: an AssetBundle may contain cached Futures and other
    // objects that cannot be sent to another isolate.
    return vg.loadPicture(SvgBytesLoader(Uint8List.sublistView(bytes)), null);
  }

  void _release(int page, _PageEntry entry) {
    entry.references--;
    if (entry.references == 0 && entry.discardOnRelease) {
      if (identical(_entries[page], entry)) _entries.remove(page);
      entry.picture?.picture.dispose();
      entry.picture = null;
    }
    _trim();
  }

  void _trim() {
    if (_entries.length <= maxEntries) return;
    for (final page in _entries.keys.toList()) {
      if (_entries.length <= maxEntries) break;
      final entry = _entries[page]!;
      if (entry.references != 0 || entry.pending != null) continue;
      _entries.remove(page);
      entry.picture?.picture.dispose();
    }
  }

  /// Clears retained pages without invalidating pictures currently on screen.
  void clear() {
    for (final page in _entries.keys.toList()) {
      final entry = _entries[page]!;
      if (entry.references == 0 && entry.pending == null) {
        _entries.remove(page);
        entry.picture?.picture.dispose();
      } else {
        entry.discardOnRelease = true;
      }
    }
  }
}

class _PageEntry {
  PictureInfo? picture;
  Future<PictureInfo>? pending;
  int references = 0;
  bool discardOnRelease = false;
}

/// A picture remains valid until all of its consumers release their leases.
class MushafArtworkLease {
  MushafArtworkLease._(this.picture, this._onRelease);

  final PictureInfo picture;
  final VoidCallback _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}
