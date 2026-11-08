import Flutter
import UIKit
import CoreLocation
import CoreMotion
import simd

public class SwiftFlutterCompassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate {

    private var eventSink: FlutterEventSink?;
    private var location: CLLocationManager = CLLocationManager();
    private var motion: CMMotionManager = CMMotionManager();
    private var locationUpdatesActive = false;


    init(channel: FlutterEventChannel) {
        super.init()
        location.delegate = self
        location.headingFilter = 0.1;
        // Coarse foreground updates are sufficient to resolve true north.
        location.desiredAccuracy = kCLLocationAccuracyKilometer;
        location.distanceFilter = 1000;
        channel.setStreamHandler(self);

        motion.deviceMotionUpdateInterval = 1.0 / 30.0;
    }


  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel.init(name: "hemanthraj/flutter_compass", binaryMessenger: registrar.messenger())
    _ = SwiftFlutterCompassPlugin(channel: channel);
  }

    public func onListen(withArguments arguments: Any?,
                         eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink;
        location.startUpdatingHeading();
        motion.startDeviceMotionUpdates(using: CMAttitudeReferenceFrame.xMagneticNorthZVertical);
        syncLocationUpdates();
        return nil;
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil;
        locationUpdatesActive = false;
        location.stopUpdatingHeading();
        location.stopUpdatingLocation();
        motion.stopDeviceMotionUpdates();
        return nil;
    }

    private func syncLocationUpdates() {
        let authorization: CLAuthorizationStatus;
        if #available(iOS 14.0, *) {
            authorization = location.authorizationStatus;
        } else {
            authorization = CLLocationManager.authorizationStatus();
        }
        // Permission belongs to the app's explicit location flow. A compass
        // subscription never asks for it, including with a manually chosen city.
        let authorized = authorization == .authorizedWhenInUse || authorization == .authorizedAlways;
        if eventSink != nil && authorized {
            locationUpdatesActive = true;
            location.startUpdatingLocation();
        } else {
            locationUpdatesActive = false;
            location.stopUpdatingLocation();
            publishUnavailableHeading();
        }
    }

    private func publishUnavailableHeading() {
        eventSink?([-1.0, -1.0, -1.0]);
    }

    @available(iOS 14.0, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        syncLocationUpdates();
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        syncLocationUpdates();
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Keep an unavailable heading negative before applying orientation:
        // otherwise -1 could become a plausible 89/179 degree direction.
        guard locationUpdatesActive && newHeading.trueHeading.isFinite && newHeading.trueHeading >= 0 &&
              newHeading.headingAccuracy.isFinite && newHeading.headingAccuracy >= 0 else {
            publishUnavailableHeading();
            return;
        }
        if (newHeading.headingAccuracy>=0){
            var trueHeading = newHeading.trueHeading;
            var headingForCameraMode = trueHeading;
            // If device orientation data is available, use it to calculate the heading out the the
            // back of the device (rather than out the top of the device).
            if let data = self.motion.deviceMotion?.attitude {
                // Re-map the device orientation matrix such that the Z axis (out the back of the device)
                // always reads -90deg off magnetic north. All rotation matrices use + rotation to mean
                // counter-clockwise.
                let r1 = double3x3(rows: [
                    simd_double3(0, 0, 1),
                    simd_double3(0, 1, 0),
                    simd_double3(-1, 0, 0)
                ]); // -90 around the Y axis
                let r2 = double3x3(rows: [
                    simd_double3(0, -1, 0),
                    simd_double3(1, 0, 0),
                    simd_double3(0, 0, 1)
                ]); // -90 around the Z axis
                let R = double3x3(rows: [
                    simd_double3(data.rotationMatrix.m11, data.rotationMatrix.m12, data.rotationMatrix.m13),
                    simd_double3(data.rotationMatrix.m21, data.rotationMatrix.m22, data.rotationMatrix.m23),
                    simd_double3(data.rotationMatrix.m31, data.rotationMatrix.m32, data.rotationMatrix.m33)
                ]);
                let T = r2 * r1 * R;
                // Calculate yaw from R and add 90deg.
                let yaw = atan2(T[0, 1], T[1, 1]) + Double.pi / 2;
                headingForCameraMode = (yaw + Double.pi * 2).truncatingRemainder(dividingBy: Double.pi * 2) * 180.0 / Double.pi;
            }
            var headingForUI = trueHeading;
            switch UIApplication.shared.statusBarOrientation {
                case .portrait:
                    headingForUI = trueHeading
                case .portraitUpsideDown:
                    headingForUI = trueHeading + 180
                case .landscapeRight:
                    headingForUI = trueHeading + 90
                case .landscapeLeft:
                    headingForUI = trueHeading - 90
                default:
                    headingForUI = trueHeading
            }
            // Rotation can make a valid heading negative (landscape left).
            // Normalize only validated readings; keep the early -1 sentinel.
            headingForUI = (headingForUI.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360);
            eventSink?([headingForUI, headingForCameraMode, newHeading.headingAccuracy]);
        }
    }
}
