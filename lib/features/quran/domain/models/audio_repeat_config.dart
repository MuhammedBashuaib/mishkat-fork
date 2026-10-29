import 'package:equatable/equatable.dart';

/// The repeat and looping mode for Quran audio playback.
enum AudioRepeatMode {
  /// Regular sequential playback with no automatic repetition.
  none,

  /// Repeat a single Ayah N times (e.g., Ayah 255 × 3).
  singleAyah,

  /// Loop an entire range A→B as a full cycle M times (e.g., 255 → 257 × 3).
  rangeLoop,

  /// Repeat each individual Ayah inside the range N times before advancing,
  /// with the full range looping M times (e.g., 255 × 3, 256 × 3, 257 × 3).
  perAyahRange;

  /// Arabic descriptive label.
  String get label => switch (this) {
    AudioRepeatMode.none => 'بدون تكرار',
    AudioRepeatMode.singleAyah => 'تكرار الآية',
    AudioRepeatMode.rangeLoop => 'تطويف المقطع كحلقة',
    AudioRepeatMode.perAyahRange => 'تكرار كل آية في المقطع',
  };
}

/// Immutable configuration model defining repetition, range boundaries,
/// iteration counts, and delay intervals between recitations.
class AudioRepeatConfig extends Equatable {
  const AudioRepeatConfig({
    this.mode = AudioRepeatMode.none,
    this.startGlobalAyah = 1,
    this.endGlobalAyah = 1,
    this.ayahRepeatCount = 1,
    this.rangeRepeatCount = 1,
    this.delaySeconds = 0,
  }) : assert(
         startGlobalAyah >= 1 && startGlobalAyah <= 6236,
         'startGlobalAyah must be between 1 and 6236',
       ),
       assert(
         endGlobalAyah >= 1 && endGlobalAyah <= 6236,
         'endGlobalAyah must be between 1 and 6236',
       ),
       assert(
         startGlobalAyah <= endGlobalAyah,
         'startGlobalAyah must be <= endGlobalAyah',
       ),
       assert(
         ayahRepeatCount == infinite || ayahRepeatCount > 0,
         'ayahRepeatCount must be infinite (-1) or positive',
       ),
       assert(
         rangeRepeatCount == infinite || rangeRepeatCount > 0,
         'rangeRepeatCount must be infinite (-1) or positive',
       ),
       assert(
         delaySeconds >= 0 && delaySeconds <= 30,
         'delaySeconds must be between 0 and 30',
       );

  /// Sentinel constant representing indefinite / infinite repetitions.
  static const int infinite = -1;

  /// Default configuration: no repetition, 1 iteration, 0s delay.
  static const AudioRepeatConfig defaultConfig = AudioRepeatConfig();

  /// Default configuration for memorization drill sessions: 3 repeats, 3s delay.
  static const AudioRepeatConfig defaultMemorizationConfig = AudioRepeatConfig(
    mode: AudioRepeatMode.singleAyah,
    ayahRepeatCount: 3,
    delaySeconds: 3,
  );

  /// Factory constructor for single Ayah repetition.
  factory AudioRepeatConfig.singleAyah({
    int startAyah = 1,
    int targetRepetitions = 1,
    int delaySeconds = 0,
  }) => AudioRepeatConfig(
    mode: AudioRepeatMode.singleAyah,
    startGlobalAyah: startAyah,
    endGlobalAyah: startAyah,
    ayahRepeatCount: targetRepetitions,
    rangeRepeatCount: 1,
    delaySeconds: delaySeconds,
  );

  /// Factory constructor for range looping.
  factory AudioRepeatConfig.rangeLoop({
    required int startAyah,
    required int endAyah,
    int targetRepetitions = 1,
    int delaySeconds = 0,
  }) => AudioRepeatConfig(
    mode: AudioRepeatMode.rangeLoop,
    startGlobalAyah: startAyah,
    endGlobalAyah: endAyah,
    ayahRepeatCount: 1,
    rangeRepeatCount: targetRepetitions,
    delaySeconds: delaySeconds,
  );

  /// Factory constructor for per-Ayah repetition inside a range.
  factory AudioRepeatConfig.perAyahRange({
    required int startAyah,
    required int endAyah,
    int targetRepetitions = 1,
    int rangeRepetitions = 1,
    int delaySeconds = 0,
  }) => AudioRepeatConfig(
    mode: AudioRepeatMode.perAyahRange,
    startGlobalAyah: startAyah,
    endGlobalAyah: endAyah,
    ayahRepeatCount: targetRepetitions,
    rangeRepeatCount: rangeRepetitions,
    delaySeconds: delaySeconds,
  );

  /// Factory constructor for infinite repetition.
  factory AudioRepeatConfig.infiniteRepeat({
    AudioRepeatMode mode = AudioRepeatMode.singleAyah,
    int startAyah = 1,
    int? endAyah,
    int delaySeconds = 0,
  }) {
    final effectiveEnd = endAyah ?? startAyah;
    return AudioRepeatConfig(
      mode: mode,
      startGlobalAyah: startAyah,
      endGlobalAyah: effectiveEnd >= startAyah ? effectiveEnd : startAyah,
      ayahRepeatCount: infinite,
      rangeRepeatCount: mode == AudioRepeatMode.rangeLoop ? infinite : 1,
      delaySeconds: delaySeconds,
    );
  }

  final AudioRepeatMode mode;
  final int startGlobalAyah;
  final int endGlobalAyah;

  int get startAyah => startGlobalAyah;
  int get endAyah => endGlobalAyah;
  int get targetRepetitions =>
      mode == AudioRepeatMode.rangeLoop ? rangeRepeatCount : ayahRepeatCount;

  /// Repetitions per Ayah: 1, 2, 3, 5, 7, 10, or [infinite] (-1).
  final int ayahRepeatCount;

  /// Repetitions for the entire range cycle: 1, 2, 3, 5, 7, 10, or [infinite] (-1).
  final int rangeRepeatCount;

  /// Interval pause in seconds after recitation finishes before the next repetition starts.
  final int delaySeconds;

  bool get isInfiniteAyah => ayahRepeatCount == infinite;
  bool get isInfiniteRange => rangeRepeatCount == infinite;
  bool get isInfinite => isInfiniteAyah || isInfiniteRange;
  bool get hasDelay => delaySeconds > 0;
  bool get isRange =>
      mode == AudioRepeatMode.rangeLoop || mode == AudioRepeatMode.perAyahRange;

  /// Ordered list of all global Ayah indices included in this configuration.
  List<int> get rangeQueue {
    if (!isRange) return [startGlobalAyah];
    return List<int>.generate(
      endGlobalAyah - startGlobalAyah + 1,
      (i) => startGlobalAyah + i,
    );
  }

  AudioRepeatConfig copyWith({
    AudioRepeatMode? mode,
    int? startGlobalAyah,
    int? endGlobalAyah,
    int? ayahRepeatCount,
    int? rangeRepeatCount,
    int? delaySeconds,
  }) {
    return AudioRepeatConfig(
      mode: mode ?? this.mode,
      startGlobalAyah: startGlobalAyah ?? this.startGlobalAyah,
      endGlobalAyah: endGlobalAyah ?? this.endGlobalAyah,
      ayahRepeatCount: ayahRepeatCount ?? this.ayahRepeatCount,
      rangeRepeatCount: rangeRepeatCount ?? this.rangeRepeatCount,
      delaySeconds: delaySeconds ?? this.delaySeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'startGlobalAyah': startGlobalAyah,
    'endGlobalAyah': endGlobalAyah,
    'ayahRepeatCount': ayahRepeatCount,
    'rangeRepeatCount': rangeRepeatCount,
    'delaySeconds': delaySeconds,
  };

  factory AudioRepeatConfig.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    final mode = AudioRepeatMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => AudioRepeatMode.none,
    );

    final start = (json['startGlobalAyah'] as num?)?.toInt() ?? 1;
    final end = (json['endGlobalAyah'] as num?)?.toInt() ?? start;
    final safeStart = start.clamp(1, 6236);
    final safeEnd = end.clamp(safeStart, 6236);

    final ayahCount = (json['ayahRepeatCount'] as num?)?.toInt() ?? 1;
    final rangeCount = (json['rangeRepeatCount'] as num?)?.toInt() ?? 1;
    final delay = (json['delaySeconds'] as num?)?.toInt() ?? 0;

    return AudioRepeatConfig(
      mode: mode,
      startGlobalAyah: safeStart,
      endGlobalAyah: safeEnd,
      ayahRepeatCount: ayahCount == infinite
          ? infinite
          : ayahCount.clamp(1, 100),
      rangeRepeatCount: rangeCount == infinite
          ? infinite
          : rangeCount.clamp(1, 100),
      delaySeconds: delay.clamp(0, 30),
    );
  }

  @override
  List<Object?> get props => [
    mode,
    startGlobalAyah,
    endGlobalAyah,
    ayahRepeatCount,
    rangeRepeatCount,
    delaySeconds,
  ];
}

/// Lifecycle status for repeat execution.
enum AudioRepeatStatus {
  /// Engine is inactive, ready to be configured.
  idle,

  /// Ayah audio is currently reciting.
  playing,

  /// Recitation of the Ayah completed; waiting during the Tardid silence interval.
  delaying,

  /// Playback or delay is paused.
  paused,

  /// All configured repetitions and ranges have finished.
  completed,
}

/// Snapshot of the live state of repetition progress.
class AudioRepeatState extends Equatable {
  const AudioRepeatState({
    this.status = AudioRepeatStatus.idle,
    this.config = AudioRepeatConfig.defaultConfig,
    this.currentAyah = 1,
    this.currentAyahRepeat = 1,
    this.currentRangeCycle = 1,
    this.remainingDelaySeconds = 0,
    this.queueIndex = 0,
    this.queue = const [1],
  });

  final AudioRepeatStatus status;
  final AudioRepeatConfig config;

  /// The global Ayah currently active (1..6236).
  final int currentAyah;

  /// Current 1-based iteration of the active Ayah.
  final int currentAyahRepeat;

  /// Current 1-based cycle of the range loop.
  final int currentRangeCycle;

  /// Remaining seconds in the current delay/tardid countdown.
  final int remainingDelaySeconds;

  /// Index inside [queue].
  final int queueIndex;

  /// The active queue of global Ayahs for this sequence.
  final List<int> queue;

  bool get isIdle => status == AudioRepeatStatus.idle;
  bool get isPlaying => status == AudioRepeatStatus.playing;
  bool get isDelaying => status == AudioRepeatStatus.delaying;
  bool get isPaused => status == AudioRepeatStatus.paused;
  bool get isCompleted => status == AudioRepeatStatus.completed;
  bool get isActive => isPlaying || isDelaying || isPaused;

  /// Current 1-based repetition index (Ayah repeat or Range cycle depending on mode).
  int get currentRepetition => config.mode == AudioRepeatMode.rangeLoop
      ? currentRangeCycle
      : currentAyahRepeat;

  /// Total repeats expected for the current Ayah (-1 if infinite).
  int get targetAyahRepeats {
    if (config.mode == AudioRepeatMode.rangeLoop) {
      // In range loop mode, each Ayah is recited once per range cycle.
      return 1;
    }
    return config.ayahRepeatCount;
  }

  /// Total cycles expected for the range (-1 if infinite).
  int get targetRangeCycles => config.rangeRepeatCount;

  /// Effective target repetitions (-1 if infinite).
  int get targetRepetitions => config.mode == AudioRepeatMode.rangeLoop
      ? targetRangeCycles
      : targetAyahRepeats;

  /// Informative, concise Arabic status description.
  String get statusText {
    if (isDelaying) {
      return 'ترديد: $remainingDelaySeconds ث';
    }
    if (targetRepetitions == AudioRepeatConfig.infinite) {
      return 'تكرار مستمر ($currentRepetition)';
    }
    return 'تكرار $currentRepetition من $targetRepetitions';
  }

  AudioRepeatState copyWith({
    AudioRepeatStatus? status,
    AudioRepeatConfig? config,
    int? currentAyah,
    int? currentAyahRepeat,
    int? currentRangeCycle,
    int? remainingDelaySeconds,
    int? queueIndex,
    List<int>? queue,
  }) {
    return AudioRepeatState(
      status: status ?? this.status,
      config: config ?? this.config,
      currentAyah: currentAyah ?? this.currentAyah,
      currentAyahRepeat: currentAyahRepeat ?? this.currentAyahRepeat,
      currentRangeCycle: currentRangeCycle ?? this.currentRangeCycle,
      remainingDelaySeconds:
          remainingDelaySeconds ?? this.remainingDelaySeconds,
      queueIndex: queueIndex ?? this.queueIndex,
      queue: queue ?? this.queue,
    );
  }

  @override
  List<Object?> get props => [
    status,
    config,
    currentAyah,
    currentAyahRepeat,
    currentRangeCycle,
    remainingDelaySeconds,
    queueIndex,
    queue,
  ];
}
