import AVFAudio
import Flutter
import Speech
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var speechSettingsChannel: FlutterMethodChannel?
  private var tasbihSoundChannel: FlutterMethodChannel?
  private var tasbihSoundPlayer: AVAudioPlayer?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MishkatSpeechModels") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.dakomn.mishkatapp/speech_settings",
      binaryMessenger: registrar.messenger()
    )
    let soundChannel = FlutterMethodChannel(
      name: "com.dakomn.mishkatapp/tasbih_sound",
      binaryMessenger: registrar.messenger()
    )
    tasbihSoundChannel = soundChannel
    soundChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(FlutterMethodNotImplemented) }
      do {
        switch call.method {
        case "prepare":
          try self.prepareTasbihSound()
          result(nil)
        case "play":
          try self.prepareTasbihSound()
          let session = AVAudioSession.sharedInstance()
          // Keep an existing Quran playback session intact.
          if session.category != .playback {
            try session.setCategory(.playback, options: [.mixWithOthers])
          }
          try session.setActive(true)
          self.tasbihSoundPlayer?.currentTime = 0
          guard self.tasbihSoundPlayer?.play() == true else {
            result(FlutterError(code: "tasbih_sound_error", message: "Cannot start chime", details: nil))
            return
          }
          result(nil)
        case "dispose":
          self.tasbihSoundPlayer?.stop()
          self.tasbihSoundPlayer = nil
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "tasbih_sound_error", message: error.localizedDescription, details: nil))
      }
    }
    speechSettingsChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getArabicModelStatus", "downloadArabicModel":
        // The legacy recognizer used by speech_to_text exposes capability, but
        // provides no public API for downloading its language assets.
        result(self?.arabicModelStatus() ?? ["status": "unknown", "reason": "checkUnavailable"])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func prepareTasbihSound() throws {
    if tasbihSoundPlayer != nil { return }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/audio/tasbih_complete.wav")
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      throw NSError(domain: "TasbihSound", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Completion sound asset is missing"
      ])
    }
    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.prepareToPlay()
    tasbihSoundPlayer = player
  }

  private func arabicModelStatus() -> [String: Any] {
    let locales = SFSpeechRecognizer.supportedLocales().filter {
      $0.identifier.replacingOccurrences(of: "_", with: "-").hasPrefix("ar-")
        || $0.identifier == "ar"
    }.sorted {
      let left = $0.identifier.replacingOccurrences(of: "_", with: "-")
      let right = $1.identifier.replacingOccurrences(of: "_", with: "-")
      if left == "ar-SA" { return right != "ar-SA" }
      if right == "ar-SA" { return false }
      return left < right
    }
    if #available(iOS 13.0, *) {
      for locale in locales {
        if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
          return [
            "status": "installed",
            "reason": "iosOnDeviceAvailable",
            "localeId": locale.identifier.replacingOccurrences(of: "_", with: "-")
          ]
        }
      }
    }
    return ["status": "unsupported", "localeId": "ar-SA", "reason": "iosManagedBySystem"]
  }
}
