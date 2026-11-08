import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_notification_service.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/data/services/notification_schedule_planner.dart';
import '../../data/models/hifz_planning_models.dart';
import '../../data/models/memorization_item.dart';
import '../../data/models/memorization_plan.dart';
import '../../data/models/memorization_session.dart';
import '../../data/models/memorization_status.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/repositories/quran_memorization_repository.dart';
import '../services/adaptive_murajaah_engine.dart';
import 'quran_memorization_state.dart';

/// Authoritative Cubit managing Quran memorization plans, mastery progress,
/// recall sessions, revision queues, and adaptive Muraja'ah scheduling.
class QuranMemorizationCubit extends Cubit<QuranMemorizationState> {
  QuranMemorizationCubit({required this.repository, this.notificationService})
    : super(const QuranMemorizationState());

  final QuranMemorizationRepository repository;
  final LocalNotificationService? notificationService;

  static const int reminderNotificationId = 800001;
  static const int murajaahReminderNotificationId = 800002;
  static const AdaptiveMurajaahEngine engine = AdaptiveMurajaahEngine();
  final Map<String, Completer<void>> _inFlightOperations =
      <String, Completer<void>>{};
  final Set<Future<void>> _pendingWrites = {};
  int _loadRevision = 0;
  bool _resetting = false;

  void invalidatePendingOperations() {
    ++_loadRevision;
    _resetting = true;
  }

  /// Include the legacy history write in the barrier before clearing storage.
  Future<void> finishPendingWrites() async {
    while (_pendingWrites.isNotEmpty || _inFlightOperations.isNotEmpty) {
      await Future.wait(
        [
          ..._pendingWrites,
          ..._inFlightOperations.values.map((operation) => operation.future),
        ].map((future) => future.catchError((Object _) {})),
      );
    }
  }

  void resetLocalData() {
    invalidatePendingOperations();
    _resetting = false;
    emit(const QuranMemorizationState(status: QuranMemorizationStatus.ready));
  }

  /// Loads all memorization data from local-first storage.
  Future<void> load() async {
    _resetting = false;
    final revision = ++_loadRevision;
    emit(
      state.copyWith(status: QuranMemorizationStatus.loading, clearError: true),
    );
    try {
      final data = await repository.loadData();
      if (isClosed || revision != _loadRevision) return;
      emit(
        state.copyWith(
          status: QuranMemorizationStatus.ready,
          plans: data.plans,
          items: data.items,
          activeSession: data.sessionResume,
          history: data.history,
        ),
      );
    } on Object catch (e) {
      if (isClosed || revision != _loadRevision) return;
      emit(
        state.copyWith(
          status: QuranMemorizationStatus.failure,
          error: 'تعذّر تحميل بيانات الحفظ: $e',
        ),
      );
    }
  }

  /// Creates a new memorization plan with validation.
  /// If [makeActive] is true, other plans are set inactive.
  Future<MemorizationPlan> createPlan({
    required String title,
    int? surah,
    required int startGlobalAyah,
    required int endGlobalAyah,
    required int dailyTarget,
    bool makeActive = true,
    TimeOfDay? reminderTime,
  }) async {
    final start = startGlobalAyah.clamp(1, 6236);
    final end = endGlobalAyah.clamp(1, 6236);
    final safeDaily = dailyTarget.clamp(1, 100);

    final plan = MemorizationPlan(
      id: 'plan_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'خطة حفظ' : title.trim(),
      surah: surah,
      startGlobalAyah: start <= end ? start : end,
      endGlobalAyah: start <= end ? end : start,
      dailyTarget: safeDaily,
      isActive: makeActive,
      createdAt: DateTime.now(),
      reminderHour: reminderTime?.hour,
      reminderMinute: reminderTime?.minute,
    );

    final updatedPlans = state.plans.map((p) {
      if (makeActive && p.isActive) {
        return p.copyWith(isActive: false);
      }
      return p;
    }).toList();

    updatedPlans.insert(0, plan);

    emit(state.copyWith(plans: updatedPlans));
    await _persist();

    await _refreshNotificationCalendar();

    return plan;
  }

  /// Starts a plan-based session (alias for [startMemorizationSession]).
  void startPlanSession(MemorizationPlan plan) =>
      startMemorizationSession(plan: plan);

  /// Updates an existing plan.
  Future<void> updatePlan(MemorizationPlan updatedPlan) async {
    final updatedPlans = state.plans.map((p) {
      if (p.id == updatedPlan.id) return updatedPlan;
      return p;
    }).toList();

    emit(state.copyWith(plans: updatedPlans));
    await _persist();
    await _refreshNotificationCalendar();
  }

  /// Pauses an active plan.
  Future<void> pausePlan(String planId) async {
    final updatedPlans = state.plans.map((p) {
      if (p.id == planId) {
        return p.copyWith(isActive: false);
      }
      return p;
    }).toList();

    emit(state.copyWith(plans: updatedPlans));
    await _persist();
    await _refreshNotificationCalendar();
  }

  /// Resumes a plan as the primary active plan.
  Future<void> resumePlan(String planId) async {
    final updatedPlans = state.plans.map((p) {
      if (p.id == planId) {
        return p.copyWith(isActive: true);
      } else if (p.isActive) {
        return p.copyWith(isActive: false);
      }
      return p;
    }).toList();

    emit(state.copyWith(plans: updatedPlans));
    await _persist();
    await _refreshNotificationCalendar();
  }

  /// Deletes a plan permanently.
  Future<void> deletePlan(String planId) async {
    final updatedPlans = state.plans.where((p) => p.id != planId).toList();
    MemorizationSession? session = state.activeSession;
    if (session?.planId == planId) {
      session = null;
    }

    emit(
      state.copyWith(
        plans: updatedPlans,
        activeSession: session,
        clearActiveSession: session == null,
      ),
    );
    await _persist();
    await _refreshNotificationCalendar();
  }

  /// Starts or resumes a memorization session.
  void startMemorizationSession({
    MemorizationPlan? plan,
    List<int>? customQueue,
  }) {
    final targetPlan = plan ?? state.activePlan;
    final queue =
        customQueue ??
        (targetPlan != null
            ? state.todayTargetAyahs(targetPlan)
            : const <int>[]);

    if (queue.isEmpty) return;

    final session = MemorizationSession(
      planId: targetPlan?.id,
      queue: queue,
      currentIndex: 0,
      isTextHidden: true,
      sessionType: MemorizationSessionType.memorization,
      completedCount: 0,
    );

    emit(state.copyWith(activeSession: session));
    _persist();
  }

  /// Starts a targeted revision session using standard 4-tier queue or custom queue.
  void startRevisionSession({List<int>? customQueue, int limit = 15}) {
    final queue = customQueue ?? state.generateRevisionQueue(limit: limit);
    if (queue.isEmpty) return;

    final session = MemorizationSession(
      queue: queue,
      currentIndex: 0,
      isTextHidden: true,
      sessionType: MemorizationSessionType.revision,
      completedCount: 0,
    );

    emit(state.copyWith(activeSession: session));
    _persist();
  }

  /// Starts an adaptive revision session targeted by [category].
  void startAdaptiveRevisionSession({
    AdaptiveMurajaahCategory category = AdaptiveMurajaahCategory.all,
    int limit = 15,
    List<int>? customQueue,
  }) {
    final queue =
        customQueue ??
        state.generateAdaptiveQueue(category: category, limit: limit);
    if (queue.isEmpty) return;

    final session = MemorizationSession(
      queue: queue,
      currentIndex: 0,
      isTextHidden: true,
      sessionType: MemorizationSessionType.revision,
      completedCount: 0,
    );

    emit(state.copyWith(activeSession: session));
    _persist();
  }

  /// Starts a comprehensive, unified session for the entire daily journey ("وردك اليومي المقترح").
  void startDailyJourneySession({
    required DailyHifzJourney journey,
    int? manualTargetOverride,
  }) {
    final effectiveJourney = manualTargetOverride != null
        ? state.calculateDailyJourney(
            manualTargetOverride: manualTargetOverride,
          )
        : journey;

    final queue = effectiveJourney.allAyahs;
    if (queue.isEmpty) return;

    final session = MemorizationSession(
      planId: effectiveJourney.plan?.id,
      queue: queue,
      currentIndex: 0,
      isTextHidden: true,
      sessionType: effectiveJourney.hasNewHifz
          ? MemorizationSessionType.memorization
          : MemorizationSessionType.revision,
      completedCount: 0,
    );

    emit(state.copyWith(activeSession: session));
    _persist();
  }

  /// Starts a targeted session for a specific segment of the daily journey.
  void startJourneySegmentSession(
    HifzJourneySegment segment, {
    String? planId,
  }) {
    if (segment.queue.isEmpty) return;

    final session = MemorizationSession(
      planId:
          planId ??
          (segment.type == HifzJourneySegmentType.newHifz
              ? state.activePlan?.id
              : null),
      queue: segment.queue,
      currentIndex: 0,
      isTextHidden: true,
      sessionType: segment.type == HifzJourneySegmentType.newHifz
          ? MemorizationSessionType.memorization
          : MemorizationSessionType.revision,
      completedCount: 0,
    );

    emit(state.copyWith(activeSession: session));
    _persist();
  }

  /// Applies a plan adaptation suggestion, updating the plan's dailyTarget cleanly.
  Future<void> applyPlanAdaptation(PlanAdaptationSuggestion suggestion) async {
    final planIndex = state.plans.indexWhere((p) => p.id == suggestion.planId);
    if (planIndex == -1) return;

    final existingPlan = state.plans[planIndex];
    final updatedPlan = existingPlan.copyWith(
      dailyTarget: suggestion.recommendedTarget,
    );

    await updatePlan(updatedPlan);
  }

  /// Toggles visibility of Quran text in the active recall session.
  void toggleTextHidden() {
    final session = state.activeSession;
    if (session == null) return;
    emit(
      state.copyWith(
        activeSession: session.copyWith(isTextHidden: !session.isTextHidden),
      ),
    );
  }

  /// Explicitly reveals the text for the current session item.
  void revealText() {
    final session = state.activeSession;
    if (session == null || !session.isTextHidden) return;
    emit(state.copyWith(activeSession: session.copyWith(isTextHidden: false)));
  }

  /// Records an adaptive review outcome (easy, good, difficult, failed).
  ///
  /// Calculates subsequent spaced intervals, updates consecutive recall counters,
  /// creates an immutable review record, advances the active session, and checks plan completion.
  Future<void> recordReviewOutcome({
    required int globalAyah,
    required ReviewOutcome outcome,
    String? planId,
    String? sessionId,
    String? operationId,
    DateTime? now,
  }) async {
    final safeGlobal = globalAyah.clamp(1, 6236);
    final current = now ?? DateTime.now();
    final effectiveSessionId = sessionId ?? state.activeSession?.id;
    final effectiveOperationId =
        operationId ??
        (effectiveSessionId != null
            ? 'rev_${effectiveSessionId}_$safeGlobal'
            : 'rev_${current.millisecondsSinceEpoch}_$safeGlobal');

    // 1. Guard against concurrent in-flight delivery: await original operation if in flight
    final inFlight = _inFlightOperations[effectiveOperationId];
    if (inFlight != null) {
      await inFlight.future;
      return;
    }
    final completer = Completer<void>();
    completer.future.ignore();
    _inFlightOperations[effectiveOperationId] = completer;

    try {
      final session = state.activeSession;

      // 2. Idempotency ledger check: if this operation was already recorded, return safely
      final isDuplicate = state.history.any(
        (r) =>
            r.id == effectiveOperationId ||
            (effectiveSessionId != null &&
                r.sessionId == effectiveSessionId &&
                r.globalAyah == safeGlobal),
      );

      if (isDuplicate) {
        if (session != null && session.currentGlobalAyah == safeGlobal) {
          emit(
            state.copyWith(
              activeSession: session.copyWith(
                currentIndex: session.currentIndex + 1,
                isTextHidden: true,
                completedCount: session.completedCount + 1,
              ),
            ),
          );
        }
        completer.complete();
        return;
      }

      final currentItem = state.getItem(safeGlobal);

      // 3. Compute spaced interval and next review date
      final intervalCalc = engine.calculateNextInterval(
        item: currentItem,
        outcome: outcome,
        now: current,
      );

      // 4. Compute updated mistakes and status
      final mistakeDelta =
          (outcome == ReviewOutcome.difficult ||
              outcome == ReviewOutcome.failed)
          ? 1
          : 0;
      final newMistakeCount = currentItem.mistakeCount + mistakeDelta;
      final resultingStatus = outcome.resultingStatus;

      final updatedItem = currentItem.copyWith(
        status: resultingStatus,
        mistakeCount: newMistakeCount,
        lastReviewedAt: current,
        updatedAt: current,
        nextReviewAt: intervalCalc.nextReviewAt,
        intervalDays: intervalCalc.intervalDays,
        consecutiveSuccesses: intervalCalc.consecutiveSuccesses,
        lastOutcome: outcome,
      );

      final updatedItems = Map<int, MemorizationItem>.from(state.items);
      updatedItems[safeGlobal] = updatedItem;

      // 5. Create persistent review history record
      final effectivePlanId = planId ?? session?.planId;
      final record = MemorizationReviewRecord(
        id: effectiveOperationId,
        globalAyah: safeGlobal,
        planId: effectivePlanId,
        sessionId: effectiveSessionId,
        outcome: outcome,
        mistakeCount: newMistakeCount,
        reviewedAt: current,
        intervalDays: intervalCalc.intervalDays,
        previousStatus: currentItem.status,
        resultingStatus: resultingStatus,
      );

      final updatedHistory = List<MemorizationReviewRecord>.from(state.history)
        ..add(record);

      // 6. Advance session if active and targetAyah matches current
      var updatedSession = session;
      if (session != null && session.currentGlobalAyah == safeGlobal) {
        final nextIndex = session.currentIndex + 1;
        updatedSession = session.copyWith(
          currentIndex: nextIndex,
          isTextHidden: true,
          completedCount: session.completedCount + 1,
        );
      }

      // 7. Check if the associated plan is now completely memorized
      var updatedPlans = state.plans;
      if (effectivePlanId != null) {
        final planIndex = updatedPlans.indexWhere(
          (p) => p.id == effectivePlanId,
        );
        if (planIndex != -1) {
          final plan = updatedPlans[planIndex];
          var allMemorized = true;
          for (var g = plan.startGlobalAyah; g <= plan.endGlobalAyah; g++) {
            final item = updatedItems[g];
            if (item == null || item.status != MemorizationStatus.memorized) {
              allMemorized = false;
              break;
            }
          }
          if (allMemorized && !plan.isCompleted) {
            final completedPlan = plan.copyWith(
              isActive: false,
              completedAt: current,
            );
            updatedPlans = List<MemorizationPlan>.from(updatedPlans);
            updatedPlans[planIndex] = completedPlan;
          }
        }
      }

      final previousState = state;
      emit(
        state.copyWith(
          items: updatedItems,
          history: updatedHistory,
          activeSession: updatedSession,
          plans: updatedPlans,
          clearError: true,
        ),
      );

      try {
        await _persist();
        completer.complete();
      } catch (e, st) {
        // Rollback in-memory state on persistence failure so memory does not diverge from disk
        emit(
          previousState.copyWith(error: 'تعذر حفظ نتيجة التسميع على القرص: $e'),
        );
        completer.completeError(e, st);
        rethrow;
      }
    } finally {
      _inFlightOperations.remove(effectiveOperationId);
    }
  }

  /// User self-assessment: Confirmed recall ("أعرفها").
  /// Seamless backward-compatible bridge delegating to [recordReviewOutcome].
  Future<void> recordKnows([int? targetGlobalAyah]) async {
    final session = state.activeSession;
    final currentGlobal = targetGlobalAyah ?? session?.currentGlobalAyah;
    if (currentGlobal == null) return;
    await recordReviewOutcome(
      globalAyah: currentGlobal,
      outcome: ReviewOutcome.good,
      sessionId: session?.id,
    );
  }

  /// User self-assessment: Flagged difficulty ("أحتاج مراجعة").
  /// Seamless backward-compatible bridge delegating to [recordReviewOutcome].
  Future<void> recordNeedsRevision([int? targetGlobalAyah]) async {
    final session = state.activeSession;
    final currentGlobal = targetGlobalAyah ?? session?.currentGlobalAyah;
    if (currentGlobal == null) return;
    await recordReviewOutcome(
      globalAyah: currentGlobal,
      outcome: ReviewOutcome.difficult,
      sessionId: session?.id,
    );
  }

  /// Manually advances to the next Ayah in the session queue without assessment.
  void advanceSession() {
    final session = state.activeSession;
    if (session == null || session.isFinished) return;
    emit(
      state.copyWith(
        activeSession: session.copyWith(
          currentIndex: session.currentIndex + 1,
          isTextHidden: true,
        ),
      ),
    );
    _persist();
  }

  /// Goes back to previous Ayah in the session queue if index > 0.
  void previousSessionAyah() {
    final session = state.activeSession;
    if (session == null || session.currentIndex <= 0) return;
    emit(
      state.copyWith(
        activeSession: session.copyWith(
          currentIndex: session.currentIndex - 1,
          isTextHidden: true,
        ),
      ),
    );
    _persist();
  }

  /// Terminates the current active session.
  Future<void> endSession() async {
    emit(state.copyWith(clearActiveSession: true));
    await _persist();
  }

  /// Direct status override for a specific Ayah (used in Mushaf Action Sheet or tile).
  Future<void> setItemStatus(int globalAyah, MemorizationStatus status) async {
    final safeGlobal = globalAyah.clamp(1, 6236);
    final now = DateTime.now();
    final currentItem = state.getItem(safeGlobal);

    final updatedItem = currentItem.copyWith(
      status: status,
      mistakeCount: status == MemorizationStatus.needsRevision
          ? currentItem.mistakeCount + 1
          : currentItem.mistakeCount,
      lastReviewedAt: now,
      updatedAt: now,
    );

    final updatedItems = Map<int, MemorizationItem>.from(state.items);
    updatedItems[safeGlobal] = updatedItem;

    emit(state.copyWith(items: updatedItems));
    await _persist();
  }

  /// Schedules an optional daily memorization reminder notification using [LocalNotificationService].
  Future<void> scheduleDailyReminder({
    required TimeOfDay time,
    String title = 'ورد الحفظ والمراجعة',
    String body = 'حان موعد وردك اليومي من حفظ القرآن الكريم ومراجعته.',
  }) async {
    if (notificationService == null) return;
    final now = DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final notifications = [
      ScheduledAppNotification(
        id: reminderNotificationId,
        title: title,
        body: body,
        at: scheduled,
        payload: 'memorization',
        repeatsDaily: true,
        kind: AppNotificationKind.memorization,
      ),
    ];
    await notificationService!.scheduleAll(notifications);
  }

  /// Schedules an optional adaptive Muraja'ah reminder notification.
  Future<void> scheduleMurajaahReminder({
    required TimeOfDay time,
    String title = 'تنبيه المراجعة والتثبيت',
    String body = 'لديك آيات مستحقة للمراجعة اليوم لتثبيت حفظك.',
  }) async {
    if (notificationService == null) return;
    final now = DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final notifications = [
      ScheduledAppNotification(
        id: murajaahReminderNotificationId,
        title: title,
        body: body,
        at: scheduled,
        payload: 'memorization:review',
        repeatsDaily: true,
        kind: AppNotificationKind.memorization,
      ),
    ];
    await notificationService!.scheduleAll(notifications);
  }

  /// Cancels scheduled memorization reminder.
  Future<void> cancelDailyReminder() async {
    if (notificationService == null) return;
    await notificationService!.scheduleAll([
      ScheduledAppNotification(
        id: reminderNotificationId,
        title: '',
        body: '',
        at: DateTime.fromMillisecondsSinceEpoch(0),
        sound: false,
        vibrate: false,
        kind: AppNotificationKind.memorization,
      ),
    ]);
  }

  Future<void> _refreshNotificationCalendar() async {
    if (_resetting || isClosed) return;
    final service = notificationService;
    if (service == null) return;
    final settings = AppSettings.fromJson(
      repository.storage.readMap('settings'),
    );
    if (!settings.notificationsEnabled) return;
    await service.scheduleAll(
      NotificationSchedulePlanner.build(
        storage: repository.storage,
        settings: settings,
      ),
    );
  }

  Future<void> _persist() {
    final write = repository.saveData(
      plans: state.plans,
      items: state.items,
      session: state.activeSession,
      history: state.history,
    );
    _pendingWrites.add(write);
    return write.whenComplete(() => _pendingWrites.remove(write));
  }
}
