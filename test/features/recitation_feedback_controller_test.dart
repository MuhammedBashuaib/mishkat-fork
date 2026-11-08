import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/oral_recitation_models.dart';
import 'package:mishkat_app/features/quran/data/models/recitation_feedback_event.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_oral_recitation_state.dart';
import 'package:mishkat_app/features/quran/presentation/services/recitation_feedback_controller.dart';
import 'package:mishkat_app/features/quran/presentation/services/recitation_pause_diagnostics.dart';
import 'package:mishkat_app/features/quran/presentation/services/speech_recognition_service.dart';
import 'package:mishkat_app/features/settings/data/models/app_settings.dart';

class _Speech extends MockSpeechRecognitionService
    implements RecitationPauseDiagnostics {
  final quiet = StreamController<bool>.broadcast(sync: true);
  bool active = true;
  bool atPause = false;
  @override
  bool get isListening => active;
  @override
  bool get isQuietForFeedback => active && atPause;
  @override
  Stream<bool> get feedbackQuietStream => quiet.stream;
  void pauseAudio(bool value) {
    atPause = value;
    quiet.add(value);
  }
}

class _Output implements RecitationFeedbackOutput {
  final sounds = <RecitationCue>[];
  final haptics = <RecitationCue>[];
  Completer<void>? loading;
  bool fail = false;
  int stops = 0;
  int disposals = 0;
  @override
  Future<void> prepare() async {
    await loading?.future;
    if (fail) throw PlatformException(code: 'unavailable');
  }

  @override
  Future<bool> play(RecitationCue cue) async {
    if (fail) throw PlatformException(code: 'unavailable');
    sounds.add(cue);
    return true;
  }

  @override
  Future<void> vibrate(RecitationCue cue) async => haptics.add(cue);
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async => disposals++;
}

class _Harness {
  _Harness(
    WidgetTester? tester, {
    RecitationFeedbackMode mode = RecitationFeedbackMode.sound,
  }) {
    controller = RecitationFeedbackController.bind(
      events: events.stream,
      states: states.stream,
      currentState: () => state,
      speechService: speech,
      output: output,
      mode: mode,
      nowMs: tester == null
          ? null
          : () => tester.binding.clock.now().millisecondsSinceEpoch,
    );
  }
  final speech = _Speech();
  final output = _Output();
  final events = StreamController<RecitationFeedbackEvent>.broadcast(
    sync: true,
  );
  final states = StreamController<QuranOralRecitationState>.broadcast(
    sync: true,
  );
  QuranOralRecitationState state = const QuranOralRecitationState(
    sessionId: 'session',
    lifecycle: OralRecitationLifecycle.listening,
    isOfflineEngine: true,
    unresolvedMistakeWordIndices: {1, 2, 3},
  );
  late RecitationFeedbackController controller;
  void update(QuranOralRecitationState value) {
    state = value;
    states.add(value);
  }

  void cue(RecitationCue cue, [Set<int> words = const {1}]) => events.add(
    RecitationFeedbackEvent(cue, sessionId: 'session', wordIndices: words),
  );
  Future<void> close() async {
    if (output.loading?.isCompleted == false) output.loading!.complete();
    await controller.dispose();
    await events.close();
    await states.close();
    await speech.quiet.close();
    await speech.dispose();
  }
}

void main() {
  testWidgets('ready cue expires quickly if reading has already begun', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.cue(RecitationCue.ready);
    await tester.pump(const Duration(milliseconds: 350));
    h.speech.pauseAudio(true);
    await tester.pump();
    expect(h.output.sounds, isEmpty);
  });

  testWidgets('live mistake waits for VAD pause without stopping capture', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.cue(RecitationCue.mistake);
    await tester.pump();
    expect(h.output.sounds, isEmpty);
    expect(h.speech.isListening, isTrue);
    h.speech.pauseAudio(true);
    await tester.pump();
    expect(h.output.sounds, [RecitationCue.mistake]);
    expect(h.speech.isListening, isTrue);
  });

  testWidgets('several errors before a breath coalesce to one recent cue', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.cue(RecitationCue.mistake, {1});
    h.cue(RecitationCue.mistake, {2});
    h.cue(RecitationCue.mistake, {3});
    h.speech.pauseAudio(true);
    await tester.pump();
    expect(h.output.sounds, [RecitationCue.mistake]);
    await tester.pump(const Duration(seconds: 3));
    expect(h.output.sounds, hasLength(1));
  });

  testWidgets('error cues have a 1200ms cooldown and no backlog', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.speech.pauseAudio(true);
    h.cue(RecitationCue.mistake, {1});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    h.cue(RecitationCue.mistake, {2});
    h.cue(RecitationCue.mistake, {3});
    await tester.pump(const Duration(milliseconds: 899));
    expect(h.output.sounds, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(h.output.sounds, [RecitationCue.mistake, RecitationCue.mistake]);
    await tester.pump(const Duration(seconds: 3));
    expect(h.output.sounds, hasLength(2));
  });

  testWidgets('stale errors expire instead of interrupting a later passage', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.cue(RecitationCue.mistake);
    await tester.pump(const Duration(milliseconds: 2200));
    h.speech.pauseAudio(true);
    await tester.pump();
    expect(h.output.sounds, isEmpty);
  });

  testWidgets('correcting an error cancels its waiting cue', (tester) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.cue(RecitationCue.mistake);
    h.update(h.state.copyWith(unresolvedMistakeWordIndices: {}));
    h.cue(RecitationCue.corrected);
    h.speech.pauseAudio(true);
    await tester.pump();
    expect(h.output.sounds, [RecitationCue.corrected]);
  });

  testWidgets('an unresolved mistake wins over positive and ready cues', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.cue(RecitationCue.mistake);
    h.cue(RecitationCue.corrected, {0});
    h.cue(RecitationCue.ready);
    h.speech.pauseAudio(true);
    await tester.pump();
    expect(h.output.sounds, [RecitationCue.mistake]);
  });

  testWidgets(
    'vibration mode responds without audio; silent mode has no feedback',
    (tester) async {
      final h = _Harness(tester, mode: RecitationFeedbackMode.vibration);
      addTearDown(h.close);
      h.cue(RecitationCue.mistake);
      await tester.pump();
      expect(h.output.haptics, [RecitationCue.mistake]);
      expect(h.output.sounds, isEmpty);
      h.controller.setMode(RecitationFeedbackMode.silent);
      h.cue(RecitationCue.mistake, {2});
      await tester.pump(const Duration(seconds: 3));
      expect(h.output.haptics, hasLength(1));
      expect(h.speech.isListening, isTrue);
    },
  );

  for (final reason in [
    'background',
    'silent',
    'new session',
    'draining',
    'dispose',
  ]) {
    test('$reason cancels a cue while the sound is loading', () async {
      final h = _Harness(null);
      addTearDown(h.close);
      await Future<void>.delayed(Duration.zero);
      h.output.loading = Completer<void>();
      h.speech.pauseAudio(true);
      h.cue(RecitationCue.mistake);
      await Future<void>.delayed(Duration.zero);
      switch (reason) {
        case 'background':
          h.controller.setForeground(false);
        case 'silent':
          h.controller.setMode(RecitationFeedbackMode.silent);
        case 'new session':
          h.update(h.state.copyWith(sessionId: 'new'));
        case 'draining':
          h.update(h.state.copyWith(isDraining: true));
        case 'dispose':
          await h.controller.dispose();
      }
      h.output.loading!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(h.output.sounds, isEmpty);
      expect(h.output.stops, greaterThan(0));
    });
  }

  test('preview is unavailable during capture and drain', () async {
    final h = _Harness(null);
    addTearDown(h.close);
    await h.controller.preview();
    expect(h.output.sounds, isEmpty);
    h.speech.active = false;
    h.update(
      h.state.copyWith(
        lifecycle: OralRecitationLifecycle.paused,
        isDraining: true,
      ),
    );
    await h.controller.preview();
    expect(h.output.sounds, isEmpty);
    h.update(h.state.copyWith(isDraining: false));
    await h.controller.preview();
    expect(h.output.sounds, [RecitationCue.mistake]);
  });

  testWidgets('completion only sounds once capture has fully stopped', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.update(h.state.copyWith(lifecycle: OralRecitationLifecycle.completed));
    h.cue(RecitationCue.complete);
    await tester.pump();
    expect(h.output.sounds, isEmpty);
    h.speech.active = false;
    h.cue(RecitationCue.complete);
    await tester.pump();
    expect(h.output.sounds, [RecitationCue.complete]);
  });

  testWidgets('output failures never change listening or alignment state', (
    tester,
  ) async {
    final h = _Harness(tester);
    addTearDown(h.close);
    h.output.fail = true;
    final before = h.state;
    h.speech.pauseAudio(true);
    h.cue(RecitationCue.mistake);
    await tester.pump();
    expect(h.state, same(before));
    expect(h.speech.isListening, isTrue);
    expect(tester.takeException(), isNull);
  });
}
