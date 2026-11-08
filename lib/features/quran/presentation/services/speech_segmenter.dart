import 'dart:math' as math;
import 'dart:typed_data';

/// A copy of real microphone audio, never an ASR prediction.
class SpeechSegment {
  const SpeechSegment(
    this.samples, {
    required this.forced,
    required this.revision,
  });

  final Int16List samples;
  final bool forced;

  /// Source utterance identity before a final segment advances the segmenter.
  /// Equal revisions alone do not imply equal audio: speech may have resumed.
  final int revision;
}

/// Tasmee's pause-aware segmentation, independent of platform and recognizer.
///
/// Small chunks are assembled into 30 ms frames. A short pre-roll preserves
/// initial consonants; a natural pause closes an utterance. Long uninterrupted
/// speech is cut at its quietest recent point rather than at an arbitrary word.
class SpeechSegmenter {
  SpeechSegmenter({
    this.sampleRate = 16000,
    this.frameMs = 30,
    this.silenceMs = 420,
    this.maxSegmentMs = 12000,
    this.forcedCutWindowMs = 2500,
    this.preRollMs = 300,
    this.postRollMs = 200,
    this.minVoicedMs = 300,
    this.speechRatio = 3.2,
    this.minSpeechRms = 30,
    this.minNoiseFloor = 6,
  });

  final int sampleRate;
  final int frameMs;
  final int silenceMs;
  final int maxSegmentMs;
  final int forcedCutWindowMs;
  final int preRollMs;
  final int postRollMs;
  final int minVoicedMs;
  final double speechRatio;
  final double minSpeechRms;
  final double minNoiseFloor;

  int get _frameLength => (sampleRate * frameMs / 1000).round();
  int get _preRollFrames => (preRollMs / frameMs).ceil();
  int get _postRollFrames => (postRollMs / frameMs).ceil();
  Int16List _pending = Int16List(0);
  List<Int16List> _pre = [];
  List<Int16List> _frames = [];
  List<double> _levels = [];
  List<bool> _voiced = [];
  bool _inSpeech = false;
  bool _hasHeardSpeech = false;
  int _quietFrames = 0;
  int _silence = 0;
  double _noiseFloor = -1;
  final List<double> _recentSpeechLevels = [];
  int _revision = 0;

  /// Identifies the buffered utterance; snapshots from older revisions expire.
  int get revision => _revision;

  /// A possible breath is in progress; a final segment will take priority.
  bool get hasPendingPause => _silence > 0;

  int get pendingPauseMs => _silence * frameMs;

  int get bufferedDurationMs => _frames.length * frameMs;

  /// A natural boundary or idle silence, never a forced cut through speech.
  /// Optional sounds wait here so they do not extend an unfinished utterance.
  bool get isAtQuietBoundary =>
      !_inSpeech && (!_hasHeardSpeech || _quietFrames * frameMs >= silenceMs);

  /// Copies the current audio without closing or consuming the utterance.
  SpeechSegment? snapshot() {
    if (!_inSpeech ||
        _voiced.where((value) => value).length * frameMs < minVoicedMs) {
      return null;
    }
    return SpeechSegment(
      _concatenate([..._frames, if (_pending.isNotEmpty) _pending]),
      forced: false,
      revision: _revision,
    );
  }

  /// Candidate length without copying PCM, or null before enough post-roll.
  /// Unprocessed partial frames are excluded, just as in [pauseSnapshot].
  int? get pauseSnapshotSampleCount {
    if (!_inSpeech ||
        _silence == 0 ||
        _silence < _postRollFrames ||
        _voiced.where((value) => value).length * frameMs < minVoicedMs) {
      return null;
    }
    return (_frames.length - _silence + _postRollFrames) * _frameLength;
  }

  /// Copies a possible ending as soon as its post-roll audio is available.
  ///
  /// This does not confirm a pause or consume audio. If the remaining frames
  /// stay quiet, the later natural final has exactly these samples. A caller
  /// may reuse a decode only after comparing both the final's revision and PCM;
  /// resumed speech within the same revision invalidates the earlier candidate.
  SpeechSegment? pauseSnapshot() {
    final sampleCount = pauseSnapshotSampleCount;
    if (sampleCount == null) return null;
    final end = sampleCount ~/ _frameLength;
    return SpeechSegment(
      _concatenate(_frames.sublist(0, end)),
      forced: false,
      revision: _revision,
    );
  }

  List<SpeechSegment> push(Int16List samples) {
    final input = _pending.isEmpty
        ? samples
        : (Int16List(_pending.length + samples.length)
            ..setAll(0, _pending)
            ..setAll(_pending.length, samples));
    final result = <SpeechSegment>[];
    var offset = 0;
    while (offset + _frameLength <= input.length) {
      final frame = Int16List.fromList(
        input.sublist(offset, offset + _frameLength),
      );
      offset += _frameLength;
      final segment = _processFrame(frame);
      if (segment != null) result.add(segment);
    }
    _pending = Int16List.fromList(input.sublist(offset));
    return result;
  }

  SpeechSegment? flush() {
    if (_pending.isNotEmpty) {
      final frame = Int16List(_frameLength)..setAll(0, _pending);
      _pending = Int16List(0);
      final closed = _processFrame(frame);
      if (closed != null) {
        // Padding may land exactly on a forced-cut boundary. Flush its retained
        // tail in the same result so stop never loses the end of that verse.
        final parts = [closed.samples, ..._frames];
        final joined = _concatenate(parts);
        reset();
        return SpeechSegment(
          joined,
          forced: closed.forced,
          revision: closed.revision,
        );
      }
    }
    if (!_inSpeech) return null;
    return _close(_frames.length, forced: false);
  }

  void reset() {
    _revision++;
    _pending = Int16List(0);
    _pre = [];
    _frames = [];
    _levels = [];
    _voiced = [];
    _inSpeech = false;
    _hasHeardSpeech = false;
    _quietFrames = 0;
    _silence = 0;
    _noiseFloor = -1;
    _recentSpeechLevels.clear();
  }

  SpeechSegment? _processFrame(Int16List frame) {
    final rms = frameRms(frame);
    // Start from the digital noise floor, not the first frame: a reader who
    // starts immediately must not have their first word classified as noise.
    if (_noiseFloor < 0) _noiseFloor = minNoiseFloor;
    if (rms < _noiseFloor) {
      _noiseFloor = _noiseFloor * .7 + rms * .3;
    } else if (rms < _threshold) {
      // Learning from voiced frames eventually treats a long connected verse
      // as background noise and drops its ending. Only learn quiet frames.
      _noiseFloor = _noiseFloor * .97 + rms * .03;
    }
    _noiseFloor = math.max(minNoiseFloor, _noiseFloor);
    // A phone microphone does not produce digital silence during a breath.
    // Recognize a sustained drop relative to the reader's recent voice too,
    // otherwise room noise above minSpeechRms keeps an utterance open forever.
    // The upper quartile ignores brief clicks, and quiet frames do not lower
    // the reference while a possible breath is being measured.
    final relativeThreshold = _relativeQuietThreshold;
    final voiced = rms >= math.max(_threshold, relativeThreshold);
    if (voiced) {
      _hasHeardSpeech = true;
      _quietFrames = 0;
    } else if (_quietFrames * frameMs < silenceMs) {
      _quietFrames++;
    }
    if (!_inSpeech) {
      if (!voiced) {
        _pre.add(frame);
        if (_pre.length > _preRollFrames) _pre.removeAt(0);
        return null;
      }
      _inSpeech = true;
      _frames = [..._pre];
      _levels = _pre.map(frameRms).toList();
      _voiced = List<bool>.filled(_pre.length, false, growable: true);
      _pre = [];
      _silence = 0;
    }
    _frames.add(frame);
    _levels.add(rms);
    _voiced.add(voiced);
    if (voiced) {
      _recentSpeechLevels.add(rms);
      final recentFrames = (1500 / frameMs).ceil();
      if (_recentSpeechLevels.length > recentFrames) {
        _recentSpeechLevels.removeAt(0);
      }
      _silence = 0;
    } else {
      _silence++;
    }
    if (_silence * frameMs >= silenceMs) {
      // Learn a nonzero background only after a complete, verified pause.
      // The relative threshold bounds this update below the recent voice,
      // so connected speech cannot gradually train itself into background.
      final quietLevels = _levels.sublist(_levels.length - _silence)..sort();
      final quietFloor = quietLevels[quietLevels.length ~/ 2];
      _noiseFloor = math.max(minNoiseFloor, quietFloor);
      final end = _frames.length - _silence + _postRollFrames;
      return _close(end.clamp(0, _frames.length), forced: false);
    }
    if (_frames.length * frameMs >= maxSegmentMs) {
      return _close(_quietestCut(), forced: true);
    }
    return null;
  }

  double get _threshold => math.max(minSpeechRms, _noiseFloor * speechRatio);

  double get _relativeQuietThreshold {
    if (_recentSpeechLevels.length * frameMs < minVoicedMs) return 0;
    final sorted = List<double>.of(_recentSpeechLevels)..sort();
    return sorted[((sorted.length - 1) * .75).floor()] * .18;
  }

  int _quietestCut() {
    final window = (forcedCutWindowMs / frameMs).ceil();
    var best = _frames.length;
    var lowest = double.infinity;
    for (
      var i = math.max(1, _frames.length - window);
      i < _frames.length;
      i++
    ) {
      final next = i + 1 < _levels.length ? _levels[i + 1] : _levels[i];
      final average = (_levels[i - 1] + _levels[i] + next) / 3;
      if (average < lowest) {
        lowest = average;
        best = i + 1;
      }
    }
    return best;
  }

  SpeechSegment? _close(int end, {required bool forced}) {
    final sourceRevision = _revision++;
    final head = _frames.sublist(0, end);
    final tail = _frames.sublist(end);
    // Track actual voiced classifications, not a retrospectively higher noise
    // threshold that could discard an otherwise valid quiet utterance.
    final voicedInHead = _voiced.take(end).where((value) => value).length;
    if (forced && tail.isNotEmpty) {
      _frames = tail;
      _levels = _levels.sublist(end);
      _voiced = _voiced.sublist(end);
      _recentSpeechLevels
        ..clear()
        ..addAll([
          for (var i = 0; i < _levels.length; i++)
            if (_voiced[i]) _levels[i],
        ]);
      final recentFrames = (1500 / frameMs).ceil();
      if (_recentSpeechLevels.length > recentFrames) {
        _recentSpeechLevels.removeRange(
          0,
          _recentSpeechLevels.length - recentFrames,
        );
      }
      _silence = 0;
    } else {
      _frames = [];
      _levels = [];
      _voiced = [];
      _recentSpeechLevels.clear();
      _inSpeech = false;
      _silence = 0;
      _pre = tail.skip(math.max(0, tail.length - _preRollFrames)).toList();
    }
    if (voicedInHead * frameMs < minVoicedMs) return null;
    return SpeechSegment(
      _concatenate(head),
      forced: forced,
      revision: sourceRevision,
    );
  }

  static Int16List _concatenate(List<Int16List> frames) {
    final joined = Int16List(
      frames.fold<int>(0, (n, frame) => n + frame.length),
    );
    var offset = 0;
    for (final frame in frames) {
      joined.setAll(offset, frame);
      offset += frame.length;
    }
    return joined;
  }

  static double frameRms(Int16List samples) {
    var squares = 0.0;
    for (final sample in samples) {
      squares += sample * sample;
    }
    return math.sqrt(squares / math.max(1, samples.length));
  }
}
