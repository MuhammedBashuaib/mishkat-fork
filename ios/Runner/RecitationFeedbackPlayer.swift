import AVFAudio
import Flutter
import UIKit

/// One short, original cue. Kept injectable so ownership and lifecycle behavior
/// can be tested without starting the shared audio session or microphone.
protocol RecitationFeedbackCuePlaying: AnyObject {
  func play() -> Bool
  func stop()
}

final class AVRecitationFeedbackCuePlayer: RecitationFeedbackCuePlaying {
  private let player: AVAudioPlayer

  init(url: URL) throws {
    player = try AVAudioPlayer(contentsOf: url)
    player.volume = 0.6
    player.numberOfLoops = 0
    // Do not call prepareToPlay: it implicitly activates the shared session.
    // Loading feedback must not affect Quran playback or microphone capture.
  }

  var isPlaying: Bool { player.isPlaying }

  func play() -> Bool {
    guard AVAudioSession.sharedInstance().outputVolume > 0 else { return false }
    player.currentTime = 0
    // Use the existing category, mode and route, including connected headphones.
    // iOS treats this as media audio; sound mode follows the media volume.
    return player.play()
  }

  func stop() {
    player.stop()
  }
}

enum RecitationFeedbackError: Error {
  case unavailable
  case inactive
  case preparationFailed
}

/// Main-thread confined state. There is no queued playback or asynchronous load
/// completion that could resurrect a disposed page or play an obsolete cue.
final class RecitationFeedbackPlayback {
  static let cueNames = ["ready", "mistake", "corrected", "paused", "complete"]

  private let makePlayer: (String) throws -> RecitationFeedbackCuePlaying
  private var players: [String: RecitationFeedbackCuePlaying] = [:]
  private var currentPlayer: RecitationFeedbackCuePlaying?
  private var retiredOwners = Set<String>()
  private var ownerId: String?
  private var foreground = false
  private var interrupted = false
  private var mediaServicesAvailable = true
  private var armed = false
  private var closed = false

  init(makePlayer: @escaping (String) throws -> RecitationFeedbackCuePlaying) {
    self.makePlayer = makePlayer
  }

  func prepare(ownerId caller: String) throws {
    guard !closed, !caller.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RecitationFeedbackError.unavailable
    }
    guard foreground, !interrupted, mediaServicesAvailable, !retiredOwners.contains(caller) else {
      throw RecitationFeedbackError.inactive
    }
    if ownerId != caller {
      if let previous = ownerId { retiredOwners.insert(previous) }
      releasePlayers()
      ownerId = caller
    }
    if players.count != Self.cueNames.count {
      do {
        // These five bundled PCM files are tiny. Atomic synchronous construction
        // prevents partial readiness and makes stop/dispose ordering explicit.
        var loaded: [String: RecitationFeedbackCuePlaying] = [:]
        for cue in Self.cueNames { loaded[cue] = try makePlayer(cue) }
        players = loaded
      } catch {
        releasePlayers()
        throw RecitationFeedbackError.preparationFailed
      }
    }
    armed = true
  }

  func play(ownerId caller: String, cue: String?) -> Bool {
    guard !closed, foreground, !interrupted, mediaServicesAvailable, armed, caller == ownerId,
      let cue = cue, let player = players[cue]
    else { return false }
    // At most one cue can be audible. A newer cue replaces, never queues behind,
    // an earlier cue; the Dart controller already applies relevance/cooldowns.
    stopCurrentPlayer()
    guard player.play() else { return false }
    currentPlayer = player
    return true
  }

  func stop(ownerId caller: String) {
    guard caller == ownerId else { return }
    disarm()
  }

  func dispose(ownerId caller: String) {
    guard !closed else { return }
    retiredOwners.insert(caller)
    guard caller == ownerId else { return }
    releasePlayers()
    ownerId = nil
  }

  func setForeground(_ active: Bool) {
    guard !closed else { return }
    // iOS may suspend the app after an interruption without ever sending its
    // ended notification. Returning to the foreground permits a fresh explicit
    // prepare, but cannot rearm or resume the interrupted cue by itself.
    if active && !foreground { interrupted = false }
    foreground = active
    if !active { disarm() }
  }

  func interruptionBegan() {
    guard !closed else { return }
    interrupted = true
    disarm()
  }

  func interruptionEnded() {
    guard !closed else { return }
    interrupted = false
    // Only a new explicit prepare may rearm; never resume an old cue.
  }

  func routeBecameUnavailable() {
    guard !closed else { return }
    disarm()
  }

  func mediaServicesLost() {
    guard !closed else { return }
    mediaServicesAvailable = false
    // These audio objects belong to the lost service and must not be reused.
    releasePlayers()
  }

  func mediaServicesReset() {
    guard !closed else { return }
    mediaServicesAvailable = true
    interrupted = false
    releasePlayers()
  }

  func shutdown() {
    guard !closed else { return }
    closed = true
    foreground = false
    releasePlayers()
    ownerId = nil
    retiredOwners.removeAll()
  }

  private func disarm() {
    armed = false
    stopCurrentPlayer()
  }

  private func stopCurrentPlayer() {
    currentPlayer?.stop()
    currentPlayer = nil
  }

  private func releasePlayers() {
    disarm()
    players.removeAll()
  }
}

/// A foreground-only effects channel with no AVAudioSession setter calls.
/// Preparation leaves the session untouched; explicit playback uses its current
/// configuration and route. AVAudioPlayer may activate that session when played.
final class RecitationFeedbackPlayer {
  private let channel: FlutterMethodChannel
  private let playback: RecitationFeedbackPlayback
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    playback = RecitationFeedbackPlayback { cue in
      try AVRecitationFeedbackCuePlayer(url: Self.bundledAssetURL(cue: cue))
    }
    channel = FlutterMethodChannel(
      name: "com.dakomn.mishkatapp/recitation_feedback", binaryMessenger: messenger)
    playback.setForeground(UIApplication.shared.applicationState == .active)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "feedback_unavailable", message: "Feedback unavailable", details: nil))
        return
      }
      self.handle(call, result: result)
    }
    observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
      self?.playback.setForeground(true)
    }
    observe(UIApplication.willResignActiveNotification) { [weak self] _ in
      self?.playback.setForeground(false)
    }
    observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
      self?.playback.setForeground(false)
    }
    observe(UIApplication.willTerminateNotification) { [weak self] _ in
      self?.dispose()
    }
    observe(AVAudioSession.interruptionNotification) { [weak self] notification in
      guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: raw)
      else { return }
      if type == .began { self?.playback.interruptionBegan() }
      else { self?.playback.interruptionEnded() }
    }
    observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
      guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
        AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
      else { return }
      // Do not move an in-progress headphone cue onto the loudspeaker.
      self?.playback.routeBecameUnavailable()
    }
    observe(AVAudioSession.mediaServicesWereLostNotification) { [weak self] _ in
      self?.playback.mediaServicesLost()
    }
    observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
      self?.playback.mediaServicesReset()
    }
  }

  static func bundledAssetURL(cue: String) throws -> URL {
    guard RecitationFeedbackPlayback.cueNames.contains(cue) else {
      throw RecitationFeedbackError.preparationFailed
    }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/audio/recitation_\(cue).wav")
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      throw RecitationFeedbackError.preparationFailed
    }
    return URL(fileURLWithPath: path)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let caller = arguments["ownerId"] as? String,
      !caller.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      if call.method == "play" { result(false) }
      else { result(FlutterError(code: "feedback_unavailable", message: "Feedback owner unavailable", details: nil)) }
      return
    }
    switch call.method {
    case "prepare":
      do {
        try playback.prepare(ownerId: caller)
        result(nil)
      } catch RecitationFeedbackError.inactive {
        result(FlutterError(code: "feedback_inactive", message: "Feedback owner is inactive", details: nil))
      } catch RecitationFeedbackError.unavailable {
        result(FlutterError(code: "feedback_unavailable", message: "Feedback unavailable", details: nil))
      } catch {
        result(FlutterError(code: "feedback_prepare_failed", message: "Cannot prepare feedback cues", details: nil))
      }
    case "play":
      result(playback.play(ownerId: caller, cue: arguments["cue"] as? String))
    case "stop":
      playback.stop(ownerId: caller)
      result(nil)
    case "dispose":
      playback.dispose(ownerId: caller)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func observe(_ name: Notification.Name, using block: @escaping (Notification) -> Void) {
    observers.append(NotificationCenter.default.addObserver(
      forName: name, object: nil, queue: .main, using: block))
  }

  func dispose() {
    channel.setMethodCallHandler(nil)
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    playback.shutdown()
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    playback.shutdown()
  }
}
