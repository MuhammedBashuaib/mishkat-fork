import 'package:equatable/equatable.dart';

import '../../data/models/app_settings.dart';

enum SettingsStatus { initial, ready, locating, saving, failure }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.settings = const AppSettings(),
    this.message,
    this.preciseAlarmsAllowed = true,
    this.notificationPermissionDenied = false,
  });

  final SettingsStatus status;
  final AppSettings settings;
  final String? message;
  final bool preciseAlarmsAllowed;
  final bool notificationPermissionDenied;

  SettingsState copyWith({
    SettingsStatus? status,
    AppSettings? settings,
    String? message,
    bool clearMessage = false,
    bool? preciseAlarmsAllowed,
    bool? notificationPermissionDenied,
  }) => SettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    message: clearMessage ? null : message ?? this.message,
    preciseAlarmsAllowed: preciseAlarmsAllowed ?? this.preciseAlarmsAllowed,
    notificationPermissionDenied:
        notificationPermissionDenied ??
        (clearMessage ? false : this.notificationPermissionDenied),
  );

  @override
  List<Object?> get props => [
    status,
    settings,
    message,
    preciseAlarmsAllowed,
    notificationPermissionDenied,
  ];
}
