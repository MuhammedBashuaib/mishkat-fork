/// Optional VAD guidance for short UI sounds. This never pauses capture or
/// filters microphone samples; unsupported recognizers simply omit live sound.
abstract interface class RecitationPauseDiagnostics {
  bool get isQuietForFeedback;
  Stream<bool> get feedbackQuietStream;
}
