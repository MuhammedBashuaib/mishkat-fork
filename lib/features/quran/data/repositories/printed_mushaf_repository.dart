import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/printed_mushaf_models.dart';

/// Loads the verified printed line/word map entirely from bundled assets.
class PrintedMushafRepository {
  PrintedMushafRepository({this.bundle});

  static final instance = PrintedMushafRepository();

  final AssetBundle? bundle;
  PrintedMushafData? _cache;
  Future<PrintedMushafData>? _pending;

  bool get isLoaded => _cache != null;

  PrintedMushafData get data =>
      _cache ?? (throw StateError('Printed Mushaf data has not been loaded.'));

  Future<PrintedMushafData> load() {
    final cached = _cache;
    // Cache decoded data, not a completed Future tied to another caller zone.
    if (cached != null) return Future.value(cached);
    return _pending ??= _read();
  }

  Future<PrintedMushafData> _read() async {
    try {
      final raw = await (bundle ?? rootBundle).loadString(
        'assets/data/printed-mushaf.json',
      );
      final decoded = PrintedMushafData.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (decoded.version != 1 || decoded.pages.length != 604) {
        throw const FormatException('Unsupported printed Mushaf data.');
      }
      for (var index = 0; index < decoded.pages.length; index++) {
        if (decoded.pages[index].page != index + 1) {
          throw const FormatException('Printed Mushaf pages are incomplete.');
        }
      }
      return _cache = decoded;
    } finally {
      _pending = null;
    }
  }

  PrintedMushafPage? page(int number) {
    final pages = _cache?.pages;
    if (pages == null || number < 1 || number > pages.length) return null;
    return pages[number - 1];
  }
}
