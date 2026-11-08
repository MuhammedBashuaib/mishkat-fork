import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_notification_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/data/services/notification_schedule_planner.dart';
import '../../data/models/khatma_plan.dart';
import '../../data/models/khatma_schedule.dart';
import 'khatma_state.dart';

class KhatmaCubit extends Cubit<KhatmaState> {
  // A named public argument is clearer at composition sites than exposing the
  // private field name as an initializing formal.
  KhatmaCubit(this._storage, {LocalNotificationService? notifications})
    // ignore: prefer_initializing_formals
    : _notifications = notifications,
      super(const KhatmaState()) {
    load();
  }
  final LocalStorageService _storage;
  final LocalNotificationService? _notifications;
  int _dataGeneration = 0;
  bool _resetting = false;

  void invalidatePendingOperations() {
    _dataGeneration++;
    _resetting = true;
  }

  void resetLocalData() {
    invalidatePendingOperations();
    emit(const KhatmaState());
    _resetting = false;
  }

  void load() {
    _resetting = false;
    final saved = _storage.readMap('khatma');
    final plans = <KhatmaPlan>[
      if (saved['plans'] is List)
        for (final item in saved['plans'] as List)
          if (item is Map) KhatmaPlan.fromJson(Map<String, dynamic>.from(item)),
    ];
    final activeId = saved['activeId'] as String?;
    emit(
      KhatmaState(
        plans: plans,
        activeId: plans.any((item) => item.id == activeId)
            ? activeId
            : plans.firstOrNull?.id,
      ),
    );
  }

  Future<void> create({
    required String name,
    required int durationDays,
    required int startPage,
    String? reminderPrayer,
    String? reminderTime,
    KhatmaPlanningMode planningMode = KhatmaPlanningMode.duration,
    int? dailyPages,
  }) async {
    final generation = _dataGeneration;
    final schedule = planningMode == KhatmaPlanningMode.pages
        ? KhatmaSchedule.fromDailyPages(
            startPage: startPage,
            dailyPages: dailyPages ?? 5,
          )
        : KhatmaSchedule.fromDuration(
            startPage: startPage,
            durationDays: durationDays,
          );
    final safeStart = schedule.startPage;
    final duration = schedule.durationDays;
    final daily = schedule.maxDailyPages;
    final now = DateTime.now();
    final time = KhatmaPlan.normalizeReminderTime(reminderTime);
    final plan = KhatmaPlan(
      id: now.microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'ختمتي' : name.trim(),
      durationDays: duration,
      dailyPages: daily,
      startDate: now,
      planningMode: planningMode,
      balancedSchedule: schedule.isBalanced,
      startPage: safeStart,
      progressPage: safeStart - 1,
      lastReadPage: safeStart,
      currentWardEndPage: math.min(604, safeStart + daily - 1),
      status: KhatmaStatus.active,
      reminderPrayer: time == null ? reminderPrayer : null,
      reminderTime: time,
      createdAt: now,
    );
    final updated = KhatmaState(
      plans: [plan, ...state.plans],
      activeId: plan.id,
    );
    // Publish the plan only once it is durable. Scheduling can then fail
    // independently while the saved plan remains available for a retry.
    await _storage.writeMap('khatma', {
      'activeId': updated.activeId,
      'plans': updated.plans.map((item) => item.toJson()).toList(),
    });
    if (isClosed || generation != _dataGeneration) return;
    emit(updated);
    await _refreshNotificationCalendar();
  }

  Future<void> setActive(String id) async {
    if (!state.plans.any((item) => item.id == id)) return;
    emit(state.copyWith(activeId: id));
    await _persist();
    await _refreshNotificationCalendar();
  }

  Future<void> recordProgress(int page) async {
    final plan = state.active;
    if (plan == null) return;
    await recordReadingPosition(
      planId: plan.id,
      currentPage: math.min(604, page + 1),
      completedThrough: page,
    );
  }

  /// Saves a Khatma reading session independently from the general Mushaf
  /// bookmark. Progress is monotonic: revisiting earlier pages never erases
  /// pages already completed.
  Future<void> recordReadingPosition({
    required String planId,
    required int currentPage,
    int? completedThrough,
    bool requireContiguousProgress = false,
  }) async {
    final plan = state.plans.where((item) => item.id == planId).firstOrNull;
    if (plan == null || plan.status != KhatmaStatus.active) return;

    final safeCurrent = currentPage.clamp(plan.startPage, 604);
    // Automatic page turns may complete only the next unread page. Explicit
    // completion actions can still confirm an entire portion at once.
    final safeCompleted =
        completedThrough == null ||
            (requireContiguousProgress && completedThrough != plan.nextPage)
        ? plan.progressPage
        : completedThrough.clamp(plan.startPage - 1, 604);
    final progress = math.max(plan.progressPage, safeCompleted);
    final completed = progress >= 604;
    final currentWardEnd = plan.todayEnd;
    final nextWardEnd = !completed && progress >= currentWardEnd
        ? plan.nextWardEndAfter(progress)
        : (plan.currentWardEndPage ?? currentWardEnd);
    final updated = plan.copyWith(
      progressPage: progress,
      lastReadPage: safeCurrent,
      currentWardEndPage: nextWardEnd,
      status: completed ? KhatmaStatus.completed : KhatmaStatus.active,
      completedAt: completed ? DateTime.now() : null,
      pausedAt: null,
    );
    await _replace(updated);
    if (completed || progress >= currentWardEnd) {
      await _refreshNotificationCalendar();
    }
  }

  Future<void> completeReadingPage({
    required String planId,
    required int page,
  }) async {
    await recordReadingPosition(
      planId: planId,
      currentPage: math.min(604, page + 1),
      completedThrough: page,
    );
  }

  Future<void> completeToday() async {
    final plan = state.active;
    if (plan == null) return;
    await recordProgress(plan.todayEnd);
  }

  Future<void> togglePause() async {
    final plan = state.active;
    if (plan == null || plan.status == KhatmaStatus.completed) return;
    final paused = plan.status != KhatmaStatus.paused;
    await _replace(
      plan.copyWith(
        status: paused ? KhatmaStatus.paused : KhatmaStatus.active,
        pausedAt: paused ? DateTime.now() : null,
      ),
    );
    await _refreshNotificationCalendar();
  }

  Future<void> rebalance(int remainingDays) async {
    final plan = state.active;
    if (plan == null || plan.remainingPages == 0) return;
    final schedule = KhatmaSchedule.fromDuration(
      startPage: plan.nextPage,
      durationDays: remainingDays,
    );
    await _replace(
      plan.copyWith(
        durationDays: schedule.durationDays,
        dailyPages: schedule.maxDailyPages,
        planningMode: KhatmaPlanningMode.duration,
        balancedSchedule: true,
        scheduleStartPage: plan.nextPage,
        scheduleStartDate: DateTime.now(),
        currentWardEndPage: schedule.endPageAfter(plan.progressPage),
      ),
    );
    await _refreshNotificationCalendar();
  }

  Future<void> delete(String id) async {
    final plans = state.plans.where((item) => item.id != id).toList();
    emit(KhatmaState(plans: plans, activeId: plans.firstOrNull?.id));
    await _persist();
    await _refreshNotificationCalendar();
  }

  Future<void> _replace(KhatmaPlan plan) async {
    emit(
      state.copyWith(
        plans: [
          for (final item in state.plans)
            if (item.id == plan.id) plan else item,
        ],
      ),
    );
    await _persist();
  }

  Future<void> _persist() => _storage.writeMap('khatma', {
    'activeId': state.activeId,
    'plans': state.plans.map((item) => item.toJson()).toList(),
  });

  Future<void> _refreshNotificationCalendar() async {
    if (_resetting || isClosed) return;
    final service = _notifications;
    if (service == null) return;
    final settings = AppSettings.fromJson(_storage.readMap('settings'));
    if (!settings.notificationsEnabled) return;
    await service.scheduleAll(
      NotificationSchedulePlanner.build(storage: _storage, settings: settings),
    );
  }
}
