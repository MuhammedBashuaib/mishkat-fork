import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mishkat_app/core/services/location_service.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission response = LocationPermission.whileInUse;
  int requests = 0;
  int positionRequests = 0;
  LocationSettings? lastSettings;
  Completer<LocationPermission>? permissionResult;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permissionResult?.future ?? response;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positionRequests++;
    lastSettings = locationSettings;
    return Position(
      latitude: 21.3891,
      longitude: 39.8579,
      timestamp: DateTime(2026),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late GeolocatorPlatform original;
  late _LocationPlatform platform;
  late LocationService service;

  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
    service = LocationService();
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  test(
    'requests permission in context and obtains a bounded location fix',
    () async {
      final position = await service.currentPosition();
      expect(platform.requests, 1);
      expect(platform.positionRequests, 1);
      expect(platform.lastSettings!.timeLimit, const Duration(seconds: 30));
      expect(position.label, 'مكة المكرمة');
    },
  );

  test('granted permission does not prompt again', () async {
    platform.permission = LocationPermission.whileInUse;
    await service.currentPosition();
    expect(platform.requests, 0);
    expect(platform.positionRequests, 1);
  });

  test('denial stays recoverable without obtaining coordinates', () async {
    platform.response = LocationPermission.denied;
    await expectLater(
      service.currentPosition(),
      throwsA(
        isA<LocationFailure>().having(
          (failure) => failure.reason,
          'reason',
          LocationFailureReason.denied,
        ),
      ),
    );
    expect(platform.requests, 1);
    expect(platform.positionRequests, 0);
    platform.response = LocationPermission.whileInUse;
    await service.currentPosition();
    expect(platform.requests, 2);
  });

  test(
    'permanent denial requests a settings recovery instead of prompting',
    () async {
      platform.permission = LocationPermission.deniedForever;
      await expectLater(
        service.currentPosition(),
        throwsA(
          isA<LocationFailure>().having(
            (failure) => failure.reason,
            'reason',
            LocationFailureReason.permanentlyDenied,
          ),
        ),
      );
      expect(platform.requests, 0);
      expect(platform.positionRequests, 0);
    },
  );

  test('disabled services are distinct from a denied permission', () async {
    platform.enabled = false;
    await expectLater(
      service.currentPosition(),
      throwsA(
        isA<LocationFailure>().having(
          (failure) => failure.reason,
          'reason',
          LocationFailureReason.serviceDisabled,
        ),
      ),
    );
    expect(platform.requests, 0);
    expect(platform.positionRequests, 0);
  });

  test('simultaneous actions share one native permission request', () async {
    platform.permissionResult = Completer<LocationPermission>();
    final first = service.currentPosition();
    final second = service.currentPosition();
    expect(identical(first, second), isTrue);
    platform.permissionResult!.complete(LocationPermission.whileInUse);
    await Future.wait([first, second]);
    expect(platform.requests, 1);
    expect(platform.positionRequests, 1);
  });
}
