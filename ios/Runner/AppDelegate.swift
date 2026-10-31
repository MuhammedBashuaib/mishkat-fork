import Flutter
import Speech
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var speechSettingsChannel: FlutterMethodChannel?
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
            "localeId": locale.identifier.replacingOccurrences(of: "_", with: "-")
          ]
        }
      }
    }
    return ["status": "unsupported", "localeId": "ar-SA", "reason": "iosManagedBySystem"]
  }
}
