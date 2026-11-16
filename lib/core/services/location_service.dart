import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<AppPosition>? _pendingPosition;

  Future<AppPosition> currentPosition() => _pendingPosition ??= _locate()
      .whenComplete(() => _pendingPosition = null);

  Future<AppPosition> _locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'خدمة الموقع متوقفة على الجهاز. فعّلها لحساب الصلاة والقبلة، أو اختر مدينتك يدويًا.',
        reason: LocationFailureReason.serviceDisabled,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'إذن الموقع مغلق لمشكاة. يمكنك السماح به من إعدادات الجهاز، أو اختيار مدينتك يدويًا.',
        reason: LocationFailureReason.permanentlyDenied,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        'لم يُسمح بالوصول إلى الموقع. نحتاجه لحساب الصلاة والقبلة، ويمكنك اختيار مدينتك دون منح الإذن.',
        reason: LocationFailureReason.denied,
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30),
      ),
    );
    final nearest = closestCity(position.latitude, position.longitude);
    return AppPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      label: nearest.distanceKm <= 450 ? nearest.name : 'موقعك الحالي',
      suggestedMethod: nearest.method,
    );
  }

  NearbyCity closestCity(double latitude, double longitude) {
    NearbyCity? best;
    for (final city in cities) {
      final distance = _distance(
        latitude,
        longitude,
        city.latitude,
        city.longitude,
      );
      if (best == null || distance < best.distanceKm) {
        best = city.copyWith(distanceKm: distance);
      }
    }
    return best!;
  }

  double _distance(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371.0;
    double rad(double value) => value * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static const cities = <NearbyCity>[
    NearbyCity('مكة المكرمة', 21.3891, 39.8579, 'Makkah'),
    NearbyCity('المدينة المنورة', 24.4686, 39.6142, 'Makkah'),
    NearbyCity('الرياض', 24.7136, 46.6753, 'Makkah'),
    NearbyCity('جدة', 21.4858, 39.1925, 'Makkah'),
    NearbyCity('الدمام', 26.4207, 50.0888, 'Makkah'),
    NearbyCity('أبها', 18.2164, 42.5053, 'Makkah'),
    NearbyCity('القدس', 31.7683, 35.2137, 'Egypt'),
    NearbyCity('غزة', 31.5017, 34.4668, 'Egypt'),
    NearbyCity('عمّان', 31.9539, 35.9106, 'Egypt'),
    NearbyCity('القاهرة', 30.0444, 31.2357, 'Egypt'),
    NearbyCity('الإسكندرية', 31.2001, 29.9187, 'Egypt'),
    NearbyCity('دبي', 25.2048, 55.2708, 'Dubai'),
    NearbyCity('أبوظبي', 24.4539, 54.3773, 'Dubai'),
    NearbyCity('الدوحة', 25.2854, 51.5310, 'Qatar'),
    NearbyCity('الكويت', 29.3759, 47.9774, 'Kuwait'),
    NearbyCity('المنامة', 26.2285, 50.5860, 'Gulf'),
    NearbyCity('مسقط', 23.5880, 58.3829, 'Gulf'),
    NearbyCity('صنعاء', 15.3694, 44.1910, 'MWL'),
    NearbyCity('عدن', 12.7855, 45.0187, 'MWL'),
    NearbyCity('الشحر، حضرموت', 14.7664, 49.6254, 'MWL'),
    NearbyCity('حضرموت', 14.54, 49.12, 'MWL'),
    NearbyCity('المهرة', 16.21, 52.18, 'MWL'),
    NearbyCity('تعز', 13.58, 44.02, 'MWL'),
    NearbyCity('الحديدة', 14.80, 42.95, 'MWL'),
    NearbyCity('سقطرى', 12.51, 53.92, 'MWL'),
    NearbyCity('بغداد', 33.3152, 44.3661, 'Karachi'),
    NearbyCity('بيروت', 33.8938, 35.5018, 'Egypt'),
    NearbyCity('دمشق', 33.5138, 36.2765, 'Egypt'),
    NearbyCity('تونس', 36.8065, 10.1815, 'MWL'),
    NearbyCity('الجزائر', 36.7538, 3.0588, 'MWL'),
    NearbyCity('الرباط', 34.0209, -6.8416, 'MWL'),
    NearbyCity('الدار البيضاء', 33.5731, -7.5898, 'MWL'),
    NearbyCity('إسطنبول', 41.0082, 28.9784, 'Turkey'),
    NearbyCity('كوالالمبور', 3.1390, 101.6869, 'Singapore'),
    NearbyCity('جاكرتا', -6.2088, 106.8456, 'Singapore'),
    NearbyCity('كراتشي', 24.8607, 67.0011, 'Karachi'),
    NearbyCity('لندن', 51.5074, -0.1278, 'MWL'),
    NearbyCity('باريس', 48.8566, 2.3522, 'France'),
    NearbyCity('نيويورك', 40.7128, -74.0060, 'ISNA'),
    NearbyCity('تورونتو', 43.6532, -79.3832, 'ISNA'),
    NearbyCity('سيدني', -33.8688, 151.2093, 'MWL'),
  ];
}

class AppPosition {
  const AppPosition({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.suggestedMethod,
  });
  final double latitude;
  final double longitude;
  final String label;
  final String suggestedMethod;
}

class NearbyCity {
  const NearbyCity(
    this.name,
    this.latitude,
    this.longitude,
    this.method, [
    this.distanceKm = double.infinity,
  ]);
  final String name;
  final double latitude;
  final double longitude;
  final String method;
  final double distanceKm;

  NearbyCity copyWith({double? distanceKm}) => NearbyCity(
    name,
    latitude,
    longitude,
    method,
    distanceKm ?? this.distanceKm,
  );
}

enum LocationFailureReason {
  unavailable,
  serviceDisabled,
  denied,
  permanentlyDenied,
}

class LocationFailure implements Exception {
  const LocationFailure(
    this.message, {
    this.reason = LocationFailureReason.unavailable,
  });
  final String message;
  final LocationFailureReason reason;
  @override
  String toString() => message;
}
