import 'dart:async';
import 'dart:developer' as developer;

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
  int? _activeNotificationToggle;
  int _dataRevision = 0;
  int _notificationScheduleRevision = 0;
  static const _scheduleFailureMessage =
      'تعذّر تحديث التذكيرات. حاول تفعيل التنبيهات مجددًا.';
  static const _cancellationFailureMessage =
      'تعذّر إيقاف التذكيرات. حاول إيقاف التنبيهات مجددًا.';
  bool _resetting = false;

  void invalidatePendingOperations() {
    ++_dataRevision;
    ++_notificationToggleRevision;
    _activeNotificationToggle = null;
    ++_notificationScheduleRevision;
    _resetting = true;
  }

  Future<void> load() async {
    _resetting = false;
    final savedSettings = _storage.readMap('settings');
    final settings = AppSettings.fromJson(savedSettings);
    emit(SettingsState(status: SettingsStatus.ready, settings: settings));
    if (settings.keepAwake) unawaited(WakelockPlus.enable());
    if (settings.notificationsEnabled ||
        savedSettings['notificationsEnabled'] == false) {
      // A failed cancellation (or a process exit during it) must be retried
      // after restart. A persisted off switch is also an OS calendar state.
      unawaited(rescheduleNotifications(settings));
    }
  }

  Future<LocationFailure?> useCurrentLocation({
    bool reportFailure = true,
  }) async {
    final revision = _dataRevision;
    emit(state.copyWith(status: SettingsStatus.locating, clearMessage: true));
    try {
      final position = await _locationService.currentPosition();
      if (isClosed || revision != _dataRevision) return null;
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
      return null;
    } on LocationFailure catch (error) {
      if (isClosed || revision != _dataRevision) return null;
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: reportFailure ? error.message : null,
          clearMessage: !reportFailure,
        ),
      );
      return error;
    } on Object {
      if (isClosed || revision != _dataRevision) return null;
      const error = LocationFailure('تعذّر تحديد الموقع الآن. حاول مجددًا.');
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: reportFailure ? error.message : null,
          clearMessage: !reportFailure,
        ),
      );
      return error;
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
  Future<void> setMushafTheme(MushafThemePreference value) =>
      _save(state.settings.copyWith(mushafTheme: value));
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
  Future<void> setRecitationFeedbackMode(RecitationFeedbackMode value) =>
      _save(state.settings.copyWith(recitationFeedbackMode: value));

  Future<void> setKeepAwake(bool value) async {
    final revision = _dataRevision;
    if (value) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    if (isClosed || revision != _dataRevision) {
      await WakelockPlus.disable();
      return;
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
    ++_notificationScheduleRevision;
    bool isCurrent() =>
        !isClosed && !_resetting && revision == _notificationToggleRevision;
    if (!isCurrent()) return false;
    _activeNotificationToggle = revision;
    try {
      if (enabled && !await _notifications.requestPermission()) {
        if (!isCurrent()) return false;
        emit(
          state.copyWith(
            status: SettingsStatus.failure,
            message: 'لم يُمنح إذن التنبيهات. يمكنك المحاولة مجددًا عند رغبتك.',
            notificationPermissionDenied: true,
          ),
        );
        return false;
      }
      if (!isCurrent()) return false;
      await _save(state.settings.copyWith(notificationsEnabled: enabled));
      if (!isCurrent()) return false;
      if (enabled) {
        // Retain the user's preference so resume/startup can retry, but never
        // report successful activation when the OS calendar was not updated.
        return await _rescheduleNotifications(state.settings) && isCurrent();
      }
      await _notifications.cancelAll();
      return isCurrent();
    } on Object catch (error, stack) {
      developer.log(
        'Notification toggle failed',
        name: 'notifications',
        error: error,
        stackTrace: stack,
      );
      if (isCurrent()) {
        emit(
          state.copyWith(
            status: SettingsStatus.failure,
            notificationPermissionDenied: false,
            message: enabled
                ? 'تعذّر تفعيل التنبيهات. حاول مجددًا وتحقق من أذونات الجهاز.'
                : _cancellationFailureMessage,
          ),
        );
      }
      return false;
    } finally {
      if (_activeNotificationToggle == revision) {
        _activeNotificationToggle = null;
      }
    }
  }

  Future<bool> areNotificationsAllowed() =>
      _notifications.isPermissionGranted();

  Future<bool> openNotificationSettings() => _notifications.openAppSettings();

  Future<void> testNotification({bool permissionAlreadyGranted = false}) async {
    final revision = _dataRevision;
    try {
      if (!permissionAlreadyGranted &&
          !await _notifications.requestPermission()) {
        throw StateError('notifications denied');
      }
      if (isClosed || revision != _dataRevision) return;
      await _notifications.showTest(
        sound: state.settings.adhanSound,
        vibrate: state.settings.vibrate,
        soundName: state.settings.adhanSound
            ? AdhanVoice.byId(state.settings.adhanFile)
                  .soundName(state.settings.adhanPlaybackMode)
            : null,
      );
    } on Object {
      if (!isClosed && revision == _dataRevision) {
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

  Future<void> refreshNotificationSchedule() {
    // Returning from an OS permission screen can resume the app before the
    // activation's own schedule finishes. Let that operation reconcile the
    // calendar instead of invalidating it and falsely reporting failure.
    if (_activeNotificationToggle != null) return Future<void>.value();
    return rescheduleNotifications(state.settings);
  }

  Future<void> clearAllData() async {
    invalidatePendingOperations();
    await _notifications.cancelAll();
    await _storage.clear();
    emit(
      const SettingsState(
        status: SettingsStatus.ready,
        settings: AppSettings(),
      ),
    );
    // Wakelock is optional (and absent on some test/desktop platforms).
    try {
      await WakelockPlus.disable();
    } on Object {
      // Stored settings and in-memory state have already been reset.
    }
    _resetting = false;
  }

  Future<void> _save(AppSettings settings, {bool reschedule = false}) async {
    if (_resetting) return;
    final revision = _dataRevision;
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
    if (isClosed || revision != _dataRevision || state.settings != settings) {
      return;
    }
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
    await _rescheduleNotifications(settings);
  }

  Future<bool> _rescheduleNotifications(AppSettings settings) async {
    final revision = _dataRevision;
    final scheduleRevision = ++_notificationScheduleRevision;
    bool isCurrent() =>
        !isClosed &&
        !_resetting &&
        revision == _dataRevision &&
        scheduleRevision == _notificationScheduleRevision &&
        state.settings == settings;
    if (!isCurrent()) return false;
    try {
      if (!settings.notificationsEnabled) {
        // The off preference is saved before cancellation. Retry on resume
        // and startup so a transient native failure cannot leave old alarms
        // running indefinitely while the UI says notifications are disabled.
        await _notifications.cancelAll();
        if (!isCurrent()) return false;
        if (state.message == _cancellationFailureMessage ||
            state.message == _scheduleFailureMessage) {
          emit(
            state.copyWith(status: SettingsStatus.ready, clearMessage: true),
          );
        }
        return true;
      }
      final precise = await _notifications.canSchedulePrecisely();
      if (!isCurrent()) return false;
      emit(state.copyWith(preciseAlarmsAllowed: precise));
      await _notifications.scheduleAll(
        NotificationSchedulePlanner.build(
          storage: _storage,
          settings: settings,
        ),
      );
      if (!isCurrent()) return false;
      // A retry clears only its own error, never an unrelated location/save
      // error that may have appeared while the native request was in flight.
      if (state.message == _scheduleFailureMessage) {
        emit(state.copyWith(status: SettingsStatus.ready, clearMessage: true));
      }
      return true;
    } on Object catch (error, stack) {
      developer.log(
        'Notification schedule update failed',
        name: 'notifications',
        error: error,
        stackTrace: stack,
      );
      if (isCurrent()) {
        emit(
          state.copyWith(
            status: SettingsStatus.failure,
            message: settings.notificationsEnabled
                ? _scheduleFailureMessage
                : _cancellationFailureMessage,
          ),
        );
      }
      return false;
    }
  }
}
