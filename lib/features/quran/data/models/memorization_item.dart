import 'package:equatable/equatable.dart';

import 'memorization_status.dart';
import 'murajaah_models.dart';

/// Immutable domain entity representing the personal memorization record of an individual Ayah.
///
/// Anchored strictly to the canonical [globalAyah] (1..6236).
/// Does not duplicate Quran text, which is resolved via [QuranRepository].
class MemorizationItem extends Equatable {
  const MemorizationItem({
    required this.globalAyah,
    this.status = MemorizationStatus.notStarted,
    this.mistakeCount = 0,
    this.lastReviewedAt,
    required this.updatedAt,
    this.nextReviewAt,
    this.intervalDays,
    this.consecutiveSuccesses = 0,
    this.lastOutcome,
  }) : assert(
         globalAyah >= 1 && globalAyah <= 6236,
         'globalAyah must be between 1 and 6236, got $globalAyah',
       ),
       assert(mistakeCount >= 0, 'mistakeCount must not be negative'),
       assert(
         consecutiveSuccesses >= 0,
         'consecutiveSuccesses must not be negative',
       );

  /// The canonical global 1-based index (1..6236).
  final int globalAyah;

  /// Current mastery status.
  final MemorizationStatus status;

  /// Number of times the user flagged difficulty or marked this Ayah for revision.
  final int mistakeCount;

  /// Timestamp of the most recent practice or testing event.
  final DateTime? lastReviewedAt;

  /// Timestamp when this record was last modified.
  final DateTime updatedAt;

  /// Timestamp when this Ayah is next due for adaptive review.
  final DateTime? nextReviewAt;

  /// Computed review interval in days between reviews.
  final int? intervalDays;

  /// Number of consecutive successful recall events (good or easy).
  final int consecutiveSuccesses;

  /// The most recent self-assessment outcome.
  final ReviewOutcome? lastOutcome;

  MemorizationItem copyWith({
    MemorizationStatus? status,
    int? mistakeCount,
    DateTime? lastReviewedAt,
    DateTime? updatedAt,
    DateTime? nextReviewAt,
    bool clearNextReviewAt = false,
    int? intervalDays,
    bool clearIntervalDays = false,
    int? consecutiveSuccesses,
    ReviewOutcome? lastOutcome,
    bool clearLastOutcome = false,
  }) => MemorizationItem(
    globalAyah: globalAyah,
    status: status ?? this.status,
    mistakeCount: mistakeCount ?? this.mistakeCount,
    lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    nextReviewAt: clearNextReviewAt
        ? null
        : (nextReviewAt ?? this.nextReviewAt),
    intervalDays: clearIntervalDays
        ? null
        : (intervalDays ?? this.intervalDays),
    consecutiveSuccesses: consecutiveSuccesses ?? this.consecutiveSuccesses,
    lastOutcome: clearLastOutcome ? null : (lastOutcome ?? this.lastOutcome),
  );

  factory MemorizationItem.fromJson(Map<String, dynamic> json) {
    final rawGlobal = (json['g'] ?? json['globalAyah']) as num?;
    final global = rawGlobal?.toInt() ?? 1;
    final safeGlobal = global.clamp(1, 6236);

    final rawStatus = json['s'] ?? json['status'];
    final status = rawStatus is String
        ? MemorizationStatus.fromString(rawStatus)
        : MemorizationStatus.notStarted;

    final rawMistakes = (json['m'] ?? json['mistakeCount']) as num?;
    final mistakeCount = (rawMistakes?.toInt() ?? 0).clamp(0, 999999);

    final rawReviewed = json['r'] ?? json['lastReviewedAt'];
    final lastReviewedAt = rawReviewed is String
        ? DateTime.tryParse(rawReviewed)
        : null;

    final rawUpdated = json['u'] ?? json['updatedAt'];
    final updatedAt =
        (rawUpdated is String ? DateTime.tryParse(rawUpdated) : null) ??
        DateTime.now();

    final rawNextReview = json['nr'] ?? json['nextReviewAt'];
    final nextReviewAt = rawNextReview is String
        ? DateTime.tryParse(rawNextReview)
        : null;

    final rawInterval = (json['iv'] ?? json['intervalDays']) as num?;
    final intervalDays = rawInterval?.toInt();

    final rawSuccesses = (json['cs'] ?? json['consecutiveSuccesses']) as num?;
    final consecutiveSuccesses = (rawSuccesses?.toInt() ?? 0).clamp(0, 999999);

    final rawLastOutcome = json['lo'] ?? json['lastOutcome'];
    final lastOutcome = rawLastOutcome is String
        ? ReviewOutcome.fromString(rawLastOutcome)
        : null;

    return MemorizationItem(
      globalAyah: safeGlobal,
      status: status,
      mistakeCount: mistakeCount,
      lastReviewedAt: lastReviewedAt,
      updatedAt: updatedAt,
      nextReviewAt: nextReviewAt,
      intervalDays: intervalDays,
      consecutiveSuccesses: consecutiveSuccesses,
      lastOutcome: lastOutcome,
    );
  }

  Map<String, dynamic> toJson() => {
    'g': globalAyah,
    's': status.name,
    'm': mistakeCount,
    if (lastReviewedAt != null) 'r': lastReviewedAt!.toIso8601String(),
    'u': updatedAt.toIso8601String(),
    if (nextReviewAt != null) 'nr': nextReviewAt!.toIso8601String(),
    if (intervalDays != null) 'iv': intervalDays,
    if (consecutiveSuccesses > 0) 'cs': consecutiveSuccesses,
    if (lastOutcome != null) 'lo': lastOutcome!.name,
  };

  @override
  List<Object?> get props => [
    globalAyah,
    status,
    mistakeCount,
    lastReviewedAt,
    updatedAt,
    nextReviewAt,
    intervalDays,
    consecutiveSuccesses,
    lastOutcome,
  ];
}
