import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/tafsir_models.dart';

/// Repository for authentic Tafsir and Quran commentary data.
///
/// Follows Local-First principles: loads bundled static assets once into an
/// in-memory index for instant O(1) Ayah commentary retrieval without network.
class TafsirRepository {
  TafsirRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Map<String, TafsirPackage> _packages = <String, TafsirPackage>{};

  static const String defaultSourceId = 'arabic_moyassar';

  static const Map<String, String> _sourceAssets = {
    'arabic_moyassar': 'assets/data/tafsir-muyassar.json',
  };

  /// Returns metadata for all registered Tafsir sources.
  List<TafsirSource> getSources() {
    if (_packages.isNotEmpty) {
      return _packages.values.map((pkg) => pkg.source).toList(growable: false);
    }
    // Static fallback before packages are loaded
    return const [
      TafsirSource(
        id: 'arabic_moyassar',
        name: 'التفسير الميسر',
        language: 'ar',
        author: 'نخبة من العلماء بإشراف مجمع الملك فهد لطباعة المصحف الشريف',
        publisher: 'مجمع الملك فهد لطباعة المصحف الشريف',
        description: 'تفسير ميسر أعدته نخبة من العلماء وصدر عن مجمع الملك فهد لطباعة المصحف الشريف بالمدينة المنورة وفق منهج أهل السنة والجماعة.',
        attribution: 'مأخوذ وموثق من مجمع الملك فهد لطباعة المصحف الشريف بالمدينة المنورة عبر موسوعة القرآن الكريم (QuranEnc.com)',
        license: 'شروط النشر الحر المعتمدة لموسوعة القرآن الكريم (QuranEnc)',
        version: '1.0.0',
        sourceUrl: 'https://quranenc.com/ar/browse/arabic_moyassar',
        totalAyahs: 6236,
      ),
    ];
  }

  /// Loads a Tafsir package into memory by source ID.
  Future<TafsirPackage> load({String sourceId = defaultSourceId}) async {
    final cached = _packages[sourceId];
    if (cached != null) return cached;

    final assetPath = _sourceAssets[sourceId];
    if (assetPath == null) {
      throw ArgumentError('Unknown Tafsir source ID: $sourceId');
    }

    final rawJson = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final package = TafsirPackage.fromJson(decoded);

    _packages[sourceId] = package;
    return package;
  }

  /// Loads a Tafsir package directly from a raw JSON string (primarily for tests).
  TafsirPackage loadFromJsonString(
    String jsonString, {
    String sourceId = defaultSourceId,
  }) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final package = TafsirPackage.fromJson(decoded);
    _packages[sourceId] = package;
    return package;
  }

  /// Retrieves a specific Ayah Tafsir entry by canonical global Ayah number.
  ///
  /// Lookup complexity is O(1). Returns null if the entry does not exist.
  TafsirEntry? getTafsir(int globalAyah, [String? sourceId]) {
    final effectiveSourceId = sourceId ?? defaultSourceId;
    final package = _packages[effectiveSourceId];
    return package?.getEntry(globalAyah);
  }

  /// Retrieves all available commentaries for a global Ayah across loaded sources.
  List<TafsirEntry> getAvailableTafsirs(int globalAyah) {
    final results = <TafsirEntry>[];
    for (final package in _packages.values) {
      final entry = package.getEntry(globalAyah);
      if (entry != null) {
        results.add(entry);
      }
    }
    return results;
  }

  /// Clears in-memory caches (useful for testing).
  void clearCache() {
    _packages.clear();
  }
}
