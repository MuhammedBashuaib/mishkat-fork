import 'package:equatable/equatable.dart';

class LibraryBook extends Equatable {
  const LibraryBook({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.description,
    required this.contentPath,
    required this.contentType,
    required this.itemLabel,
    required this.availableItems,
    required this.expectedItems,
    required this.sourceName,
    required this.sourceUrl,
  });
  final String id;
  final String title;
  final String author;
  final String category;
  final String description;
  final String contentPath;
  final String contentType;
  final String itemLabel;
  final int availableItems;
  final int expectedItems;
  final String sourceName;
  final String sourceUrl;

  factory LibraryBook.fromJson(Map<String, dynamic> json) => LibraryBook(
    id: json['id'] as String,
    title: json['title'] as String,
    author: json['author'] as String,
    category: json['category'] as String? ?? '',
    description: json['description'] as String? ?? '',
    contentPath: json['contentPath'] as String,
    contentType: json['contentType'] as String? ?? 'entries',
    itemLabel: json['itemLabel'] as String? ?? 'مادة',
    availableItems: (json['availableItems'] as num?)?.toInt() ?? 0,
    expectedItems: (json['expectedItems'] as num?)?.toInt() ?? 0,
    sourceName: json['sourceName'] as String? ?? '',
    sourceUrl: json['sourceUrl'] as String? ?? '',
  );

  @override
  List<Object?> get props => [
    id,
    title,
    author,
    category,
    description,
    contentPath,
    contentType,
    itemLabel,
    availableItems,
    expectedItems,
    sourceName,
    sourceUrl,
  ];
}

class LibraryEntry extends Equatable {
  const LibraryEntry({
    required this.id,
    required this.number,
    required this.title,
    required this.chapter,
    required this.text,
    required this.reference,
    required this.sourceUrl,
    this.narrator = '',
  });
  final String id;
  final int number;
  final String title;
  final String chapter;
  final String narrator;
  final String text;
  final String reference;
  final String sourceUrl;

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
    id: json['id'] as String,
    number: (json['number'] as num).toInt(),
    title: json['title'] as String,
    chapter: json['chapter'] as String,
    narrator: json['narrator'] as String? ?? '',
    text: json['text'] as String,
    // Some source records legitimately have no printed reference. Treat that
    // field as optional so one incomplete record cannot block the whole book.
    reference: json['reference'] as String? ?? '',
    sourceUrl: json['sourceUrl'] as String? ?? '',
  );

  @override
  List<Object?> get props => [
    id,
    number,
    title,
    chapter,
    narrator,
    text,
    reference,
    sourceUrl,
  ];
}
