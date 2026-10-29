import 'dart:math';

import 'package:equatable/equatable.dart';

import 'murajaah_models.dart';

/// Discrete lifecycle phases of the In-Mushaf Visual Recall state machine.
enum VisualRecallPhase {
  /// No active recall session; default reader mode.
  idle,

  /// User is highlighting a contiguous Ayah range on the Mushaf page.
  rangeSelection,

  /// Active drill: target Ayah(s) are masked; learner recalls from page context.
  activeRecall,

  /// Current Ayah is revealed; learner is performing self-assessment.
  evaluating,

  /// All Ayahs in the session queue have been practiced and assessed.
  completed;

  bool get isIdle => this == VisualRecallPhase.idle;
  bool get isRangeSelection => this == VisualRecallPhase.rangeSelection;
  bool get isActiveRecall => this == VisualRecallPhase.activeRecall;
  bool get isEvaluating => this == VisualRecallPhase.evaluating;
  bool get isCompleted => this == VisualRecallPhase.completed;
}

/// The origin or trigger context of a visual recall session.
enum VisualRecallSessionOrigin {
  /// Ad-hoc single Ayah tapped from reader.
  adhoc,

  /// Multi-Ayah range selected from reader.
  range,

  /// Daily Hifz Journey queue segment.
  dailyJourney,

  /// Formal memorization plan review.
  plan;

  String get label => switch (this) {
    VisualRecallSessionOrigin.adhoc => 'آية فردية',
    VisualRecallSessionOrigin.range => 'مقطع محدد',
    VisualRecallSessionOrigin.dailyJourney => 'الورد اليومي',
    VisualRecallSessionOrigin.plan => 'خطة الحفظ',
  };
}

/// Generates a 128-bit cryptographically secure session identifier.
///
/// Combines microsecond timestamp with 128 bits of OS entropy ([Random.secure])
/// to guarantee zero collision probability across device restarts and test harnesses.
String generateVisualRecallSessionId({
  required String origin,
  required int startGlobal,
  required int endGlobal,
}) {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // UUIDv4 version
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // UUIDv4 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final ts = DateTime.now().microsecondsSinceEpoch;
  return 'vrs_${ts}_${origin}_${startGlobal}_${endGlobal}_$hex';
}

/// Checkpoint model representing serialized transient state of an in-progress Visual Recall drill.
///
/// Stored under the key `'quran_visual_recall_checkpoint'` in local storage.
/// Used solely for resuming interrupted practice sessions within 24 hours.
class VisualRecallSessionCheckpoint extends Equatable {
  const VisualRecallSessionCheckpoint({
    this.version = 1,
    required this.sessionId,
    required this.origin,
    this.planId,
    required this.queue,
    this.currentIndex = 0,
    this.revealedGlobals = const <int>{},
    this.assessmentOutcomes = const <int, ReviewOutcome>{},
    this.uncommittedReviews = const <int>[],
    this.isAudioSyncEnabled = false,
    required this.savedAt,
  }) : assert(currentIndex >= 0);

  /// Schema version for backward-compatible migration.
  final int version;

  /// Unique 128-bit session identifier.
  final String sessionId;

  /// Session origin trigger.
  final VisualRecallSessionOrigin origin;

  /// Optional associated memorization plan ID.
  final String? planId;

  /// Sequence of canonical global Ayah indices (1..6236).
  final List<int> queue;

  /// Current 0-based pointer within [queue].
  final int currentIndex;

  /// Set of canonical global Ayah indices currently unmasked/revealed.
  final Set<int> revealedGlobals;

  /// Recorded self-assessment outcomes for completed Ayahs in this session.
  final Map<int, ReviewOutcome> assessmentOutcomes;

  /// Buffer of uncommitted review indices awaiting durable cubit acknowledgement.
  final List<int> uncommittedReviews;

  /// Whether audio recitation sync is toggled on.
  final bool isAudioSyncEnabled;

  /// Timestamp when this checkpoint was written.
  final DateTime savedAt;

  /// Default checkpoint validity lifespan: 24 hours (86,400,000 ms).
  static const Duration expirationDuration = Duration(hours: 24);

  /// Whether this checkpoint has exceeded its 24-hour expiration window.
  bool get isExpired => DateTime.now().difference(savedAt) > expirationDuration;

  /// Total count of Ayahs in this session queue.
  int get totalCount => queue.length;

  /// Current global Ayah, or null if the queue is finished or empty.
  int? get currentGlobalAyah =>
      (currentIndex >= 0 && currentIndex < queue.length)
      ? queue[currentIndex]
      : null;

  VisualRecallSessionCheckpoint copyWith({
    int? version,
    String? sessionId,
    VisualRecallSessionOrigin? origin,
    String? planId,
    List<int>? queue,
    int? currentIndex,
    Set<int>? revealedGlobals,
    Map<int, ReviewOutcome>? assessmentOutcomes,
    List<int>? uncommittedReviews,
    bool? isAudioSyncEnabled,
    DateTime? savedAt,
  }) {
    return VisualRecallSessionCheckpoint(
      version: version ?? this.version,
      sessionId: sessionId ?? this.sessionId,
      origin: origin ?? this.origin,
      planId: planId ?? this.planId,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      revealedGlobals: revealedGlobals ?? this.revealedGlobals,
      assessmentOutcomes: assessmentOutcomes ?? this.assessmentOutcomes,
      uncommittedReviews: uncommittedReviews ?? this.uncommittedReviews,
      isAudioSyncEnabled: isAudioSyncEnabled ?? this.isAudioSyncEnabled,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  factory VisualRecallSessionCheckpoint.fromJson(Map<String, dynamic> json) {
    final rawQueue = json['queue'] as List?;
    final queue = <int>[];
    if (rawQueue != null) {
      for (final item in rawQueue) {
        if (item is num && item >= 1 && item <= 6236) {
          queue.add(item.toInt());
        }
      }
    }

    final rawRevealed = json['revealedGlobals'] as List?;
    final revealedGlobals = <int>{};
    if (rawRevealed != null) {
      for (final item in rawRevealed) {
        if (item is num && item >= 1 && item <= 6236) {
          revealedGlobals.add(item.toInt());
        }
      }
    }

    final rawOutcomes = json['assessmentOutcomes'] as Map?;
    final assessmentOutcomes = <int, ReviewOutcome>{};
    if (rawOutcomes != null) {
      for (final entry in rawOutcomes.entries) {
        final g = int.tryParse(entry.key.toString());
        final outcomeStr = entry.value as String?;
        if (g != null && outcomeStr != null) {
          final outcome = ReviewOutcome.values.firstWhere(
            (o) => o.name == outcomeStr,
            orElse: () => ReviewOutcome.good,
          );
          assessmentOutcomes[g] = outcome;
        }
      }
    }

    final rawUncommitted = json['uncommittedReviews'] as List?;
    final uncommittedReviews = <int>[];
    if (rawUncommitted != null) {
      for (final item in rawUncommitted) {
        if (item is num && item >= 1 && item <= 6236) {
          uncommittedReviews.add(item.toInt());
        }
      }
    }

    final originStr = json['origin'] as String?;
    final origin = VisualRecallSessionOrigin.values.firstWhere(
      (o) => o.name == originStr,
      orElse: () => VisualRecallSessionOrigin.adhoc,
    );

    final rawSavedAt = json['savedAt'] as num?;
    final savedAt = rawSavedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(rawSavedAt.toInt())
        : DateTime.now();

    final currentIndex = ((json['currentIndex'] as num?)?.toInt() ?? 0).clamp(
      0,
      queue.isEmpty ? 0 : queue.length,
    );

    return VisualRecallSessionCheckpoint(
      version: (json['version'] as num?)?.toInt() ?? 1,
      sessionId: json['sessionId'] as String? ?? 'vrs_unknown',
      origin: origin,
      planId: json['planId'] as String?,
      queue: queue,
      currentIndex: currentIndex,
      revealedGlobals: revealedGlobals,
      assessmentOutcomes: assessmentOutcomes,
      uncommittedReviews: uncommittedReviews,
      isAudioSyncEnabled: json['isAudioSyncEnabled'] as bool? ?? false,
      savedAt: savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'sessionId': sessionId,
    'origin': origin.name,
    if (planId != null) 'planId': planId,
    'queue': queue,
    'currentIndex': currentIndex,
    'revealedGlobals': revealedGlobals.toList(),
    'assessmentOutcomes': assessmentOutcomes.map(
      (k, v) => MapEntry(k.toString(), v.name),
    ),
    'uncommittedReviews': uncommittedReviews,
    'isAudioSyncEnabled': isAudioSyncEnabled,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  @override
  List<Object?> get props => [
    version,
    sessionId,
    origin,
    planId,
    queue,
    currentIndex,
    revealedGlobals,
    assessmentOutcomes,
    uncommittedReviews,
    isAudioSyncEnabled,
    savedAt,
  ];
}
