#!/usr/bin/env python3
"""Source contracts for the vendored iOS patch; no Flutter or device required."""

import hashlib
from pathlib import Path
import re
import unittest


APP = Path(__file__).resolve().parents[1]
PACKAGE = APP / "packages/flutter_compass"
SWIFT = (PACKAGE / "ios/Classes/SwiftFlutterCompassPlugin.swift").read_text()
UPSTREAM_SHA256 = {
    "android/build.gradle": "5f340f6b0f5ea9579a9a56b12354bc3bba234bf5724d71a5a3aada64ea619a7d",
    "android/gradle/wrapper/gradle-wrapper.properties": "9340dd42ca2faa078b7ad56728e4548a369312511c6135bdf9069863b5ad55d1",
    "android/gradle.properties": "034fd3f15ac7a699cf7393150e318cd3e0afb51826b0decc69a548db53fa1116",
    "android/settings.gradle": "f1fde14e064c20ef2ec30917d51fdcb16ddbe18c85a84e9174db6e142174aa4e",
    "android/src/main/AndroidManifest.xml": "d72b2fd1f22437d42d07fea8437fb2bcdf5aa6a8b1461d35851a3392d2b42cfb",
    "android/src/main/java/com/hemanthraj/fluttercompass/FlutterCompassPlugin.java": "31632965310c69e0882bf3f26816a8e8ff6c1156b703260ea592e3181dc611a9",
    "lib/flutter_compass.dart": "ff58c3eee7a9acf24b4d43061c26c9159592eaa5756aaa8d684dc4ad85b176db",
}


def body(signature):
    start = SWIFT.index("{", SWIFT.index(signature))
    depth = 1
    for end in range(start + 1, len(SWIFT)):
        depth += (SWIFT[end] == "{") - (SWIFT[end] == "}")
        if depth == 0:
            return SWIFT[start + 1 : end]
    raise AssertionError(f"Unclosed Swift function: {signature}")


class CompassPatchContracts(unittest.TestCase):
    def test_android_and_dart_remain_upstream_081(self):
        for relative, expected in UPSTREAM_SHA256.items():
            with self.subTest(file=relative):
                actual = hashlib.sha256((PACKAGE / relative).read_bytes()).hexdigest()
                self.assertEqual(actual, expected)
        self.assertIn("version: 0.8.1", (PACKAGE / "pubspec.yaml").read_text())
        self.assertIn("MIT License", (PACKAGE / "LICENSE").read_text())

    def test_compass_never_requests_location_permission(self):
        self.assertIsNone(re.search(
            r"\.request(?:WhenInUseAuthorization|AlwaysAuthorization|TemporaryFullAccuracyAuthorization)\s*\(",
            SWIFT,
        ))

    def test_location_updates_require_both_permission_and_listener(self):
        sync = body("private func syncLocationUpdates()")
        self.assertIn("authorization == .authorizedWhenInUse", sync)
        self.assertIn("authorization == .authorizedAlways", sync)
        self.assertIn("if eventSink != nil && authorized {", sync)
        self.assertEqual(SWIFT.count("location.startUpdatingLocation()"), 1)
        allowed, denied = sync.split("if eventSink != nil && authorized {", 1)[1].split("} else {", 1)
        self.assertIn("locationUpdatesActive = true", allowed)
        self.assertIn("location.startUpdatingLocation()", allowed)
        self.assertIn("locationUpdatesActive = false", denied)
        self.assertIn("location.stopUpdatingLocation()", denied)
        self.assertIn("publishUnavailableHeading()", denied)

    def test_sensor_lifetime_matches_subscription(self):
        listen = body("public func onListen(")
        cancel = body("public func onCancel(")
        for call in ["location.startUpdatingHeading()", "motion.startDeviceMotionUpdates(", "syncLocationUpdates()"]:
            self.assertIn(call, listen)
        for call in ["location.stopUpdatingHeading()", "location.stopUpdatingLocation()", "motion.stopDeviceMotionUpdates()"]:
            self.assertIn(call, cancel)
        self.assertEqual(SWIFT.count("motion.startDeviceMotionUpdates("), 1)
        self.assertNotIn("startDeviceMotionUpdates", body("init(channel:"))
        self.assertIn("locationUpdatesActive = false", cancel)

    def test_authorization_changes_recheck_the_active_subscription(self):
        self.assertIn("syncLocationUpdates()", body("public func locationManagerDidChangeAuthorization("))
        self.assertIn("syncLocationUpdates()", body("didChangeAuthorization status:"))

    def test_invalid_heading_is_rejected_before_orientation_offsets(self):
        heading = body("didUpdateHeading newHeading:")
        guard, orientation = heading.split("var trueHeading", 1)
        for condition in ["guard locationUpdatesActive", "trueHeading.isFinite", "trueHeading >= 0", "headingAccuracy.isFinite", "headingAccuracy >= 0"]:
            self.assertIn(condition, guard)
        self.assertIn("publishUnavailableHeading()", guard)
        self.assertIn("return;", guard)
        self.assertIn("trueHeading + 90", orientation)
        self.assertIn("[-1.0, -1.0, -1.0]", body("private func publishUnavailableHeading()"))

    def test_app_resolves_repository_owned_package(self):
        self.assertRegex((APP / "pubspec.yaml").read_text(),
                         r"flutter_compass:\s*\n\s+path: packages/flutter_compass")

    def test_valid_orientation_is_normalized_before_publication(self):
        heading = body("didUpdateHeading newHeading:")
        normalization = "headingForUI = (headingForUI.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360);"
        self.assertIn(normalization, heading)
        self.assertLess(heading.index("trueHeading - 90"), heading.index(normalization))
        self.assertLess(heading.index(normalization), heading.index("eventSink?([headingForUI"))
        self.assertLess(heading.index("publishUnavailableHeading()"), heading.index(normalization))


if __name__ == "__main__":
    unittest.main(verbosity=2)
