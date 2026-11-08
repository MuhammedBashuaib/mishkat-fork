# Mishkat iOS compass patch

Vendored from the published `flutter_compass` **0.8.1** package:
<https://pub.dev/packages/flutter_compass/versions/0.8.1>
Upstream repository: <https://github.com/hemanthrajv/flutter_compass>.
The original MIT license is preserved in `LICENSE`.

The upstream Dart API, event channel, Android sources, and package version are
unchanged. The example application is excluded. Only
`ios/Classes/SwiftFlutterCompassPlugin.swift` is patched:

- Start coarse location updates while the compass event stream is subscribed
  and the app already has When In Use or Always location permission. This gives
  the same `CLLocationManager` the location updates required for `trueHeading`.
- Observe authorization changes without requesting additional permission.
- Start device motion when the stream is subscribed instead of during plugin
  registration. Stop heading, location, and device motion on cancellation.
- Publish an unavailable heading for invalid sensor values before orientation
  adjustments can turn the negative sentinel into a plausible direction.
- Normalize valid orientation-adjusted headings into `[0, 360)` before sending
  them to Dart. In particular, landscape-left rotation can subtract 90 degrees
  from a valid heading; this must not be confused with the unavailable sentinel.
- With a manual city and no location permission, preserve an honest unavailable
  live heading; Mishkat can still show the geographic Qibla bearing. Do not
  silently treat magnetic north as true north.

The app already includes location and motion usage descriptions. The patch adds
no background location mode, new permission prompt, networking, or stored
coordinates. It retains Swift 4.2 syntax and availability checks for the iOS 14
authorization API; Mishkat currently targets iOS 15 and later.

The package-local `analysis_options.yaml` inherits the app's analysis settings
and disables only `unnecessary_null_in_if_null_operators` and `unnecessary_const`
for this vendored package. This preserves the published Dart source byte for
byte; other analysis and asynchronous-context safety checks remain enabled.

Run `python3 tools/check_compass_patch.py` from the app directory for the source
contract, including checksums of unchanged upstream Android and Dart files.
This check does not replace compiling the iOS plugin or verifying true north,
permission denial, rotation, tab changes, and foreground/background transitions
on a physical iPhone.

References:

- <https://developer.apple.com/documentation/corelocation/clheading/trueheading>
- <https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanagerdidchangeauthorization(_:)>.

When updating the upstream package, compare this patch explicitly and retain the
permission and subscription lifecycle behavior. Do not modify the shared pub
cache; the app resolves this repository-owned package through a path dependency.
