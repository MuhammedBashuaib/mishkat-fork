import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geomag/geomag.dart';

import '../../../prayer_times/data/services/prayer_calculator.dart';
import 'qibla_state.dart';

class QiblaCubit extends Cubit<QiblaState> {
  QiblaCubit({
    this.calculator = const PrayerCalculator(),
    TargetPlatform? platform,
    this.geoMag,
  }) : platform = platform ?? defaultTargetPlatform,
       super(const QiblaState());

  final PrayerCalculator calculator;
  final TargetPlatform platform;
  final GeoMag? geoMag;
  StreamSubscription<CompassEvent>? _subscription;
  double? _smoothed;

  void setLocation(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) {
      _subscription?.cancel();
      _subscription = null;
      _smoothed = null;
      emit(const QiblaState(status: QiblaStatus.noLocation));
      return;
    }
    final result = calculator.qibla(latitude, longitude);

    // Compute magnetic declination:
    // - On Android: Sensor readings from flutter_compass are referenced to Magnetic North.
    //   We calculate local geomagnetic declination D from WMM so device heading can be
    //   corrected to True North, matching the geographic Qibla bearing.
    // - On iOS: flutter_compass already provides CLHeading.trueHeading (True North).
    //   Applying declination on iOS would cause double-correction, so declination is null (0.0).
    double? declination;
    if (platform == TargetPlatform.android) {
      try {
        final gm = geoMag ?? GeoMag();
        declination = gm.calculate(latitude, longitude).dec;
      } catch (_) {
        declination = null;
      }
    }

    if (state.status == QiblaStatus.listening) {
      emit(
        state.copyWith(
          bearing: result.bearing,
          distanceKm: result.distanceKm,
          declination: declination,
        ),
      );
    } else {
      emit(
        QiblaState(
          status: QiblaStatus.ready,
          bearing: result.bearing,
          distanceKm: result.distanceKm,
          declination: declination,
        ),
      );
    }
  }

  /// Helper for deterministic widget & unit testing without hardware magnetometer
  void setHeadingForTesting(
    double? heading, {
    double? accuracy,
    double? declination,
  }) {
    _smoothed = heading;
    emit(
      state.copyWith(
        status: heading != null ? QiblaStatus.listening : QiblaStatus.ready,
        heading: heading != null ? ((heading % 360) + 360) % 360 : null,
        accuracy: accuracy,
        declination: declination,
      ),
    );
  }

  Future<void> start() async {
    if (state.bearing == null) return;
    final stream = FlutterCompass.events;
    if (stream == null) {
      emit(state.copyWith(status: QiblaStatus.unavailable));
      return;
    }
    await _subscription?.cancel();
    emit(state.copyWith(status: QiblaStatus.listening));
    _subscription = stream.listen(
      (event) {
        final rawHeading = event.heading;
        if (rawHeading == null) {
          emit(state.copyWith(status: QiblaStatus.unavailable, heading: null));
          return;
        }

        // 1. Normalize raw heading to [0, 360) (handles Android [-180, 180] values)
        var heading = ((rawHeading % 360) + 360) % 360;

        // 2. On Android, apply local magnetic declination to convert Magnetic Heading
        // to True North heading, aligning with geographic Qibla bearing.
        // On iOS, declination is null because trueHeading is already True North.
        if (state.declination != null) {
          heading = ((heading + state.declination! % 360) + 360) % 360;
        }

        // 3. Shortest-arc smoothing filter
        if (_smoothed == null) {
          _smoothed = heading;
        } else {
          final delta = ((heading - _smoothed! + 540) % 360) - 180;
          final alpha = delta.abs() > 25 ? .45 : .2;
          _smoothed = (_smoothed! + delta * alpha + 360) % 360;
        }

        emit(
          state.copyWith(
            status: QiblaStatus.listening,
            heading: _smoothed,
            accuracy: event.accuracy,
          ),
        );
      },
      onError: (_) => emit(
        state.copyWith(
          status: QiblaStatus.failure,
          error: 'تعذّر قراءة مستشعر البوصلة.',
        ),
      ),
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _smoothed = null;
    if (state.bearing != null) {
      emit(
        state.copyWith(
          status: QiblaStatus.ready,
          heading: null,
          accuracy: null,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
