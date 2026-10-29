import 'package:equatable/equatable.dart';

/// Metadata describing an authentic Tafsir or Quran commentary source.
class TafsirSource extends Equatable {
  const TafsirSource({
    required this.id,
    required this.name,
    required this.language,
    required this.author,
    required this.publisher,
    required this.description,
    required this.attribution,
    required this.license,
    required this.version,
    required this.sourceUrl,
    required this.totalAyahs,
  });

  final String id;
  final String name;
  final String language;
  final String author;
  final String publisher;
  final String description;
  final String attribution;
  final String license;
  final String version;
  final String sourceUrl;
  final int totalAyahs;

  factory TafsirSource.fromJson(Map<String, dynamic> json) => TafsirSource(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    language: json['language'] as String? ?? 'ar',
    author: json['author'] as String? ?? '',
    publisher: json['publisher'] as String? ?? '',
    description: json['description'] as String? ?? '',
    attribution: json['attribution'] as String? ?? '',
    license: json['license'] as String? ?? '',
    version: json['version'] as String? ?? '',
    sourceUrl: json['sourceUrl'] as String? ?? '',
    totalAyahs: (json['totalAyahs'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'language': language,
    'author': author,
    'publisher': publisher,
    'description': description,
    'attribution': attribution,
    'license': license,
    'version': version,
    'sourceUrl': sourceUrl,
    'totalAyahs': totalAyahs,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    language,
    author,
    publisher,
    description,
    attribution,
    license,
    version,
    sourceUrl,
    totalAyahs,
  ];
}

/// A single commentary entry for a specific global Ayah.
class TafsirEntry extends Equatable {
  const TafsirEntry({
    required this.sourceId,
    required this.globalAyah,
    required this.text,
  });

  final String sourceId;
  final int globalAyah;
  final String text;

  @override
  List<Object?> get props => [sourceId, globalAyah, text];
}

/// In-memory representation of a loaded Tafsir package.
class TafsirPackage extends Equatable {
  const TafsirPackage({
    required this.schemaVersion,
    required this.source,
    required this.entries,
  });

  final int schemaVersion;
  final TafsirSource source;
  final Map<int, String> entries;

  TafsirEntry? getEntry(int globalAyah) {
    final text = entries[globalAyah];
    if (text == null || text.isEmpty) return null;
    return TafsirEntry(sourceId: source.id, globalAyah: globalAyah, text: text);
  }

  bool hasEntry(int globalAyah) => entries.containsKey(globalAyah);

  factory TafsirPackage.fromJson(Map<String, dynamic> json) {
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    final source = TafsirSource.fromJson(
      Map<String, dynamic>.from(json['source'] as Map? ?? {}),
    );
    final rawEntries = json['entries'] as Map? ?? {};
    final entries = <int, String>{};
    for (final entry in rawEntries.entries) {
      final key = int.tryParse(entry.key.toString());
      if (key != null && entry.value is String) {
        entries[key] = entry.value as String;
      }
    }
    return TafsirPackage(
      schemaVersion: schemaVersion,
      source: source,
      entries: entries,
    );
  }

  @override
  List<Object?> get props => [schemaVersion, source, entries.length];
}
