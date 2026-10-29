import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'adhan_preferences.dart';

const _unset = Object();

enum AppThemePreference { system, light, dark }

class AppSettings extends Equatable {
  const AppSettings({
    this.latitude,
    this.longitude,
    this.city = '',
    this.locationAuto = false,
    this.method = 'MWL',
    this.methodSet = false,
    this.asr = 'Standard',
    this.highLatitudes = 'NightMiddle',
    this.hijriOffset = 0,
    this.tune = const {
      'fajr': 0,
      'sunrise': 0,
      'dhuhr': 0,
      'asr': 0,
      'maghrib': 0,
      'isha': 0,
    },
    this.notificationsEnabled = false,
    this.adhanSound = true,
    this.adhanFile = 'adhan1',
    this.adhanPlaybackMode = AdhanPlaybackMode.full,
    this.preMinutes = 0,
    this.prayerNotifications = const {
      'fajr': true,
      'dhuhr': true,
      'asr': true,
      'maghrib': true,
      'isha': true,
    },
    this.prayerAdhanEnabled = const {
      'fajr': true,
      'dhuhr': true,
      'asr': true,
      'maghrib': true,
      'isha': true,
    },
    this.adhkarNotifications = false,
    this.theme = AppThemePreference.system,
    this.uiFontScale = 1,
    this.quranFont = 32,
    this.reciter = 'ar.alafasy',
    this.quranAutoScroll = true,
    this.quranContinuous = true,
    this.keepAwake = false,
    this.vibrate = true,
    this.onboardingSeen = false,
  });

  final double? latitude;
  final double? longitude;
  final String city;
  final bool locationAuto;
  final String method;
  final bool methodSet;
  final String asr;
  final String highLatitudes;
  final int hijriOffset;
  final Map<String, int> tune;
  final bool notificationsEnabled;
  final bool adhanSound;
  final String adhanFile;
  final AdhanPlaybackMode adhanPlaybackMode;
  final int preMinutes;
  final Map<String, bool> prayerNotifications;
  final Map<String, bool> prayerAdhanEnabled;
  final bool adhkarNotifications;
  final AppThemePreference theme;
  final double uiFontScale;
  final double quranFont;
  final String reciter;
  final bool quranAutoScroll;
  final bool quranContinuous;
  final bool keepAwake;
  final bool vibrate;
  final bool onboardingSeen;

  bool get hasLocation => latitude != null && longitude != null;
  ThemeMode get themeMode => switch (theme) {
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
    AppThemePreference.system => ThemeMode.system,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    Map<String, int> integerMap(String key, Map<String, int> defaults) {
      final raw = json[key];
      if (raw is! Map) return defaults;
      return {
        ...defaults,
        ...raw.map(
          (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
        ),
      };
    }

    Map<String, bool> boolMap(String key, Map<String, bool> defaults) {
      final raw = json[key];
      if (raw is! Map) return defaults;
      return {
        ...defaults,
        ...raw.map((key, value) => MapEntry('$key', value == true)),
      };
    }

    final themeName = json['theme'] as String? ?? 'system';
    const defaultPrayers = {
      'fajr': true,
      'dhuhr': true,
      'asr': true,
      'maghrib': true,
      'isha': true,
    };
    final prayerNotifications = boolMap('prayerNotifications', defaultPrayers);
    final adhanModeName = json['adhanPlaybackMode'] as String? ?? 'full';
    return AppSettings(
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      city: json['city'] as String? ?? '',
      locationAuto: json['locationAuto'] == true,
      method: json['method'] as String? ?? 'MWL',
      methodSet: json['methodSet'] == true,
      asr: json['asr'] as String? ?? 'Standard',
      highLatitudes: json['highLatitudes'] as String? ?? 'NightMiddle',
      hijriOffset: (json['hijriOffset'] as num?)?.toInt() ?? 0,
      tune: integerMap('tune', const {
        'fajr': 0,
        'sunrise': 0,
        'dhuhr': 0,
        'asr': 0,
        'maghrib': 0,
        'isha': 0,
      }),
      notificationsEnabled: json['notificationsEnabled'] == true,
      adhanSound: json['adhanSound'] != false,
      adhanFile: _validAdhanFile(json['adhanFile'] as String?),
      adhanPlaybackMode: AdhanPlaybackMode.values.firstWhere(
        (mode) => mode.name == adhanModeName,
        orElse: () => AdhanPlaybackMode.full,
      ),
      preMinutes: (json['preMinutes'] as num?)?.toInt() ?? 0,
      prayerNotifications: prayerNotifications,
      prayerAdhanEnabled: boolMap('prayerAdhanEnabled', prayerNotifications),
      adhkarNotifications: json['adhkarNotifications'] == true,
      theme: AppThemePreference.values.firstWhere(
        (item) => item.name == themeName,
        orElse: () => AppThemePreference.system,
      ),
      uiFontScale:
          (json['uiFontScale'] as num?)?.toDouble().clamp(1, 1.25) ?? 1,
      quranFont: (json['quranFont'] as num?)?.toDouble().clamp(20, 60) ?? 32,
      reciter: json['reciter'] as String? ?? 'ar.alafasy',
      quranAutoScroll: json['quranAutoScroll'] != false,
      quranContinuous: json['quranContinuous'] != false,
      keepAwake: json['keepAwake'] == true,
      vibrate: json['vibrate'] != false,
      onboardingSeen: json['onboardingSeen'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'locationAuto': locationAuto,
    'method': method,
    'methodSet': methodSet,
    'asr': asr,
    'highLatitudes': highLatitudes,
    'hijriOffset': hijriOffset,
    'tune': tune,
    'notificationsEnabled': notificationsEnabled,
    'adhanSound': adhanSound,
    'adhanFile': adhanFile,
    'adhanPlaybackMode': adhanPlaybackMode.name,
    'preMinutes': preMinutes,
    'prayerNotifications': prayerNotifications,
    'prayerAdhanEnabled': prayerAdhanEnabled,
    'adhkarNotifications': adhkarNotifications,
    'theme': theme.name,
    'uiFontScale': uiFontScale,
    'quranFont': quranFont,
    'reciter': reciter,
    'quranAutoScroll': quranAutoScroll,
    'quranContinuous': quranContinuous,
    'keepAwake': keepAwake,
    'vibrate': vibrate,
    'onboardingSeen': onboardingSeen,
  };

  AppSettings copyWith({
    Object? latitude = _unset,
    Object? longitude = _unset,
    String? city,
    bool? locationAuto,
    String? method,
    bool? methodSet,
    String? asr,
    String? highLatitudes,
    int? hijriOffset,
    Map<String, int>? tune,
    bool? notificationsEnabled,
    bool? adhanSound,
    String? adhanFile,
    AdhanPlaybackMode? adhanPlaybackMode,
    int? preMinutes,
    Map<String, bool>? prayerNotifications,
    Map<String, bool>? prayerAdhanEnabled,
    bool? adhkarNotifications,
    AppThemePreference? theme,
    double? uiFontScale,
    double? quranFont,
    String? reciter,
    bool? quranAutoScroll,
    bool? quranContinuous,
    bool? keepAwake,
    bool? vibrate,
    bool? onboardingSeen,
  }) => AppSettings(
    latitude: identical(latitude, _unset) ? this.latitude : latitude as double?,
    longitude: identical(longitude, _unset)
        ? this.longitude
        : longitude as double?,
    city: city ?? this.city,
    locationAuto: locationAuto ?? this.locationAuto,
    method: method ?? this.method,
    methodSet: methodSet ?? this.methodSet,
    asr: asr ?? this.asr,
    highLatitudes: highLatitudes ?? this.highLatitudes,
    hijriOffset: hijriOffset ?? this.hijriOffset,
    tune: tune ?? this.tune,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    adhanSound: adhanSound ?? this.adhanSound,
    adhanFile: adhanFile ?? this.adhanFile,
    adhanPlaybackMode: adhanPlaybackMode ?? this.adhanPlaybackMode,
    preMinutes: preMinutes ?? this.preMinutes,
    prayerNotifications: prayerNotifications ?? this.prayerNotifications,
    prayerAdhanEnabled: prayerAdhanEnabled ?? this.prayerAdhanEnabled,
    adhkarNotifications: adhkarNotifications ?? this.adhkarNotifications,
    theme: theme ?? this.theme,
    uiFontScale: uiFontScale ?? this.uiFontScale,
    quranFont: quranFont ?? this.quranFont,
    reciter: reciter ?? this.reciter,
    quranAutoScroll: quranAutoScroll ?? this.quranAutoScroll,
    quranContinuous: quranContinuous ?? this.quranContinuous,
    keepAwake: keepAwake ?? this.keepAwake,
    vibrate: vibrate ?? this.vibrate,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
  );

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    city,
    locationAuto,
    method,
    methodSet,
    asr,
    highLatitudes,
    hijriOffset,
    tune,
    notificationsEnabled,
    adhanSound,
    adhanFile,
    adhanPlaybackMode,
    preMinutes,
    prayerNotifications,
    prayerAdhanEnabled,
    adhkarNotifications,
    theme,
    uiFontScale,
    quranFont,
    reciter,
    quranAutoScroll,
    quranContinuous,
    keepAwake,
    vibrate,
    onboardingSeen,
  ];
}

String _validAdhanFile(String? value) {
  const allowed = {'adhan1', 'adhan2', 'adhan4'};
  if (value != null && allowed.contains(value)) return value;
  if (value != null && RegExp(r'^a[124]$').hasMatch(value)) {
    return 'adhan${value.substring(1)}';
  }
  return 'adhan1';
}
