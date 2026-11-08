# iOS privacy resources

Each executable or framework that calls a required-reason API needs its own
bundled `PrivacyInfo.xcprivacy`. The Xcode project includes the Runner manifest
in the app and the shared Widgets manifest in each of the five WidgetKit
extensions. The Podfile adds the home_widget manifest to that framework's
resources because version 0.10.0 does not supply one. Other plugins retain their
own manifests; review this addition when upgrading home_widget.

Declared uses:

- `1C8F.1` / UserDefaults: the app and widget plugin exchange widget content and
  appearance preferences with extensions in `group.com.dakomn.mishkatapp.widgets`.
  Widget code reads that same suite. This is App Group storage, so the app-only
  reason `CA92.1` would not describe it correctly.
- `C617.1` / FileTimestamp (Runner): local storage recovery sorts backups by
  modification time and the audio cache reads local file sizes. These files
  remain inside the application's container.
- `35F9.1` / SystemBootTime (Runner): Dart stopwatches measure elapsed time for
  recitation and feedback scheduling; they are not used for fingerprinting.

No tracking domains or first-party off-device collection are declared here.
The app's privacy policy separately explains requests for third-party audio
and reference content. These manifests do not replace the store's privacy
questionnaire or permission descriptions.

Official references (reviewed 8 November 2026):

- [Required reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

The Xcode project and workspace were recovered from `2fb53ec^`, before their
deletion, preserving the existing app identity, team, five extension targets,
App Group entitlements, and six bundled notification sounds. Runner's marketing
version now follows `FLUTTER_BUILD_NAME`, like the extensions, so a Flutter
version change cannot leave the targets with different versions.
