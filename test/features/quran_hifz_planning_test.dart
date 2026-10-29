import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/hifz_planning_models.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_analytics_models.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_item.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_session.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_memorization_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/hifz_planning_engine.dart';

class DummyAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();

  @override
  bool get isPlaying => false;

  @override
  Duration? get duration => null;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }
}

class DummyQuranRepository extends QuranRepository {
  DummyQuranRepository(this.data);
  final QuranData data;

  @override
  Future<QuranData> load() async => data;
}

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _store = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final val = _store[key];
    return val is Map ? Map<String, dynamic>.from(val) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final val = _store[key];
    return val is List ? List<dynamic>.from(val) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) =>
      (val(key) as num?)?.toInt() ?? fallback;

  dynamic val(String key) => _store[key];

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _store[key] = value;
  }

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranData quranData;
  final now = DateTime(2026, 10, 5, 12, 0);

  setUpAll(() async {
    quranData = await QuranRepository().load();
  });

  group('Q11 — 1. Domain Models Unit Tests', () {
    test('HifzJourneySegment provides correct labels and counts', () {
      const segment = HifzJourneySegment(
        type: HifzJourneySegmentType.dueMurajaah,
        queue: [1, 2, 3],
      );

      expect(segment.type, HifzJourneySegmentType.dueMurajaah);
      expect(segment.title, 'المراجعة المستحقة');
      expect(segment.description, contains('آيات حان موعد مراجعتها'));
      expect(segment.count, 3);
      expect(segment.isEmpty, isFalse);
      expect(segment.isNotEmpty, isTrue);

      const emptySegment = HifzJourneySegment(
        type: HifzJourneySegmentType.newHifz,
        queue: [],
      );
      expect(emptySegment.isEmpty, isTrue);
      expect(emptySegment.count, 0);
    });

    test('DailyHifzJourney calculates allAyahs, totalAyahs and targetToday correctly', () {
      final journey = DailyHifzJourney(
        segments: const [
          HifzJourneySegment(
            type: HifzJourneySegmentType.dueMurajaah,
            queue: [10, 11],
          ),
          HifzJourneySegment(
            type: HifzJourneySegmentType.weakConsolidation,
            queue: [12],
          ),
          HifzJourneySegment(
            type: HifzJourneySegmentType.newHifz,
            queue: [13, 14, 15],
          ),
        ],
        dueMurajaahQueue: const [10, 11],
        weakAyahsQueue: const [12],
        newHifzQueue: const [13, 14, 15],
        recommendedNewHifzTarget: 3,
        workloadLevel: WorkloadLevel.moderate,
        isRecoveryMode: false,
        rationaleMessage: 'ورد متوازن',
        evaluatedAt: now,
      );

      expect(journey.totalAyahs, 6);
      expect(journey.targetToday, 3);
      expect(journey.hasDueMurajaah, isTrue);
      expect(journey.hasWeakAyahs, isTrue);
      expect(journey.hasNewHifz, isTrue);
      expect(journey.isEmpty, isFalse);
      expect(journey.allAyahs, [10, 11, 12, 13, 14, 15]);

      final overridden = journey.copyWithTargetOverride(5, [
        13,
        14,
        15,
        16,
        17,
      ]);
      expect(overridden.targetToday, 5);
      expect(overridden.newHifzQueue.length, 5);
      expect(overridden.totalAyahs, 8);
    });

    test('PlanAdaptationSuggestion and CompletionForecast props equality', () {
      const suggestion = PlanAdaptationSuggestion(
        planId: 'plan_1',
        planTitle: 'سورة البقرة',
        currentTarget: 5,
        recommendedTarget: 2,
        sustainedPace: 1.8,
        reason: 'تخفيف الورد',
        actionText: 'تعديل الورد إلى 2 آيات',
      );

      expect(suggestion.planId, 'plan_1');
      expect(suggestion.recommendedTarget, 2);

      const forecast = CompletionForecast(
        targetBasedDays: 20,
        targetBasedDescription: 'حوالي 3 أسابيع',
        paceBasedDays: 30,
        paceBasedDescription: 'حوالي شهر',
        hasSufficientData: true,
      );

      expect(forecast.targetBasedDays, 20);
      expect(forecast.hasSufficientData, isTrue);
    });
  });

  group('Q11 — 2. HifzPlanningEngine Domain Logic Tests', () {
    const engine = HifzPlanningEngine();

    test('1. dueCount = 10 -> Light workload and full daily target', () {
      final items = [
        for (var i = 1; i <= 10; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)), // due
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.light);
      expect(journey.isRecoveryMode, isFalse);
      expect(journey.recommendedNewHifzTarget, 5); // Full target
      expect(journey.dueMurajaahQueue.length, 10);
    });

    test('2. dueCount = 11 -> Moderate workload and ~70% target', () {
      final items = [
        for (var i = 1; i <= 11; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.moderate);
      expect(journey.isRecoveryMode, isFalse);
      // 5 * 0.7 = 3.5 -> floor = 3
      expect(journey.recommendedNewHifzTarget, 3);
    });

    test('3. dueCount = 25 -> Moderate workload', () {
      final items = [
        for (var i = 1; i <= 25; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.moderate);
      expect(journey.recommendedNewHifzTarget, 3);
    });

    test('4. dueCount = 30 -> Moderate workload', () {
      final items = [
        for (var i = 1; i <= 30; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.moderate);
      expect(journey.recommendedNewHifzTarget, 3);
    });

    test('5. dueCount = 31 -> Heavy workload and ~40% target', () {
      final items = [
        for (var i = 1; i <= 31; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 150,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.heavy);
      // 5 * 0.4 = 2.0 -> floor = 2
      expect(journey.recommendedNewHifzTarget, 2);
    });

    test('6. urgentCount = 3 -> NOT Heavy solely because of urgent count', () {
      // 5 due items and 3 urgent items (dueCount <= 10 and urgentCount <= 3 -> Light)
      final items = [
        for (var i = 1; i <= 5; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
        for (var i = 6; i <= 8; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 3,
            updatedAt: now,
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.light);
      expect(journey.recommendedNewHifzTarget, 5);
    });

    test('7. urgentCount = 4 -> Heavy workload', () {
      final items = [
        for (var i = 1; i <= 5; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
        for (var i = 6; i <= 9; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 3,
            updatedAt: now,
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 50,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 3)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.workloadLevel, WorkloadLevel.heavy);
      expect(journey.recommendedNewHifzTarget, 2);
    });

    test('8. Capacity formula: verify 0.7 * P_actual + 0.3 * T_target + W_base with clamp 5..50', () {
      // Normal case: P_actual = 6.0, T_target = 6, W_base = 10
      // 0.7 * 6.0 + 0.3 * 6 = 4.2 + 1.8 = 6.0 -> round = 6 + 10 = 16
      final normalCap = engine.calculateDailyCapacity(
        actualPace: 6.0,
        target: 6,
        reviewWorkloadBase: 10,
        historyCount: 10,
        planAgeDays: 5,
        dueReviewsCount: 10,
      );
      expect(normalCap, 16);

      // Clamp lower bound: 0.7 * 0 + 0.3 * 1 = 0.3 -> round = 0 + 1 = 1 -> clamp(5, 50) = 5
      final lowerClamped = engine.calculateDailyCapacity(
        actualPace: 0.0,
        target: 1,
        reviewWorkloadBase: 1,
        historyCount: 10,
        planAgeDays: 5,
        dueReviewsCount: 1,
      );
      expect(lowerClamped, 5);

      // Clamp upper bound: 0.7 * 50 + 0.3 * 30 = 35 + 9 = 44 + 40 = 84 -> clamp(5, 50) = 50
      final upperClamped = engine.calculateDailyCapacity(
        actualPace: 50.0,
        target: 30,
        reviewWorkloadBase: 40,
        historyCount: 10,
        planAgeDays: 5,
        dueReviewsCount: 40,
      );
      expect(upperClamped, 50);
    });

    test('9. Insufficient-data fallback: dailyTarget + dueReviewsCount', () {
      // Case A: history < 5
      final historyFallback = engine.calculateDailyCapacity(
        actualPace: 10.0,
        target: 5,
        reviewWorkloadBase: 12,
        historyCount: 3,
        planAgeDays: 5,
        dueReviewsCount: 12,
      );
      expect(historyFallback, 17); // 5 + 12

      // Case B: planAgeDays < 2
      final planAgeFallback = engine.calculateDailyCapacity(
        actualPace: 10.0,
        target: 7,
        reviewWorkloadBase: 8,
        historyCount: 10,
        planAgeDays: 1,
        dueReviewsCount: 8,
      );
      expect(planAgeFallback, 15); // 7 + 8
    });

    test('Triggers Gentle Recovery Mode when overdue reviews >= 15', () {
      final items = [
        for (var i = 1; i <= 20; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now.subtract(const Duration(days: 10)),
            nextReviewAt: now.subtract(
              const Duration(days: 5),
            ), // > 24 hours overdue
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 100,
        endGlobalAyah: 200,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 10)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.isRecoveryMode, isTrue);
      expect(journey.recoveryBacklogCount, 20);
      // Bounded slice: max 15 due reviews
      expect(journey.dueMurajaahQueue.length, lessThanOrEqualTo(15));
      // Gentle new Hifz throttled to max 2 Ayahs
      expect(journey.recommendedNewHifzTarget, lessThanOrEqualTo(2));
      expect(journey.rationaleMessage, contains('وضع التعويض الهادئ'));
    });

    test('Triggers Gentle Recovery Mode on inactivity >= 3 days with pending overdue reviews', () {
      final items = [
        for (var i = 1; i <= 3; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now.subtract(const Duration(days: 5)),
            nextReviewAt: now.subtract(const Duration(days: 3)), // overdue
          ),
      ];

      final history = [
        MemorizationReviewRecord(
          id: 'rev_1',
          globalAyah: 1,
          outcome: ReviewOutcome.good,
          mistakeCount: 0,
          reviewedAt: now.subtract(const Duration(days: 4)), // 4 days inactive
        ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 100,
        endGlobalAyah: 150,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 10)),
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: history,
        activePlan: plan,
        now: now,
      );

      expect(journey.isRecoveryMode, isTrue);
    });

    test(
      'Enforces strict deduplication across due, weak, and new segments',
      () {
        // Ayah 5 is both due and marked needsRevision
        final items = [
          MemorizationItem(
            globalAyah: 5,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 4,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 3)), // due
          ),
          MemorizationItem(
            globalAyah: 6,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 3,
            updatedAt: now,
          ),
        ];

        final plan = MemorizationPlan(
          id: 'plan_test',
          title: 'خطة حفظ',
          startGlobalAyah: 5,
          endGlobalAyah: 10,
          dailyTarget: 3,
          createdAt: now,
        );

        final journey = engine.calculateDailyJourney(
          items: items,
          history: [],
          activePlan: plan,
          now: now,
        );

        // Ayah 5 is in due queue
        expect(journey.dueMurajaahQueue.contains(5), isTrue);
        // Ayah 5 MUST NOT appear in weak queue
        expect(journey.weakAyahsQueue.contains(5), isFalse);
        // Ayah 5 MUST NOT appear in new Hifz queue
        expect(journey.newHifzQueue.contains(5), isFalse);

        // Entire journey queue must be completely unique
        final all = journey.allAyahs;
        expect(all.toSet().length, all.length);
      },
    );

    test('Enforces strict global capacity bounding (<= 30 Ayahs total)', () {
      final items = [
        for (var i = 1; i <= 60; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 2,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 2)),
          ),
      ];

      final plan = MemorizationPlan(
        id: 'plan_test',
        title: 'خطة حفظ',
        startGlobalAyah: 100,
        endGlobalAyah: 200,
        dailyTarget: 10,
        createdAt: now,
      );

      final journey = engine.calculateDailyJourney(
        items: items,
        history: [],
        activePlan: plan,
        now: now,
      );

      expect(journey.totalAyahs, lessThanOrEqualTo(30));
    });

    test('Plan adaptation suggestion: suggests reduction when sustained pace <= 55% of target', () {
      final plan = MemorizationPlan(
        id: 'plan_divergent',
        title: 'خطة مكثفة',
        startGlobalAyah: 1,
        endGlobalAyah: 100,
        dailyTarget: 6,
        createdAt: now.subtract(const Duration(days: 10)), // 10 days old
      );

      // Only 10 Ayahs memorized over 10 days (pace = 1.0/day vs target 6)
      final items = [
        for (var i = 1; i <= 10; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
          ),
      ];

      final history = [
        for (var d = 1; d <= 7; d++)
          MemorizationReviewRecord(
            id: 'rev_$d',
            globalAyah: d,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now.subtract(Duration(days: d)),
          ),
      ];

      final suggestion = engine.calculatePlanAdaptationSuggestion(
        plan: plan,
        items: items,
        history: history,
        now: now,
      );

      expect(suggestion, isNotNull);
      expect(suggestion!.currentTarget, 6);
      expect(suggestion.recommendedTarget, 1);
      expect(suggestion.reason, contains('وتيرة إنجازك الفعلية'));
    });

    test('12. Realistic completion: planAgeDays = 6 -> unavailable, planAgeDays = 7 -> available when progress > 0', () {
      final items = [
        for (var i = 1; i <= 20; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
          ),
      ];

      // Case A: planAgeDays = 6 -> unavailable
      final plan6Days = MemorizationPlan(
        id: 'plan_6',
        title: 'خطة 6 أيام',
        startGlobalAyah: 1,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 6)),
      );

      final forecast6 = engine.estimateRealisticCompletion(
        plan: plan6Days,
        items: items,
        history: [],
        now: now,
      );

      expect(forecast6.hasSufficientData, isFalse);
      expect(forecast6.paceBasedDays, isNull);
      expect(forecast6.targetBasedDays, 16); // 80 / 5 = 16

      // Case B: planAgeDays = 7 -> available when progress > 0
      final plan7Days = MemorizationPlan(
        id: 'plan_7',
        title: 'خطة 7 أيام',
        startGlobalAyah: 1,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 7)),
      );

      final forecast7 = engine.estimateRealisticCompletion(
        plan: plan7Days,
        items: items,
        history: [],
        now: now,
      );

      expect(forecast7.hasSufficientData, isTrue);
      expect(forecast7.paceBasedDays, isNotNull);
      expect(forecast7.targetBasedDays, 16);
    });

    test('Completion forecast calculates humanized Arabic timelines', () {
      final plan = MemorizationPlan(
        id: 'plan_forecast',
        title: 'خطة تجريبية',
        startGlobalAyah: 1,
        endGlobalAyah: 100,
        dailyTarget: 5,
        createdAt: now.subtract(const Duration(days: 8)),
      );

      // 40 memorized, 60 remaining -> 60 / 5 = 12 days
      final items = [
        for (var i = 1; i <= 40; i++)
          MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
          ),
      ];

      final history = [
        for (var d = 1; d <= 8; d++)
          MemorizationReviewRecord(
            id: 'rev_$d',
            globalAyah: d,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now.subtract(Duration(days: d)),
          ),
      ];

      final forecast = engine.estimateRealisticCompletion(
        plan: plan,
        items: items,
        history: history,
        now: now,
      );

      expect(forecast.targetBasedDays, 12);
      expect(forecast.targetBasedDescription, contains('حوالي أسبوعين'));
      expect(forecast.hasSufficientData, isTrue);
      expect(forecast.paceBasedDays, isNotNull);
    });
  });

  group('Q11 — 3. Cubit & State Integration Tests', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository repository;
    late QuranMemorizationCubit cubit;

    setUp(() {
      storage = InMemoryLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
      cubit = QuranMemorizationCubit(repository: repository);
    });

    tearDown(() async {
      await cubit.close();
    });

    test('calculateDailyJourney, calculatePlanAdaptationSuggestion and forecast on state', () async {
      final plan = await cubit.createPlan(
        title: 'خطة الكهف',
        startGlobalAyah: 2141,
        endGlobalAyah: 2250,
        dailyTarget: 5,
      );

      final journey = cubit.state.calculateDailyJourney(now: now);
      expect(journey.plan?.id, plan.id);
      expect(journey.recommendedNewHifzTarget, 5);
      expect(journey.newHifzQueue.length, 5);

      final forecast = cubit.state.calculateCompletionForecast(plan, now: now);
      expect(forecast.targetBasedDays, greaterThan(0));

      final suggestion = cubit.state.calculatePlanAdaptationSuggestion(
        now: now,
      );
      // Fresh plan -> null
      expect(suggestion, isNull);
    });

    test('startDailyJourneySession initializes full unified session', () async {
      await cubit.createPlan(
        title: 'خطة البقرة',
        startGlobalAyah: 1,
        endGlobalAyah: 10,
        dailyTarget: 3,
      );

      final journey = cubit.state.calculateDailyJourney(now: now);
      cubit.startDailyJourneySession(journey: journey);

      expect(cubit.state.activeSession, isNotNull);
      expect(cubit.state.activeSession!.queue, journey.allAyahs);
      expect(cubit.state.activeSession!.currentIndex, 0);
      expect(cubit.state.activeSession!.isTextHidden, isTrue);
    });

    test('startJourneySegmentSession starts only selected segment', () async {
      await cubit.createPlan(
        title: 'خطة البقرة',
        startGlobalAyah: 1,
        endGlobalAyah: 10,
        dailyTarget: 3,
      );

      final journey = cubit.state.calculateDailyJourney(now: now);
      final newSegment = journey.segments.firstWhere(
        (s) => s.type == HifzJourneySegmentType.newHifz,
      );

      cubit.startJourneySegmentSession(newSegment);
      expect(cubit.state.activeSession, isNotNull);
      expect(cubit.state.activeSession!.queue, newSegment.queue);
      expect(
        cubit.state.activeSession!.sessionType,
        MemorizationSessionType.memorization,
      );
    });

    test('applyPlanAdaptation updates plan target cleanly', () async {
      final plan = await cubit.createPlan(
        title: 'خطة البقرة',
        startGlobalAyah: 1,
        endGlobalAyah: 100,
        dailyTarget: 6,
      );

      final suggestion = PlanAdaptationSuggestion(
        planId: plan.id,
        planTitle: plan.title,
        currentTarget: 6,
        recommendedTarget: 3,
        sustainedPace: 2.7,
        reason: 'تخفيف الورد',
        actionText: 'تعديل الورد إلى 3 آيات',
      );

      await cubit.applyPlanAdaptation(suggestion);

      final updated = cubit.state.activePlan;
      expect(updated?.dailyTarget, 3);
    });
  });

  group('Q11 — 4. UI Widget Smoke Tests', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository memorizationRepo;
    late QuranMemorizationCubit memorizationCubit;
    late QuranCubit quranCubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      memorizationRepo = QuranMemorizationRepository(storage: storage);
      memorizationCubit = QuranMemorizationCubit(repository: memorizationRepo);
      quranCubit = QuranCubit(
        storage: storage,
        repository: DummyQuranRepository(quranData),
        audio: DummyAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await quranCubit.load();
    });

    tearDown(() async {
      await memorizationCubit.close();
      await quranCubit.close();
    });

    testWidgets(
      'QuranMemorizationPage renders Daily Journey Card and segments',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await memorizationCubit.createPlan(
          title: 'خطة سورة الفاتحة',
          startGlobalAyah: 1,
          endGlobalAyah: 7,
          dailyTarget: 3,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<QuranCubit>.value(value: quranCubit),
                BlocProvider<QuranMemorizationCubit>.value(
                  value: memorizationCubit,
                ),
              ],
              child: const QuranMemorizationPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify Daily Journey Card header
        expect(find.text('وردك اليومي المقترح'), findsOneWidget);
        // Verify segment chips
        expect(find.text('المراجعة المستحقة'), findsOneWidget);
        expect(find.text('تثبيت المواضع الضعيفة'), findsOneWidget);
        expect(find.text('الحفظ الجديد'), findsOneWidget);
        // Verify Start unified journey button
        expect(find.textContaining('ابدأ ورد اليوم المتكامل'), findsOneWidget);
      },
    );

    testWidgets(
      'QuranMemorizationPage renders Recovery Mode banner when triggered',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Seed 16 overdue items to trigger recovery mode
        for (var i = 1; i <= 16; i++) {
          await memorizationCubit.recordReviewOutcome(
            globalAyah: i,
            outcome: ReviewOutcome.failed,
            now: now.subtract(const Duration(days: 5)),
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<QuranCubit>.value(value: quranCubit),
                BlocProvider<QuranMemorizationCubit>.value(
                  value: memorizationCubit,
                ),
              ],
              child: const QuranMemorizationPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify Recovery Mode badge/indicator
        expect(find.text('وضع التعويض الهادئ'), findsWidgets);
      },
    );
  });
}
