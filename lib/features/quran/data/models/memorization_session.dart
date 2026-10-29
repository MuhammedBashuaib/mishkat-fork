import 'package:equatable/equatable.dart';

/// The mode/purpose of an active practice session.
enum MemorizationSessionType {
  /// Regular forward memorization of new or current plan Ayahs.
  memorization,

  /// Targeted revision of flagged or older memorized Ayahs.
  revision;

  String get label => switch (this) {
    MemorizationSessionType.memorization => 'جلسة حفظ',
    MemorizationSessionType.revision => 'جلسة مراجعة',
  };
}

/// Represents the transient practice state of an active memorization or revision exercise.
class MemorizationSession extends Equatable {
  const MemorizationSession({
    String? id,
    this.planId,
    required this.queue,
    this.currentIndex = 0,
    this.isTextHidden = true,
    this.sessionType = MemorizationSessionType.memorization,
    this.completedCount = 0,
    // ignore: prefer_initializing_formals
  }) : _id = id,
       assert(currentIndex >= 0);

  final String? _id;

  /// Unique session identifier. Deterministic fallback ensures stable identity across restarts.
  String get id =>
      _id ??
      (planId != null
          ? 'sess_${planId}_${queue.isNotEmpty ? queue.first : 0}'
          : 'sess_adhoc_${queue.isNotEmpty ? queue.first : 0}');

  /// ID of the associated plan, if any.
  final String? planId;

  /// Ordered sequence of canonical [globalAyah] indices scheduled for this session.
  final List<int> queue;

  /// Current 0-based pointer within [queue].
  final int currentIndex;

  /// Whether Quranic text is currently hidden to prompt recall (Recall Mode).
  final bool isTextHidden;

  /// Whether this session is memorizing new Ayahs or revising past ones.
  final MemorizationSessionType sessionType;

  /// Count of Ayahs successfully addressed during this session.
  final int completedCount;

  /// Current canonical global Ayah, or null if the queue is empty or finished.
  int? get currentGlobalAyah =>
      (currentIndex >= 0 && currentIndex < queue.length)
      ? queue[currentIndex]
      : null;

  /// Total number of Ayahs in this session.
  int get totalCount => queue.length;

  /// Remaining count of Ayahs in this session including the current one.
  int get remainingCount => (totalCount - currentIndex).clamp(0, totalCount);

  /// Progress fraction (0.0 .. 1.0).
  double get progress =>
      totalCount == 0 ? 1.0 : (currentIndex / totalCount).clamp(0.0, 1.0);

  /// Whether all Ayahs in the session queue have been practiced.
  bool get isFinished => currentIndex >= queue.length;

  MemorizationSession copyWith({
    String? id,
    String? planId,
    List<int>? queue,
    int? currentIndex,
    bool? isTextHidden,
    MemorizationSessionType? sessionType,
    int? completedCount,
  }) => MemorizationSession(
    id: id ?? this.id,
    planId: planId ?? this.planId,
    queue: queue ?? this.queue,
    currentIndex: currentIndex ?? this.currentIndex,
    isTextHidden: isTextHidden ?? this.isTextHidden,
    sessionType: sessionType ?? this.sessionType,
    completedCount: completedCount ?? this.completedCount,
  );

  factory MemorizationSession.fromJson(Map<String, dynamic> json) {
    final rawQueue = json['queue'] as List?;
    final queue = <int>[];
    if (rawQueue != null) {
      for (final item in rawQueue) {
        if (item is num && item >= 1 && item <= 6236) {
          queue.add(item.toInt());
        }
      }
    }

    final currentIndex = ((json['currentIndex'] as num?)?.toInt() ?? 0).clamp(
      0,
      queue.isEmpty ? 0 : queue.length,
    );

    final typeStr = json['sessionType'] as String?;
    final sessionType = MemorizationSessionType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => MemorizationSessionType.memorization,
    );

    return MemorizationSession(
      id: json['id'] as String?,
      planId: json['planId'] as String?,
      queue: queue,
      currentIndex: currentIndex,
      isTextHidden: json['isTextHidden'] as bool? ?? true,
      sessionType: sessionType,
      completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (planId != null) 'planId': planId,
    'queue': queue,
    'currentIndex': currentIndex,
    'isTextHidden': isTextHidden,
    'sessionType': sessionType.name,
    'completedCount': completedCount,
  };

  @override
  List<Object?> get props => [
    id,
    planId,
    queue,
    currentIndex,
    isTextHidden,
    sessionType,
    completedCount,
  ];
}
