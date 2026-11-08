/// Optional guidance only. These events never change alignment or scoring.
enum RecitationCue { ready, mistake, corrected, paused, complete }

class RecitationFeedbackEvent {
  const RecitationFeedbackEvent(
    this.cue, {
    required this.sessionId,
    this.wordIndices = const {},
  });

  final RecitationCue cue;
  final String sessionId;
  final Set<int> wordIndices;
}
