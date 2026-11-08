import AVFoundation
import Flutter
import UIKit

/// Uses the same bundled NeMo CTC model and PCM channel as Android. Audio never
/// leaves memory. Model loading/decoding are serialized away from the UI thread.
final class OfflineRecitationPlugin: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let decoder = DispatchQueue(label: "mishkat.recitation.decoder", qos: .userInitiated)
  private let lifetime = OfflineRecitationLifetime()
  // Owned exclusively by `decoder`.
  private var recognizer: MishkatOfflineRecognizer?
  private var clients = Set<String>()
  // Owned exclusively by the main queue.
  private var sink: FlutterEventSink?
  private var capture: OfflineMicrophoneCapture?
  private var sessionSnapshot: OfflineAudioSessionSnapshot?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(
      name: "com.dakomn.mishkatapp/offline_recitation", binaryMessenger: messenger)
    events = FlutterEventChannel(
      name: "com.dakomn.mishkatapp/offline_recitation/audio", binaryMessenger: messenger)
    super.init()
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "disposed", message: "Recognition engine disposed", details: nil))
        return
      }
      self.handle(call, result: result)
    }
    observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
      self?.interruptCapture()
    }
    observe(UIApplication.willTerminateNotification) { [weak self] _ in
      self?.dispose()
    }
    observe(AVAudioSession.interruptionNotification) { [weak self] notification in
      guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        AVAudioSession.InterruptionType(rawValue: raw) == .began
      else { return }
      self?.interruptCapture()
    }
    observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
      guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
        AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
      else { return }
      self?.interruptCapture()
    }
    observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
      self?.interruptCapture()
    }
    observe(.AVAudioEngineConfigurationChange) { [weak self] notification in
      guard let self = self, let capture = self.capture,
        let engine = notification.object as? AVAudioEngine, engine === capture.engine
      else { return }
      let format = engine.inputNode.outputFormat(forBus: 0)
      if !engine.isRunning || format.sampleRate != capture.inputFormat.sampleRate
        || format.channelCount != capture.inputFormat.channelCount
      {
        self.interruptCapture()
      }
    }
  }

  private func observe(
    _ name: Notification.Name, handler: @escaping (Notification) -> Void
  ) {
    observers.append(NotificationCenter.default.addObserver(
      forName: name, object: nil, queue: .main, using: handler))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard lifetime.isOpen else {
      result(FlutterError(code: "disposed", message: "Recognition engine disposed", details: nil))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "hasPermission":
      result(hasPermission)
    case "initialize":
      let client = arguments["clientId"] as? String ?? "default"
      decoder.async { [self] in
        guard lifetime.isOpen else { return replyDisposed(result) }
        do {
          if recognizer == nil {
            guard let root = Bundle.main.resourceURL else {
              throw OfflineRecitationError("Bundled recitation assets unavailable")
            }
            recognizer = try MishkatOfflineRecognizer(
              modelPath: root.appendingPathComponent("asr/model.int8.onnx").path,
              tokensPath: root.appendingPathComponent("asr/tokens.txt").path)
          }
          guard lifetime.isOpen else {
            recognizer = nil
            return replyDisposed(result)
          }
          clients.insert(client)
          reply(result, true)
        } catch {
          reply(result, FlutterError(code: "model_unavailable",
            message: "Cannot load the bundled recitation model", details: nil))
        }
      }
    case "start":
      guard let session = arguments["sessionId"] as? String, !session.isEmpty else {
        result(FlutterError(code: "audio_start", message: "Missing session", details: nil))
        return
      }
      do {
        try startCapture(session: session)
        reply(result, true)
      } catch {
        reply(result, FlutterError(code: hasPermission ? "audio_start" : "permission_denied",
          message: error.localizedDescription, details: nil))
      }
    case "stop":
      stopCapture(expectedSession: arguments["sessionId"] as? String)
      // PCM posted by capture.stop() is already ahead of this result on main.
      // Dart can now flush VAD without dropping the final spoken consonant.
      reply(result, nil)
    case "transcribe":
      guard let typed = arguments["pcm"] as? FlutterStandardTypedData,
        !typed.data.isEmpty, typed.data.count <= 16000 * 2 * 15, typed.data.count.isMultiple(of: 2)
      else {
        result(FlutterError(code: "invalid_audio",
          message: "Expected nonempty mono PCM16 audio of at most 15 seconds", details: nil))
        return
      }
      let pcm = typed.data
      decoder.async { [self] in
        guard lifetime.isOpen else { return replyDisposed(result) }
        do {
          guard let recognizer = recognizer else {
            throw OfflineRecitationError("Model not loaded")
          }
          let text = try recognizer.transcribePCM16(pcm)
          reply(result, text)
        } catch {
          reply(result, FlutterError(code: "decode_failed",
            message: "Cannot decode the recitation audio", details: nil))
        }
      }
    case "release":
      let client = arguments["clientId"] as? String ?? "default"
      decoder.async { [self] in
        clients.remove(client)
        if clients.isEmpty { recognizer = nil }
        reply(result, nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var hasPermission: Bool {
    AVAudioSession.sharedInstance().recordPermission == .granted
  }

  private func startCapture(session id: String) throws {
    if capture?.sessionID == id { return }
    guard capture == nil else { throw OfflineRecitationError("Microphone already in use") }
    guard hasPermission else { throw OfflineRecitationError("Microphone permission required") }
    guard sink != nil else { throw OfflineRecitationError("Audio listener is not attached") }
    guard UIApplication.shared.applicationState != .background else {
      throw OfflineRecitationError("Recitation requires the app in the foreground")
    }
    let audioSession = AVAudioSession.sharedInstance()
    let snapshot = OfflineAudioSessionSnapshot(session: audioSession)
    sessionSnapshot = snapshot
    do {
      try audioSession.setCategory(.playAndRecord, mode: .measurement,
        options: OfflineAudioSessionSnapshot.captureOptions)
      // Preserve the shared session's sample-rate and I/O preferences. The
      // converter handles the actual built-in/Bluetooth hardware rate.
      // UIKit feedback is otherwise suppressed while recording. This optional
      // setting must never prevent microphone capture if the device rejects it.
      try? audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
      try audioSession.setActive(true)
      let microphone = try OfflineMicrophoneCapture(sessionID: id,
        onAudio: { [weak self] pcm, level in
          self?.emit(["type": "audio", "sessionId": id,
            "pcm": FlutterStandardTypedData(bytes: pcm), "level": level])
        }, onError: { [weak self] in
          DispatchQueue.main.async {
            guard let self = self, self.lifetime.isOpen else { return }
            if self.capture?.sessionID == id { self.stopCapture(expectedSession: id) }
            // A flush failure can arrive after capture was cleared. Deliver it
            // before the queued stop reply; Dart filters old session IDs.
            self.sink?(["type": "error", "sessionId": id])
          }
        })
      do {
        try microphone.start()
      } catch {
        microphone.stop()
        throw error
      }
      // Configuration-change notifications during prepare/start belong to
      // setup; only a fully running capture can be interrupted by them.
      capture = microphone
    } catch {
      capture?.stop()
      capture = nil
      snapshot.restoreIfOwned(session: audioSession)
      sessionSnapshot = nil
      throw error
    }
  }

  private func stopCapture(expectedSession: String?) {
    guard let microphone = capture else { return }
    if let expected = expectedSession, expected != microphone.sessionID { return }
    microphone.stop()
    capture = nil
    sessionSnapshot?.restoreIfOwned(session: AVAudioSession.sharedInstance())
    sessionSnapshot = nil
  }

  private func interruptCapture() {
    guard let id = capture?.sessionID else { return }
    stopCapture(expectedSession: id)
    emit(["type": "interrupted", "sessionId": id])
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.lifetime.isOpen else { return }
      // Old events keep their original session id. Dart ignores stale sessions;
      // valid trailing PCM must remain deliverable after native capture stops.
      self.sink?(event)
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func replyDisposed(_ result: @escaping FlutterResult) {
    reply(result, FlutterError(code: "disposed", message: "Recognition engine disposed", details: nil))
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    stopCapture(expectedSession: nil)
    return nil
  }

  func dispose() {
    guard lifetime.close() else { return }
    stopCapture(expectedSession: nil)
    sink = nil
    methods.setMethodCallHandler(nil)
    events.setStreamHandler(nil)
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    decoder.async { [self] in
      clients.removeAll()
      recognizer = nil
    }
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
  }
}

private struct OfflineRecitationError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

/// A small lock protects lifetime checks shared with the decoder worker.
private final class OfflineRecitationLifetime {
  private let lock = NSLock()
  private var open = true
  var isOpen: Bool {
    lock.lock()
    defer { lock.unlock() }
    return open
  }
  func close() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard open else { return false }
    open = false
    return true
  }
}

struct OfflineAudioSessionSnapshot {
  static let captureOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]
  let category: AVAudioSession.Category
  let mode: AVAudioSession.Mode
  let options: AVAudioSession.CategoryOptions
  let allowsHapticsDuringRecording: Bool

  init(session: AVAudioSession) {
    category = session.category
    mode = session.mode
    options = session.categoryOptions
    allowsHapticsDuringRecording = session.allowHapticsAndSystemSoundsDuringRecording
  }

  func restoreIfOwned(session: AVAudioSession) {
    // Another feature may have claimed the shared audio session meanwhile.
    // Never deactivate or overwrite the other feature's configuration.
    guard session.category == .playAndRecord, session.mode == .measurement,
      session.categoryOptions == Self.captureOptions
    else { return }
    if session.allowHapticsAndSystemSoundsDuringRecording {
      try? session.setAllowHapticsAndSystemSoundsDuringRecording(allowsHapticsDuringRecording)
    }
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    try? session.setCategory(category, mode: mode, options: options)
  }
}

/// The tap never hands AVAudioEngine-owned memory to another thread. A lock
/// makes closing the input gate and queuing copied buffers atomic, so stop can
/// drain exactly the captured audio before its method-channel response.
private final class OfflineMicrophoneCapture {
  let sessionID: String
  let engine = AVAudioEngine()
  let inputFormat: AVAudioFormat
  private let converter: OfflinePCMConverter
  private let queue = DispatchQueue(label: "mishkat.recitation.pcm", qos: .userInitiated)
  private let gate = NSLock()
  private var accepting = true
  private var installedTap = false
  private var failed = false // Only used on `queue`.
  private let onAudio: (Data, Double) -> Void
  private let onError: () -> Void

  init(sessionID: String, onAudio: @escaping (Data, Double) -> Void,
    onError: @escaping () -> Void) throws
  {
    self.sessionID = sessionID
    self.onAudio = onAudio
    self.onError = onError
    inputFormat = engine.inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw OfflineRecitationError("Microphone input format unavailable")
    }
    converter = try OfflinePCMConverter(inputFormat: inputFormat)
  }

  func start() throws {
    let frames = AVAudioFrameCount(max(256, min(8192, Int(inputFormat.sampleRate / 10))))
    engine.inputNode.installTap(onBus: 0, bufferSize: frames, format: inputFormat) {
      [weak self] buffer, _ in
      self?.enqueue(buffer)
    }
    installedTap = true
    engine.prepare()
    try engine.start()
    guard engine.isRunning else { throw OfflineRecitationError("Microphone did not start") }
  }

  private func enqueue(_ buffer: AVAudioPCMBuffer) {
    guard let copy = OfflinePCMConverter.copy(buffer) else {
      onError()
      return
    }
    gate.lock()
    defer { gate.unlock() }
    guard accepting else { return }
    queue.async { [self] in
      guard !failed else { return }
      do {
        for output in try converter.append(copy) { onAudio(output.pcm, output.level) }
      } catch {
        failed = true
        onError()
      }
    }
  }

  func stop() {
    gate.lock()
    accepting = false
    gate.unlock()
    if installedTap {
      engine.inputNode.removeTap(onBus: 0)
      installedTap = false
    }
    engine.stop()
    queue.sync {
      guard !failed else { return }
      do {
        for output in try converter.finish() { onAudio(output.pcm, output.level) }
      } catch {
        failed = true
        onError()
      }
    }
  }
}

/// This converter is also exercised with generated buffers by native tests.
/// Each instance belongs to one capture and one serial queue.
final class OfflinePCMConverter {
  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat
  private var finished = false

  init(inputFormat: AVAudioFormat) throws {
    guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,
      sampleRate: 16000, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: inputFormat, to: output)
    else { throw OfflineRecitationError("16 kHz microphone conversion unavailable") }
    outputFormat = output
    self.converter = converter
    self.converter.primeMethod = .none
  }

  func append(_ input: AVAudioPCMBuffer) throws -> [OfflinePCM16Encoder.Output] {
    guard !finished else { return [] }
    return try convert(input: input, finishing: false)
  }

  func finish() throws -> [OfflinePCM16Encoder.Output] {
    guard !finished else { return [] }
    finished = true
    return try convert(input: nil, finishing: true)
  }

  private func convert(input: AVAudioPCMBuffer?, finishing: Bool) throws
    -> [OfflinePCM16Encoder.Output]
  {
    let ratio = 16000 / converter.inputFormat.sampleRate
    let capacity = AVAudioFrameCount(max(1024, Int(ceil(Double(input?.frameLength ?? 0) * ratio)) + 64))
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      throw OfflineRecitationError("Cannot allocate converted audio")
    }
    var outputs: [OfflinePCM16Encoder.Output] = []
    var suppliedInput = false
    // A bounded drain handles the converter's retained filter tail without
    // making stop wait on a malformed device/converter indefinitely.
    for _ in 0..<12 {
      output.frameLength = 0
      var error: NSError?
      let status = converter.convert(to: output, error: &error) { _, inputStatus in
        if let input = input, !suppliedInput {
          suppliedInput = true
          inputStatus.pointee = .haveData
          return input
        }
        inputStatus.pointee = finishing ? .endOfStream : .noDataNow
        return nil
      }
      if status == .error || error != nil {
        if let error = error { throw error }
        throw OfflineRecitationError("Cannot convert microphone audio")
      }
      if output.frameLength > 0, let samples = output.floatChannelData?[0] {
        outputs.append(OfflinePCM16Encoder.encode(UnsafeBufferPointer(
          start: samples, count: Int(output.frameLength))))
      }
      if status != .haveData || output.frameLength == 0 { return outputs }
    }
    throw OfflineRecitationError("Microphone converter did not finish")
  }

  static func copy(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength)
    else { return nil }
    copy.frameLength = input.frameLength
    let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
    let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    guard source.count == destination.count else { return nil }
    for index in 0..<source.count {
      guard let from = source[index].mData, let to = destination[index].mData,
        source[index].mDataByteSize <= destination[index].mDataByteSize
      else { return nil }
      memcpy(to, from, Int(source[index].mDataByteSize))
      destination[index].mDataByteSize = source[index].mDataByteSize
    }
    return copy
  }
}

enum OfflinePCM16Encoder {
  struct Output {
    let pcm: Data
    let level: Double
  }

  static func encode(_ samples: UnsafeBufferPointer<Float>) -> Output {
    var pcm = Data(count: samples.count * 2)
    var energy = 0.0
    pcm.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
      for (index, sample) in samples.enumerated() {
        let finite = sample.isFinite ? sample : 0
        let scaled = Int32(max(-32768, min(32767, Double(finite) * 32768)))
        let value = Int16(scaled)
        let bits = UInt16(bitPattern: value)
        bytes[index * 2] = UInt8(bits & 0xff)
        bytes[index * 2 + 1] = UInt8(bits >> 8)
        energy += Double(value) * Double(value)
      }
    }
    let rms = samples.isEmpty ? 0 : sqrt(energy / Double(samples.count))
    let decibels = rms > 0 ? 20 * log10(rms / 32768) : -60
    return Output(pcm: pcm, level: max(0, min(1, (decibels + 60) / 60)))
  }
}
