import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_segmenter.dart';

Int16List _audio(int milliseconds, int amplitude) => Int16List.fromList(
  List.generate(
    milliseconds * 16,
    (index) => index.isEven ? amplitude : -amplitude,
  ),
);

void main() {
  test('digital silence and brief clicks do not become recitation', () {
    final vad = SpeechSegmenter();
    expect(vad.push(_audio(5000, 0)), isEmpty);
    expect(vad.push(_audio(60, 2000)), isEmpty);
    expect(vad.push(_audio(500, 0)), isEmpty);
    expect(vad.flush(), isNull);
  });

  test('speech beginning on the first frame is retained', () {
    final vad = SpeechSegmenter();
    vad.push(_audio(900, 1000));
    final segments = vad.push(_audio(600, 0));
    expect(segments, hasLength(1));
    expect(segments.single.samples.first, 1000);
    expect(segments.single.forced, isFalse);
  });

  test('quiet speech above the noise floor remains eligible', () {
    final vad = SpeechSegmenter();
    vad.push(_audio(600, 0));
    vad.push(_audio(900, 45));
    final segments = vad.push(_audio(600, 0));
    expect(segments, hasLength(1));
    expect(segments.single.samples.any((sample) => sample == 45), isTrue);
  });

  test('chunk boundaries do not change the captured utterance', () {
    final contiguous = SpeechSegmenter();
    final fragmented = SpeechSegmenter();
    final input = Int16List.fromList([
      ..._audio(300, 0),
      ..._audio(1000, 900),
      ..._audio(600, 0),
    ]);
    final expected = contiguous.push(input).single;
    final actual = <SpeechSegment>[];
    for (var offset = 0; offset < input.length; offset += 377) {
      final end = (offset + 377).clamp(0, input.length);
      actual.addAll(
        fragmented.push(Int16List.fromList(input.sublist(offset, end))),
      );
    }
    expect(actual, hasLength(1));
    expect(actual.single.samples, expected.samples);
  });

  test('stop flush includes the final incomplete frame once', () {
    final vad = SpeechSegmenter();
    vad.push(_audio(1001, 1000));
    final last = vad.flush();
    expect(last, isNotNull);
    expect(last!.samples.where((sample) => sample != 0), hasLength(16016));
    expect(vad.flush(), isNull);
  });

  test('long uninterrupted recitation is bounded and preserves tail audio', () {
    final vad = SpeechSegmenter();
    final segments = vad.push(_audio(14000, 2000));
    final last = vad.flush();
    if (last != null) segments.add(last);
    expect(segments.length, greaterThanOrEqualTo(2));
    expect(segments.first.forced, isTrue);
    expect(
      segments.every((segment) => segment.samples.length <= 16000 * 12),
      isTrue,
    );
    expect(
      segments.fold<int>(
        0,
        (count, segment) =>
            count + segment.samples.where((sample) => sample != 0).length,
      ),
      14000 * 16,
    );
  });

  test('reset discards cancelled audio before a new session', () {
    final vad = SpeechSegmenter();
    vad.push(_audio(900, 1000));
    vad.reset();
    expect(vad.push(_audio(600, 0)), isEmpty);
    expect(vad.flush(), isNull);
  });

  test('stop exactly at forced-cut boundary retains the entire tail', () {
    final vad = SpeechSegmenter();
    final segments = vad.push(_audio(11999, 2000));
    expect(segments, isEmpty);
    final sourceRevision = vad.revision;
    final last = vad.flush();
    expect(last!.samples.where((value) => value != 0), hasLength(11999 * 16));
    expect(last.revision, sourceRevision);
    expect(vad.revision, greaterThan(sourceRevision));
    expect(vad.flush(), isNull);
  });

  for (final background in [31, 50, 100, 200]) {
    test('a breath over room noise at RMS $background closes before stop', () {
      final vad = SpeechSegmenter();
      final segments = <SpeechSegment>[
        ...vad.push(_audio(600, background)),
        ...vad.push(_audio(1800, 1600)),
        ...vad.push(_audio(900, background)),
      ];
      expect(segments, hasLength(1));
      expect(segments.single.forced, isFalse);
      expect(
        segments.single.samples.where((sample) => sample.abs() == 1600),
        hasLength(1800 * 16),
      );
      // Continuing background after the breath must not start another decode.
      expect(vad.push(_audio(900, background)), isEmpty);
      expect(vad.flush(), isNull);
    });
  }

  test('a breath is recognized with a changing room-noise level', () {
    final vad = SpeechSegmenter();
    final segments = <SpeechSegment>[
      ...vad.push(_audio(600, 80)),
      ...vad.push(_audio(1800, 1600)),
    ];
    for (var frame = 0; frame < 30; frame++) {
      segments.addAll(vad.push(_audio(30, 60 + (frame % 5) * 25)));
    }
    expect(segments, hasLength(1));
    expect(segments.single.forced, isFalse);
  });

  test(
    'a brief loud click does not turn quiet connected speech into noise',
    () {
      final vad = SpeechSegmenter();
      final segments = <SpeechSegment>[
        ...vad.push(_audio(60, 12000)),
        ...vad.push(_audio(1500, 45)),
        ...vad.push(_audio(60, 12000)),
        ...vad.push(_audio(1500, 45)),
      ];
      expect(segments, isEmpty);
      segments.addAll(vad.push(_audio(600, 0)));
      expect(segments, hasLength(1));
      expect(
        segments.single.samples.where((sample) => sample.abs() == 45),
        hasLength(3000 * 16),
      );
    },
  );

  test('snapshots preserve pending PCM and never consume or mutate audio', () {
    final vad = SpeechSegmenter();
    final initialRevision = vad.revision;
    expect(vad.snapshot(), isNull);
    vad.push(_audio(200, 1000));
    expect(vad.snapshot(), isNull);
    vad.push(_audio(801, 1000));
    final first = vad.snapshot()!;
    expect(first.samples, hasLength(1001 * 16));
    expect(first.revision, initialRevision);
    expect(vad.bufferedDurationMs, 990);
    expect(vad.revision, initialRevision);
    first.samples[0] = 999;
    expect(vad.snapshot()!.samples.first, 1000);
    vad.push(_audio(300, 1000));
    expect(first.samples, hasLength(1001 * 16));
    final finalSegment = vad.flush()!;
    expect(finalSegment.revision, initialRevision);
    expect(
      finalSegment.samples.where((value) => value != 0),
      hasLength(1301 * 16),
    );
    expect(vad.revision, greaterThan(initialRevision));
    expect(vad.snapshot(), isNull);
    final closedRevision = vad.revision;
    vad.reset();
    expect(vad.revision, greaterThan(closedRevision));
  });

  test('forced cuts and natural pauses expire old snapshot revisions', () {
    final vad = SpeechSegmenter();
    vad.push(_audio(1000, 1000));
    final beforeForcedCut = vad.revision;
    expect(vad.push(_audio(11000, 1000)), hasLength(1));
    expect(vad.revision, greaterThan(beforeForcedCut));
    final beforePause = vad.revision;
    expect(vad.push(_audio(600, 0)), hasLength(1));
    expect(vad.revision, greaterThan(beforePause));
  });

  test(
    'pause candidate waits for full post-roll and matches the natural final',
    () {
      final vad = SpeechSegmenter();
      vad.push(_audio(900, 1000));
      final revision = vad.revision;
      expect(vad.pauseSnapshot(), isNull);
      expect(vad.pauseSnapshotSampleCount, isNull);
      expect(vad.pendingPauseMs, 0);
      expect(vad.push(_audio(180, 0)), isEmpty);
      expect(vad.pendingPauseMs, 180);
      expect(vad.pauseSnapshot(), isNull);
      expect(vad.pauseSnapshotSampleCount, isNull);
      expect(vad.push(_audio(30, 0)), isEmpty);
      final candidate = vad.pauseSnapshot()!;
      expect(vad.pendingPauseMs, 210);
      expect(candidate.samples, hasLength(1110 * 16));
      expect(vad.pauseSnapshotSampleCount, candidate.samples.length);
      expect(candidate.revision, revision);
      expect(candidate.forced, isFalse);
      expect(
        vad.revision,
        revision,
        reason: 'A candidate never closes the utterance.',
      );
      expect(vad.push(_audio(180, 0)), isEmpty);
      expect(vad.pauseSnapshot()!.samples, candidate.samples);
      expect(vad.pauseSnapshotSampleCount, candidate.samples.length);
      final finalSegment = vad.push(_audio(30, 0)).single;
      expect(finalSegment.samples, candidate.samples);
      expect(finalSegment.revision, candidate.revision);
      expect(vad.revision, greaterThan(revision));
      expect(vad.pendingPauseMs, 0);
      expect(vad.pauseSnapshot(), isNull);
      expect(vad.pauseSnapshotSampleCount, isNull);
    },
  );

  test('nonzero room-noise pause candidate preserves exact final PCM', () {
    final vad = SpeechSegmenter();
    vad.push(_audio(600, 100));
    vad.push(_audio(1800, 1600));
    expect(vad.push(_audio(210, 100)), isEmpty);
    final candidate = vad.pauseSnapshot()!;
    expect(
      candidate.samples.where((sample) => sample.abs() == 1600),
      hasLength(1800 * 16),
    );
    // Mutating the exported audio must not mutate the segmenter's buffer.
    final originalFirst = candidate.samples.first;
    candidate.samples[0] = 999;
    final unchanged = vad.pauseSnapshot()!;
    expect(unchanged.samples.first, originalFirst);
    final finalSegment = vad.push(_audio(210, 100)).single;
    expect(finalSegment.samples, unchanged.samples);
    expect(finalSegment.revision, unchanged.revision);
  });

  test(
    'resumed speech invalidates the candidate even within the same revision',
    () {
      final vad = SpeechSegmenter();
      vad.push(_audio(900, 1000));
      vad.push(_audio(210, 0));
      final first = vad.pauseSnapshot()!;
      expect(vad.push(_audio(600, 800)), isEmpty);
      expect(vad.pendingPauseMs, 0);
      expect(vad.pauseSnapshot(), isNull);
      expect(vad.revision, first.revision);
      expect(vad.push(_audio(210, 0)), isEmpty);
      final second = vad.pauseSnapshot()!;
      expect(second.revision, first.revision);
      expect(second.samples.length, greaterThan(first.samples.length));
      final finalSegment = vad.push(_audio(210, 0)).single;
      expect(finalSegment.samples, second.samples);
      expect(finalSegment.samples, isNot(equals(first.samples)));
      expect(
        finalSegment.samples.where((sample) => sample.abs() == 1000),
        hasLength(900 * 16),
      );
      expect(
        finalSegment.samples.where((sample) => sample.abs() == 800),
        hasLength(600 * 16),
      );
    },
  );

  test('pause candidates exclude unprocessed PCM and insufficient voice', () {
    final click = SpeechSegmenter();
    click.push(_audio(120, 1000));
    click.push(_audio(210, 0));
    expect(click.pauseSnapshot(), isNull);
    expect(click.pauseSnapshotSampleCount, isNull);
    expect(click.push(_audio(210, 0)), isEmpty);

    final vad = SpeechSegmenter();
    vad.push(_audio(900, 1000));
    vad.push(_audio(210, 0));
    final candidate = vad.pauseSnapshot()!;
    vad.push(_audio(10, 0));
    expect(vad.pauseSnapshot()!.samples, candidate.samples);
    expect(vad.pauseSnapshotSampleCount, candidate.samples.length);
    expect(vad.snapshot()!.samples.length, candidate.samples.length + 160);
    // Stop must retain that last partial frame, rather than reuse shorter PCM.
    final flushed = vad.flush()!;
    expect(flushed.revision, candidate.revision);
    expect(flushed.samples.length, candidate.samples.length + 480);
    expect(flushed.samples, isNot(equals(candidate.samples)));
  });

  test(
    'flush may reuse a pause candidate only when its audio is identical',
    () {
      final vad = SpeechSegmenter();
      vad.push(_audio(900, 1000));
      vad.push(_audio(210, 0));
      final candidate = vad.pauseSnapshot()!;
      final flushed = vad.flush()!;
      expect(flushed.samples, candidate.samples);
      expect(flushed.revision, candidate.revision);
      expect(vad.revision, greaterThan(candidate.revision));
    },
  );

  test('forced cuts give the retained tail a distinct source revision', () {
    final vad = SpeechSegmenter(maxSegmentMs: 600, forcedCutWindowMs: 120);
    vad.push(_audio(450, 1000));
    final first = vad.snapshot()!;
    final cut = vad.push(_audio(150, 1000)).single;
    expect(cut.forced, isTrue);
    expect(cut.revision, first.revision);
    expect(vad.revision, greaterThan(cut.revision));
    vad.push(_audio(300, 1000));
    final tail = vad.snapshot()!;
    expect(tail.revision, vad.revision);
    expect(tail.revision, isNot(cut.revision));
    final flushed = vad.flush()!;
    expect(flushed.revision, tail.revision);
    expect(flushed.samples, tail.samples);
    expect(cut.samples.length + flushed.samples.length, 900 * 16);
  });
}
