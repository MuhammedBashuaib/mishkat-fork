import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/services/local_notification_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../../core/services/location_service.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/adhan_preferences.dart';
import '../../data/models/reminder_preferences.dart';
import '../../data/services/notification_schedule_planner.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required this._storage,
    required this._locationService,
    required this._notifications,
  }) : super(const SettingsState());

  final LocalStorageService _storage;
  final LocationService _locationService;
  final LocalNotificationService _notifications;
  int _notificationToggleRevision = 0;

  Future<void> load() async {
    final settings = AppSettings.fromJson(_storage.readMap('settings'));
    emit(SettingsState(status: SettingsStatus.ready, settings: settings));
    if (settings.keepAwake) unawaited(WakelockPlus.enable());
    if (settings.notificationsEnabled) {
      unawaited(rescheduleNotifications(settings));
    }
  }

  Future<void> useCurrentLocation() async {
    emit(state.copyWith(status: SettingsStatus.locating, clearMessage: true));
    try {
      final position = await _locationService.currentPosition();
      final current = state.settings;
      await _save(
        current.copyWith(
          latitude: position.latitude,
          longitude: position.longitude,
          city: position.label,
          locationAuto: true,
          method: current.methodSet ? current.method : position.suggestedMethod,
          onboardingSeen: true,
        ),
        reschedule: true,
      );
    } on LocationFailure catch (error) {
      emit(
        state.copyWith(status: SettingsStatus.failure, message: error.message),
      );
    } on Object {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: 'تعذّر تحديد الموقع الآن. حاول مجددًا.',
        ),
      );
    }
  }

  Future<void> selectCity(NearbyCity city) => _save(
    state.settings.copyWith(
      latitude: city.latitude,
      longitude: city.longitude,
      city: city.name,
      locationAuto: false,
      method: state.settings.methodSet ? state.settings.method : city.method,
      onboardingSeen: true,
    ),
    reschedule: true,
  );

  Future<void> skipOnboarding() =>
      _save(state.settings.copyWith(onboardingSeen: true));

  Future<void> setTheme(AppThemePreference value) =>
      _save(state.settings.copyWith(theme: value));
  Future<void> setWidgetTheme(AppThemePreference value) =>
      _save(state.settings.copyWith(widgetTheme: value));
  Future<void> setUiFontScale(double value) =>
      _save(state.settings.copyWith(uiFontScale: value));
  Future<void> setQuranFont(double value) =>
      _save(state.settings.copyWith(quranFont: value));
  Future<void> setReciter(String value) =>
      _save(state.settings.copyWith(reciter: value));
  Future<void> setAsr(String value) =>
      _save(state.settings.copyWith(asr: value), reschedule: true);
  Future<void> setHighLatitudes(String value) =>
      _save(state.settings.copyWith(highLatitudes: value), reschedule: true);
  Future<void> setHijriOffset(int value) =>
      _save(state.settings.copyWith(hijriOffset: value.clamp(-2, 2)));
  Future<void> setPreMinutes(int value) => _save(
    state.settings.copyWith(preMinutes: value.clamp(0, 60)),
    reschedule: true,
  );
  Future<void> setAdhkarNotifications(bool value) => _save(
    state.settings.copyWith(adhkarNotifications: value),
    reschedule: true,
  );
  Future<void> setReminders(ReminderPreferences value) =>
      _save(state.settings.copyWith(reminders: value), reschedule: true);
  Future<void> setAdhanSound(bool value) =>
      _save(state.settings.copyWith(adhanSound: value), reschedule: true);
  Future<void> setAdhanFile(String value) =>
      _save(state.settings.copyWith(adhanFile: value), reschedule: true);
  Future<void> setAdhanPlaybackMode(AdhanPlaybackMode value) => _save(
    state.settings.copyWith(adhanPlaybackMode: value),
    reschedule: true,
  );
  Future<void> setVibration(bool value) =>
      _save(state.settings.copyWith(vibrate: value), reschedule: true);
  Future<void> setAutoScroll(bool value) =>
      _save(state.settings.copyWith(quranAutoScroll: value));
  Future<void> setContinuousAudio(bool value) =>
      _save(state.settings.copyWith(quranContinuous: value));

  Future<void> setKeepAwake(bool value) async {
    if (value) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    await _save(state.settings.copyWith(keepAwake: value));
  }

  Future<void> setMethod(String value) => _save(
    state.settings.copyWith(method: value, methodSet: true),
    reschedule: true,
  );

  Future<void> setTune(String prayer, int minutes) {
    final tune = Map<String, int>.from(state.settings.tune)
      ..[prayer] = minutes.clamp(-30, 30);
    return _save(state.settings.copyWith(tune: tune), reschedule: true);
  }

  Future<void> setPrayerNotification(String prayer, bool enabled) {
    final values = Map<String, bool>.from(state.settings.prayerNotifications)
      ..[prayer] = enabled;
    return _save(
      state.settings.copyWith(
        prayerNotifications: values,
        prayerAdhanEnabled: {
          ...state.settings.prayerAdhanEnabled,
          if (!enabled) prayer: false,
        },
      ),
      reschedule: true,
    );
  }

  Future<void> setPrayerAdhan(String prayer, bool enabled) {
    final adhanValues = Map<String, bool>.from(
      state.settings.prayerAdhanEnabled,
    )..[prayer] = enabled;
    final notificationValues = Map<String, bool>.from(
      state.settings.prayerNotifications,
    );
    // A system notification is the reliable, OS-supported trigger for an
    // adhan while the application is closed.
    if (enabled) notificationValues[prayer] = true;
    return _save(
      state.settings.copyWith(
        prayerAdhanEnabled: adhanValues,
        prayerNotifications: notificationValues,
      ),
      reschedule: true,
    );
  }

  Future<bool> setNotificationsEnabled(bool enabled) async {
    final revision = ++_notificationToggleRevision;
    if (enabled && !await _notifications.requestPermission()) {
      if (isClosed || revision != _notificationToggleRevision) return false;
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: 'لم يُمنح إذن التنبيهات من إعدادات الجهاز.',
        ),
      );
      return false;
    }
    if (isClosed || revision != _notificationToggleRevision) return false;
    await _save(state.settings.copyWith(notificationsEnabled: enabled));
    if (isClosed || revision != _notificationToggleRevision) return false;
    if (enabled) {
      await rescheduleNotifications(state.settings);
    } else {
      await _notifications.cancelAll();
    }
    return true;
  }

  Future<void> testNotification() async {
    try {
      if (!await _notifications.requestPermission()) {
        throw StateError('notifications denied');
      }
      await _notifications.showTest(
        sound: state.settings.adhanSound,
        vibrate: state.settings.vibrate,
        soundName: state.settings.adhanSound
            ? AdhanVoice.byId(state.settings.adhanFile)
                  .soundName(state.settings.adhanPlaybackMode)
            : null,
      );
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: SettingsStatus.failure,
            message: 'تعذّر تشغيل التجربة. تحقق من إذن الإشعارات والصوت في إعدادات الجهاز.',
          ),
        );
      }
    }
  }

  Future<void> stopAdhanTest() => _notifications.stopTest();

  Future<void> refreshNotificationSchedule() =>
      rescheduleNotifications(state.settings);

  Future<void> clearAllData() async {
    await _notifications.cancelAll();
    await _storage.clear();
    emit(
      const SettingsState(
        status: SettingsStatus.ready,
        settings: AppSettings(),
      ),
    );
  }

  Future<void> _save(AppSettings settings, {bool reschedule = false}) async {
    emit(
      state.copyWith(
        status: SettingsStatus.saving,
        settings: settings,
        clearMessage: true,
      ),
    );
    await _storage.writeMap('settings', settings.toJson());
    // A later toggle may have arrived while the write was pending. Do not
    // restore or schedule that older snapshot over the user's latest choice.
    if (isClosed || state.settings != settings) return;
    emit(
      state.copyWith(
        status: SettingsStatus.ready,
        settings: settings,
        clearMessage: true,
      ),
    );
    if (reschedule && settings.notificationsEnabled) {
      await rescheduleNotifications(settings);
    }
  }

  Future<void> rescheduleNotifications(AppSettings settings) async {
    if (!settings.notificationsEnabled) return;
    try {
      final precise = await _notifications.canSchedulePrecisely();
      if (isClosed || state.settings != settings) return;
      emit(state.copyWith(preciseAlarmsAllowed: precise));
      await _notifications.scheduleAll(
        NotificationSchedulePlanner.build(
          storage: _storage,
          settings: settings,
        ),
      );
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: SettingsStatus.failure,
            message: 'تعذّر تحديث التذكيرات. أعد تفعيل التنبيهات وتحقق من أذونات الجهاز.',
          ),
        );
      }
    }
  }
}
