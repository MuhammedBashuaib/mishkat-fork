import AVFoundation
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  private func recognizer() throws -> MishkatOfflineRecognizer {
    let root = try XCTUnwrap(Bundle.main.resourceURL)
    return try MishkatOfflineRecognizer(
      modelPath: root.appendingPathComponent("asr/model.int8.onnx").path,
      tokensPath: root.appendingPathComponent("asr/tokens.txt").path)
  }

  func testBundledModelLoadsAndExactDigitalSilenceProducesNoWords() throws {
    let engine = try recognizer()
    let text = try engine.transcribePCM16(Data(count: 16000 * 2 * 2))
    XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    // Exact digital silence is rejected before inference, without changing
    // the speech-energy threshold in the production Dart segmenter.
    XCTAssertEqual(try engine.transcribePCM16(Data(count: 16000 * 2)), "")
  }

  func testDecoderRejectsMalformedPCM() throws {
    let engine = try recognizer()
    for pcm in [Data(), Data([1]), Data(count: 16000 * 2 * 15 + 2)] {
      XCTAssertThrowsError(try engine.transcribePCM16(pcm)) { error in
        XCTAssertEqual((error as NSError).domain, "MishkatOfflineRecognizer")
        XCTAssertEqual((error as NSError).code, 3)
      }
    }
  }

  func testIncompleteModelFailsWithoutNativeAbort() {
    XCTAssertThrowsError(try MishkatOfflineRecognizer(
      modelPath: "/nonexistent/model.onnx", tokensPath: "/nonexistent/tokens.txt")) { error in
      XCTAssertEqual((error as NSError).code, 1)
    }
  }

  func testPCMEncodingClipsAndUsesLittleEndian() {
    let samples: [Float] = [-2, -1, -0.5, 0, 0.5, 1, 2, .nan, .infinity]
    let result = samples.withUnsafeBufferPointer(OfflinePCM16Encoder.encode)
    XCTAssertEqual(Array(result.pcm), [
      0, 128, 0, 128, 0, 192, 0, 0, 0, 64, 255, 127, 255, 127, 0, 0, 0, 0,
    ])
    XCTAssertTrue(result.level.isFinite)
    XCTAssertGreaterThan(result.level, 0)
    XCTAssertLessThanOrEqual(result.level, 1)
    let silence = Array(repeating: Float(0), count: 1600)
      .withUnsafeBufferPointer(OfflinePCM16Encoder.encode)
    XCTAssertEqual(silence.level, 0)
    XCTAssertEqual(silence.pcm, Data(count: 3200))
  }

  func testHardwareRateConversionAndStopTailPreserveDuration() throws {
    for sampleRate in [44100.0, 48000.0] {
      let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate, channels: 2, interleaved: false))
      let converter = try OfflinePCMConverter(inputFormat: format)
      var combined = Data()
      let frames = AVAudioFrameCount(sampleRate / 10)
      for part in 0..<10 {
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        input.frameLength = frames
        let channels = try XCTUnwrap(input.floatChannelData)
        for index in 0..<Int(frames) {
          let time = Double(part * Int(frames) + index) / sampleRate
          let sample = Float(sin(2 * .pi * 440 * time) * 0.25)
          channels[0][index] = sample
          channels[1][index] = sample
        }
        for output in try converter.append(input) { combined.append(output.pcm) }
      }
      for output in try converter.finish() { combined.append(output.pcm) }
      XCTAssertTrue(try converter.finish().isEmpty, "stop must be idempotent")
      // One second of hardware input becomes one second at the model's rate.
      // A few resampler-tail frames are allowed; an entire final buffer is not.
      XCTAssertEqual(Double(combined.count / 2), 16000, accuracy: 32)
      XCTAssertTrue(combined.contains { $0 != 0 })
    }
  }

  func testTapBufferCopyOwnsItsAudio() throws {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    input.frameLength = 4
    input.floatChannelData?[0][0] = 0.25
    let copy = try XCTUnwrap(OfflinePCMConverter.copy(input))
    input.floatChannelData?[0][0] = 0.75
    XCTAssertEqual(copy.floatChannelData?[0][0], 0.25)
  }

  func testKnownArabicSample() throws {
    guard let path = ProcessInfo.processInfo.environment["MISHKAT_ASR_SAMPLE_PCM"], !path.isEmpty else {
      throw XCTSkip("Set MISHKAT_ASR_SAMPLE_PCM to the public basmala PCM fixture")
    }
    let pcm = try Data(contentsOf: URL(fileURLWithPath: path))
    let engine = try recognizer()
    let text = try engine.transcribePCM16(pcm)
    // The fixture is a public recitation, not microphone/user data. Logging its
    // result here makes the native inference check independently reviewable.
    print("PUBLIC_BASMALA_ASR_RESULT: \(text)")
    XCTAssertEqual(text, "بسم الله الرحمن الرحيم")
    XCTAssertEqual(try engine.transcribePCM16(Data(count: 16000 * 2)), "")
    // The next utterance reuses the model, but must use a fresh decoder stream:
    // no words or audio from the prior result can carry over.
    XCTAssertEqual(try engine.transcribePCM16(pcm), text)
  }

}

/// Optional cues must never resurrect a retired page or take ownership of the
/// shared audio session. Spies make cancellation and error paths deterministic.
final class RecitationFeedbackTests: XCTestCase {
  private final class CueSpy: RecitationFeedbackCuePlaying {
    var playSucceeds = true
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private(set) var isPlaying = false

    func play() -> Bool {
      playCount += 1
      isPlaying = playSucceeds
      return playSucceeds
    }

    func stop() {
      stopCount += 1
      isPlaying = false
    }
  }

  private final class CueFactory {
    private(set) var made: [(name: String, player: CueSpy)] = []

    func make(_ cue: String) throws -> RecitationFeedbackCuePlaying {
      let player = CueSpy()
      made.append((cue, player))
      return player
    }

    func latest(_ cue: String) throws -> CueSpy {
      try XCTUnwrap(made.last { $0.name == cue }?.player)
    }
  }

  func testPreparationRequiresForegroundAndNeverPlays() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page-a"))
    XCTAssertTrue(factory.made.isEmpty)
    XCTAssertFalse(feedback.play(ownerId: "page-a", cue: "ready"))

    feedback.setForeground(true)
    for owner in ["", " \n "] {
      XCTAssertThrowsError(try feedback.prepare(ownerId: owner))
    }
    XCTAssertTrue(factory.made.isEmpty)
    try feedback.prepare(ownerId: "page-a")
    XCTAssertEqual(factory.made.map { $0.name }, RecitationFeedbackPlayback.cueNames)
    XCTAssertTrue(factory.made.allSatisfy { $0.player.playCount == 0 })
    XCTAssertFalse(feedback.play(ownerId: "another-page", cue: "ready"))
    XCTAssertTrue(feedback.play(ownerId: "page-a", cue: "ready"))
  }

  func testReplacingOwnerStopsOldSoundAndRejectsEveryStaleOperation() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "old-page")
    let oldCue = try factory.latest("ready")
    XCTAssertTrue(feedback.play(ownerId: "old-page", cue: "ready"))

    try feedback.prepare(ownerId: "new-page")
    let newCue = try factory.latest("ready")
    XCTAssertFalse(oldCue.isPlaying)
    XCTAssertFalse(oldCue === newCue)
    XCTAssertTrue(feedback.play(ownerId: "new-page", cue: "ready"))

    XCTAssertThrowsError(try feedback.prepare(ownerId: "old-page"))
    XCTAssertFalse(feedback.play(ownerId: "old-page", cue: "mistake"))
    feedback.stop(ownerId: "old-page")
    feedback.dispose(ownerId: "old-page")
    XCTAssertTrue(newCue.isPlaying, "Late callbacks from a replaced page cannot stop its successor")
    XCTAssertTrue(feedback.play(ownerId: "new-page", cue: "corrected"))
  }

  func testDisposalRetiresOwnerEvenWhenItsPrepareArrivesLate() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    feedback.dispose(ownerId: "disposed-before-prepare")
    XCTAssertThrowsError(try feedback.prepare(ownerId: "disposed-before-prepare"))
    XCTAssertTrue(factory.made.isEmpty)

    try feedback.prepare(ownerId: "current-page")
    XCTAssertTrue(feedback.play(ownerId: "current-page", cue: "complete"))
    let playing = try factory.latest("complete")
    feedback.dispose(ownerId: "current-page")
    XCTAssertFalse(playing.isPlaying)
    XCTAssertFalse(feedback.play(ownerId: "current-page", cue: "complete"))
    XCTAssertThrowsError(try feedback.prepare(ownerId: "current-page"))
    try feedback.prepare(ownerId: "next-page")
    XCTAssertTrue(feedback.play(ownerId: "next-page", cue: "ready"))
  }

  func testStopNeedsFreshPreparationAndNeverAutoplays() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "mistake"))
    let cue = try factory.latest("mistake")
    feedback.stop(ownerId: "page")
    feedback.stop(ownerId: "page")
    XCTAssertFalse(cue.isPlaying)
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "corrected"))

    let playsBeforePrepare = factory.made.reduce(0) { $0 + $1.player.playCount }
    try feedback.prepare(ownerId: "page")
    XCTAssertEqual(factory.made.reduce(0) { $0 + $1.player.playCount }, playsBeforePrepare)
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "corrected"))
  }

  func testBackgroundStopsSoundAndForegroundDoesNotResumeIt() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "mistake"))
    feedback.setForeground(false)
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page"))
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))

    feedback.setForeground(true)
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
  }

  func testInterruptionRequiresEndAndFreshPreparation() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "corrected"))
    feedback.interruptionBegan()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page"))
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))

    feedback.interruptionEnded()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
  }

  func testReturningFromBackgroundRecoversWhenInterruptionEndIsMissing() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "mistake"))
    feedback.interruptionBegan()
    feedback.setForeground(false)

    // iOS may suspend the app without ever delivering interruption-ended.
    feedback.setForeground(true)
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "mistake"))
    let playCount = factory.made.reduce(0) { $0 + $1.player.playCount }
    try feedback.prepare(ownerId: "page")
    XCTAssertEqual(factory.made.reduce(0) { $0 + $1.player.playCount }, playCount)
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
  }

  func testMediaServicesLossCannotRecoverFromForegroundOrInterruptionEndAlone() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "complete"))
    feedback.mediaServicesLost()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page"))
    feedback.setForeground(false)
    feedback.setForeground(true)
    feedback.interruptionEnded()
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page"))

    feedback.mediaServicesReset()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    try feedback.prepare(ownerId: "page")
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))

  }

  func testMediaServicesResetStopsAndDisarmsUntilFreshPreparation() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "complete"))
    feedback.mediaServicesReset()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
  }

  func testHeadphoneDisconnectionDisarmsInsteadOfMovingCueToSpeaker() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "mistake"))
    feedback.routeBecameUnavailable()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "mistake"))
    try feedback.prepare(ownerId: "page")
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))

    feedback.interruptionBegan()
    feedback.routeBecameUnavailable()
    feedback.setForeground(true) // Already foreground: this is not recovery.
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page"),
      "A route change during interruption cannot masquerade as a foreground return")
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    feedback.interruptionEnded()
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
  }

  func testUnknownCueCannotInterruptCurrentSoundOrEscapeAssetDirectory() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
    let ready = try factory.latest("ready")
    for invalid: String? in [nil, "", "unknown", "../tasbih_complete", "Ready"] {
      XCTAssertFalse(feedback.play(ownerId: "page", cue: invalid))
      XCTAssertTrue(ready.isPlaying)
    }
    XCTAssertThrowsError(try RecitationFeedbackPlayer.bundledAssetURL(cue: "../tasbih_complete"))
  }

  func testMissingAssetReleasesPartialPreparationAndAllowsRetry() throws {
    final class WeakCue {
      weak var player: CueSpy?
      init(_ player: CueSpy) { self.player = player }
    }
    var fail = true
    var created: [WeakCue] = []
    let feedback = RecitationFeedbackPlayback { cue in
      if fail && cue == "corrected" {
        throw NSError(domain: "FeedbackTestMissingAsset", code: 1)
      }
      let player = CueSpy()
      created.append(WeakCue(player))
      return player
    }
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    XCTAssertThrowsError(try feedback.prepare(ownerId: "page"))
    XCTAssertFalse(created.isEmpty, "Exercise failure after some assets have loaded")
    XCTAssertTrue(created.allSatisfy { $0.player == nil }, "Partial construction must release every player")
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))

    fail = false
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
  }

  func testFailedOptionalPlaybackDoesNotPoisonFollowingCue() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
    let ready = try factory.latest("ready")
    try factory.latest("mistake").playSucceeds = false
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "mistake"))
    XCTAssertFalse(ready.isPlaying)
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "corrected"))
    let corrected = try factory.latest("corrected")
    XCTAssertTrue(corrected.isPlaying)
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "complete"))
    XCTAssertFalse(corrected.isPlaying, "There can never be two overlapping cues")
  }

  func testShutdownPermanentlyStopsPlayback() throws {
    let factory = CueFactory()
    let feedback = RecitationFeedbackPlayback(makePlayer: factory.make)
    feedback.setForeground(true)
    try feedback.prepare(ownerId: "page")
    XCTAssertTrue(feedback.play(ownerId: "page", cue: "ready"))
    feedback.shutdown()
    feedback.shutdown()
    feedback.setForeground(true)
    feedback.interruptionEnded()
    XCTAssertFalse(factory.made.contains { $0.player.isPlaying })
    XCTAssertThrowsError(try feedback.prepare(ownerId: "new-page"))
    XCTAssertFalse(feedback.play(ownerId: "page", cue: "ready"))
  }

  private struct SessionState: Equatable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
    let preferredSampleRate: Double
    let preferredIOBufferDuration: TimeInterval
    let allowsHaptics: Bool

    init(_ session: AVAudioSession) {
      category = session.category
      mode = session.mode
      options = session.categoryOptions
      preferredSampleRate = session.preferredSampleRate
      preferredIOBufferDuration = session.preferredIOBufferDuration
      allowsHaptics = session.allowHapticsAndSystemSoundsDuringRecording
    }

    func restore(_ session: AVAudioSession) {
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      try? session.setCategory(category, mode: mode, options: options)
      try? session.setAllowHapticsAndSystemSoundsDuringRecording(allowsHaptics)
    }
  }

  func testBundledCuesPlayAndStopWithoutChangingQuranAudioSession() throws {
    try exerciseBundledCues(category: .playback, mode: .spokenAudio, options: .mixWithOthers)
  }

  func testBundledCuesPlayAndStopWithoutChangingCaptureAudioSession() throws {
    try exerciseBundledCues(category: .playAndRecord, mode: .measurement,
      options: OfflineAudioSessionSnapshot.captureOptions)
  }

  private func waitForHostFlutterUI() throws {
    func flutterController(in root: UIViewController) -> FlutterViewController? {
      if let flutter = root as? FlutterViewController { return flutter }
      if let presented = root.presentedViewController,
        let flutter = flutterController(in: presented) { return flutter }
      for child in root.children {
        if let flutter = flutterController(in: child) { return flutter }
      }
      return nil
    }
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      guard UIApplication.shared.applicationState == .active else { return false }
      return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }.compactMap { $0.rootViewController }
        .contains { flutterController(in: $0)?.isDisplayingFlutterUI == true }
    }, object: nil)
    // The XCTest host starts before Dart main finishes its async initialization.
    // Real audio assertions must not race that bootstrap or its first UI frame.
    let result = XCTWaiter.wait(for: [ready], timeout: 15)
    XCTAssertEqual(result, .completed, "Flutter test host did not finish startup")
    guard result == .completed else {
      throw NSError(domain: "FeedbackTestHostStartup", code: 1)
    }
  }

  private func exerciseBundledCues(
    category: AVAudioSession.Category, mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions
  ) throws {
    try waitForHostFlutterUI()
    let session = AVAudioSession.sharedInstance()
    let original = SessionState(session)
    defer { original.restore(session) }
    try session.setCategory(category, mode: mode, options: options)
    if category == .playAndRecord {
      try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
      // Production capture activates the session before its first ready cue.
      // This does not install an input tap or read microphone samples.
      print("FEEDBACK_CAPTURE_SESSION: activating")
      try session.setActive(true)
      print("FEEDBACK_CAPTURE_SESSION: active")
    }
    let expected = SessionState(session)

    // Output-only synthetic offline rendering: no input node, microphone tap,
    // user audio or permission request. This verifies that effects preserve a
    // running engine, not physical microphone quality or acoustic echo safety.
    let engine = AVAudioEngine()
    let source = AVAudioPlayerNode()
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let sourceBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    sourceBuffer.frameLength = sourceBuffer.frameCapacity
    let samples = try XCTUnwrap(sourceBuffer.floatChannelData)[0]
    for index in 0..<Int(sourceBuffer.frameLength) { samples[index] = 0.1 }
    // Configure manual rendering before touching the mixer/output graph so
    // AVAudioEngine never configures an input/output hardware render path.
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    let rendered = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
    defer {
      source.stop()
      engine.stop()
      engine.disableManualRenderingMode()
    }
    source.scheduleBuffer(sourceBuffer, at: nil, options: .loops, completionHandler: nil)
    try engine.start()
    source.play()

    func renderNextFrames() throws {
      let previousTime = engine.manualRenderingSampleTime
      XCTAssertEqual(try engine.renderOffline(256, to: rendered), .success)
      XCTAssertTrue(engine.isRunning)
      XCTAssertEqual(engine.manualRenderingSampleTime, previousTime + 256)
    }

    let mediaVolume = session.outputVolume
    print("FEEDBACK_NATIVE_PLAYBACK: category=\(category.rawValue) outputVolume=\(mediaVolume) audible=\(mediaVolume > 0)")
    var players: [String: AVRecitationFeedbackCuePlayer] = [:]
    let feedback = RecitationFeedbackPlayback { cue in
      let player = try AVRecitationFeedbackCuePlayer(
        url: RecitationFeedbackPlayer.bundledAssetURL(cue: cue))
      players[cue] = player
      return player
    }
    defer { feedback.shutdown() }
    feedback.setForeground(true)
    try renderNextFrames()
    for cue in RecitationFeedbackPlayback.cueNames {
      let url = try RecitationFeedbackPlayer.bundledAssetURL(cue: cue)
      let asset = try AVAudioFile(forReading: url)
      XCTAssertEqual(asset.processingFormat.sampleRate, 16000)
      XCTAssertEqual(asset.processingFormat.channelCount, 1)
      XCTAssertGreaterThan(asset.length, 0)
      XCTAssertLessThan(Double(asset.length) / asset.processingFormat.sampleRate, 0.22)

      try feedback.prepare(ownerId: "bundled-cue-test")
      let player = try XCTUnwrap(players[cue])
      XCTAssertFalse(player.isPlaying, "Loading \(cue) must not autoplay")
      XCTAssertEqual(SessionState(session), expected, "Loading \(cue) changed the shared session")
      try renderNextFrames()
      let audible = session.outputVolume > 0
      XCTAssertEqual(feedback.play(ownerId: "bundled-cue-test", cue: cue), audible,
        "Native playback failed for \(cue)")
      if audible { XCTAssertTrue(player.isPlaying) }
      XCTAssertEqual(SessionState(session), expected, "Playing \(cue) changed the shared session")
      try renderNextFrames()

      if audible {
        // Let the real audio finish instead of stopping before it can render.
        // A cue is at most 210 ms; the bounded allowance also covers scheduling
        // delay on a loaded simulator without allowing endless playback.
        let deadline = Date().addingTimeInterval(0.9)
        while player.isPlaying && Date() < deadline {
          RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
        XCTAssertFalse(player.isPlaying, "\(cue) did not finish naturally")
        XCTAssertEqual(SessionState(session), expected,
          "Completing \(cue) changed the shared session")
        try renderNextFrames()

        // Replaying a completed player must work; page teardown must be able
        // to stop that replay immediately, without deactivating shared audio.
        XCTAssertTrue(feedback.play(ownerId: "bundled-cue-test", cue: cue),
          "Cannot replay completed cue \(cue)")
        XCTAssertTrue(player.isPlaying)
      }
      feedback.stop(ownerId: "bundled-cue-test")
      XCTAssertFalse(player.isPlaying)
      XCTAssertEqual(SessionState(session), expected, "Stopping \(cue) changed the shared session")
      try renderNextFrames()
    }
  }

  func testCaptureRestoresBothPreviousHapticsSettings() throws {
    let session = AVAudioSession.sharedInstance()
    let original = SessionState(session)
    defer { original.restore(session) }
    for previous in [false, true] {
      try session.setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
      try session.setAllowHapticsAndSystemSoundsDuringRecording(previous)
      let expected = SessionState(session)
      let snapshot = OfflineAudioSessionSnapshot(session: session)
      try session.setCategory(.playAndRecord, mode: .measurement,
        options: OfflineAudioSessionSnapshot.captureOptions)
      try session.setAllowHapticsAndSystemSoundsDuringRecording(true)

      snapshot.restoreIfOwned(session: session)
      XCTAssertEqual(SessionState(session), expected,
        "Ending capture must restore the previous haptics preference: \(previous)")
    }
  }

  func testCaptureCannotRestoreOverAnotherFeaturesAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    let original = SessionState(session)
    defer { original.restore(session) }
    try session.setCategory(.ambient, mode: .default)
    try session.setAllowHapticsAndSystemSoundsDuringRecording(false)
    let snapshot = OfflineAudioSessionSnapshot(session: session)
    try session.setCategory(.playAndRecord, mode: .measurement,
      options: OfflineAudioSessionSnapshot.captureOptions)
    try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
    // Model another feature claiming the singleton before capture cleanup.
    try session.setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
    let otherFeature = SessionState(session)

    snapshot.restoreIfOwned(session: session)
    XCTAssertEqual(SessionState(session), otherFeature)
    XCTAssertTrue(session.allowHapticsAndSystemSoundsDuringRecording)
  }
}
