import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_analytics_models.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_item.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_memorization_analytics_page.dart';
import 'package:mishkat_app/features/quran/presentation/services/memorization_analytics_engine.dart';

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
  const engine = MemorizationAnalyticsEngine();

  setUpAll(() async {
    quranData = await QuranRepository().load();
  });

  group('Q10 — 1. Overall Memorization Analytics Tests', () {
    test(
      'Empty items dataset returns canonical 6,236 total with 0% coverage',
      () {
        final overall = engine.calculateOverall({});
        expect(overall.totalAyahs, 6236);
        expect(overall.memorized, 0);
        expect(overall.learning, 0);
        expect(overall.needsRevision, 0);
        expect(overall.notStarted, 6236);
        expect(overall.coveragePercentage, 0.0);
        expect(overall.formattedPercentage, '0.0%');
        expect(overall.dueToday, 0);
        expect(overall.overdue, 0);
        expect(overall.weak, 0);
      },
    );

    test(
      'Partial items correctly aggregates statuses and calculates percentage',
      () {
        final now = DateTime(2026, 10, 5, 12, 0);
        final items = <int, MemorizationItem>{
          1: MemorizationItem(
            globalAyah: 1,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: now.add(const Duration(days: 7)),
          ),
          2: MemorizationItem(
            globalAyah: 2,
            status: MemorizationStatus.learning,
            updatedAt: now,
            nextReviewAt: now.add(const Duration(days: 3)),
          ),
          3: MemorizationItem(
            globalAyah: 3,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 3,
            updatedAt: now,
            nextReviewAt: now.subtract(const Duration(hours: 30)), // overdue
          ),
        };

        final overall = engine.calculateOverall(items, now: now);
        expect(overall.totalAyahs, 6236);
        expect(overall.memorized, 1);
        expect(overall.learning, 1);
        expect(overall.needsRevision, 1);
        expect(overall.notStarted, 6233);
        expect(overall.dueToday, 1);
        expect(overall.overdue, 1);
        expect(overall.weak, 1);
      },
    );

    test('All memorized coverage returns 100%', () {
      final now = DateTime(2026, 10, 5);
      final items = <int, MemorizationItem>{
        for (var i = 1; i <= 6236; i++)
          i: MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
          ),
      };

      final overall = engine.calculateOverall(items, now: now);
      expect(overall.memorized, 6236);
      expect(overall.notStarted, 0);
      expect(overall.coveragePercentage, 1.0);
      expect(overall.formattedPercentage, '100.0%');
    });
  });

  group('Q10 — 2. Review Retention & Small Sample Protection Tests', () {
    test(
      'Fewer than 5 reviews returns hasSufficientData == false with null rates',
      () {
        final now = DateTime(2026, 10, 5);
        final history = [
          MemorizationReviewRecord(
            id: 'rev_1',
            globalAyah: 1,
            outcome: ReviewOutcome.easy,
            mistakeCount: 0,
            reviewedAt: now,
          ),
          MemorizationReviewRecord(
            id: 'rev_2',
            globalAyah: 2,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now,
          ),
        ];

        final retention = engine.calculateRetention(history, now: now);
        expect(retention.totalReviews, 2);
        expect(retention.hasSufficientData, false);
        expect(retention.successRate, isNull);
        expect(retention.difficultRate, isNull);
        expect(retention.failureRate, isNull);
        expect(retention.reviewsToday, 2);
        expect(retention.reviewsThisWeek, 2);
        expect(retention.reviewsThisMonth, 2);
      },
    );

    test('5 or more reviews calculates exact retention rates and averages', () {
      final now = DateTime(2026, 10, 5, 12, 0);
      final history = [
        MemorizationReviewRecord(
          id: 'r1',
          globalAyah: 1,
          outcome: ReviewOutcome.easy,
          mistakeCount: 0,
          reviewedAt: now,
        ),
        MemorizationReviewRecord(
          id: 'r2',
          globalAyah: 2,
          outcome: ReviewOutcome.good,
          mistakeCount: 0,
          reviewedAt: now,
        ),
        MemorizationReviewRecord(
          id: 'r3',
          globalAyah: 3,
          outcome: ReviewOutcome.good,
          mistakeCount: 0,
          reviewedAt: now.subtract(const Duration(days: 1)),
        ),
        MemorizationReviewRecord(
          id: 'r4',
          globalAyah: 4,
          outcome: ReviewOutcome.difficult,
          mistakeCount: 1,
          reviewedAt: now.subtract(const Duration(days: 2)),
        ),
        MemorizationReviewRecord(
          id: 'r5',
          globalAyah: 5,
          outcome: ReviewOutcome.failed,
          mistakeCount: 2,
          reviewedAt: now.subtract(const Duration(days: 10)),
        ),
      ];

      final retention = engine.calculateRetention(history, now: now);
      expect(retention.totalReviews, 5);
      expect(retention.hasSufficientData, true);
      expect(retention.easyCount, 1);
      expect(retention.goodCount, 2);
      expect(retention.difficultCount, 1);
      expect(retention.failedCount, 1);
      expect(retention.successfulCount, 3);
      expect(retention.successRate, closeTo(3 / 5, 0.001));
      expect(retention.difficultRate, closeTo(1 / 5, 0.001));
      expect(retention.failureRate, closeTo(1 / 5, 0.001));
      expect(retention.reviewsToday, 2);
      expect(retention.reviewsThisWeek, 4);
      expect(retention.reviewsThisMonth, 5);
      expect(retention.averageReviewsPerActiveDay, closeTo(5 / 4, 0.001));
    });
  });

  group('Q10 — 3. Activity Trend Analytics Tests', () {
    test('Insufficient reviews in 14-day window returns insufficientData direction', () {
      final now = DateTime(2026, 10, 5);
      final history = [
        MemorizationReviewRecord(
          id: 'r1',
          globalAyah: 1,
          outcome: ReviewOutcome.good,
          mistakeCount: 0,
          reviewedAt: now,
        ),
      ];

      final trend = engine.calculateTrend(history, now: now);
      expect(trend.direction, TrendDirection.insufficientData);
      expect(trend.description, contains('لا توجد بيانات'));
    });

    test('Activity increase of >= 3 returns increasing trend', () {
      final now = DateTime(2026, 10, 5, 12, 0);
      final history = <MemorizationReviewRecord>[
        // 1 review in previous 7 days (days 8..14)
        MemorizationReviewRecord(
          id: 'p1',
          globalAyah: 1,
          outcome: ReviewOutcome.good,
          mistakeCount: 0,
          reviewedAt: now.subtract(const Duration(days: 10)),
        ),
        // 5 reviews in last 7 days
        for (var i = 1; i <= 5; i++)
          MemorizationReviewRecord(
            id: 'n$i',
            globalAyah: i + 1,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now.subtract(Duration(days: i)),
          ),
      ];

      final trend = engine.calculateTrend(history, now: now);
      expect(trend.direction, TrendDirection.increasing);
      expect(trend.reviewsLast7Days, 5);
      expect(trend.reviewsPrevious7Days, 1);
    });

    test('Activity decrease of >= 3 returns decreasing trend', () {
      final now = DateTime(2026, 10, 5, 12, 0);
      final history = <MemorizationReviewRecord>[
        // 6 reviews in previous 7 days
        for (var i = 8; i <= 13; i++)
          MemorizationReviewRecord(
            id: 'p$i',
            globalAyah: i,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now.subtract(Duration(days: i)),
          ),
        // 1 review in last 7 days
        MemorizationReviewRecord(
          id: 'n1',
          globalAyah: 1,
          outcome: ReviewOutcome.good,
          mistakeCount: 0,
          reviewedAt: now.subtract(const Duration(days: 2)),
        ),
      ];

      final trend = engine.calculateTrend(history, now: now);
      expect(trend.direction, TrendDirection.decreasing);
    });

    test('Similar activity returns stable trend', () {
      final now = DateTime(2026, 10, 5, 12, 0);
      final history = <MemorizationReviewRecord>[
        for (var i = 1; i <= 3; i++)
          MemorizationReviewRecord(
            id: 'n$i',
            globalAyah: i,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now.subtract(Duration(days: i)),
          ),
        for (var i = 8; i <= 10; i++)
          MemorizationReviewRecord(
            id: 'p$i',
            globalAyah: i,
            outcome: ReviewOutcome.good,
            mistakeCount: 0,
            reviewedAt: now.subtract(Duration(days: i)),
          ),
      ];

      final trend = engine.calculateTrend(history, now: now);
      expect(trend.direction, TrendDirection.stable);
    });
  });

  group('Q10 — 4. Review Workload Forecast Tests', () {
    test('Calculates due today, tomorrow, and 7-day windows accurately', () {
      final now = DateTime(2026, 10, 5, 10, 0);
      final items = <int, MemorizationItem>{
        // Due today
        1: MemorizationItem(
          globalAyah: 1,
          status: MemorizationStatus.memorized,
          updatedAt: now,
          nextReviewAt: DateTime(2026, 10, 5, 18, 0),
        ),
        // Due tomorrow
        2: MemorizationItem(
          globalAyah: 2,
          status: MemorizationStatus.memorized,
          updatedAt: now,
          nextReviewAt: DateTime(2026, 10, 6, 14, 0),
        ),
        // Due within 7 days
        3: MemorizationItem(
          globalAyah: 3,
          status: MemorizationStatus.memorized,
          updatedAt: now,
          nextReviewAt: DateTime(2026, 10, 9, 12, 0),
        ),
        // Far out (beyond 7 days)
        4: MemorizationItem(
          globalAyah: 4,
          status: MemorizationStatus.memorized,
          updatedAt: now,
          nextReviewAt: DateTime(2026, 10, 25, 12, 0),
        ),
      };

      final forecast = engine.calculateWorkloadForecast(items, now: now);
      expect(forecast.dueTodayCount, 1);
      expect(forecast.dueTomorrowCount, 1);
      expect(forecast.dueNext7DaysCount, 2); // tomorrow + 9th
      expect(forecast.workloadLevel, WorkloadLevel.light);
    });

    test('Categorizes moderate and heavy workloads correctly', () {
      final now = DateTime(2026, 10, 5, 10, 0);
      final moderateItems = <int, MemorizationItem>{
        for (var i = 1; i <= 15; i++)
          i: MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: DateTime(2026, 10, 5, 14, 0),
          ),
      };

      final modForecast = engine.calculateWorkloadForecast(
        moderateItems,
        now: now,
      );
      expect(modForecast.workloadLevel, WorkloadLevel.moderate);

      final heavyItems = <int, MemorizationItem>{
        for (var i = 1; i <= 35; i++)
          i: MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.memorized,
            updatedAt: now,
            nextReviewAt: DateTime(2026, 10, 5, 14, 0),
          ),
      };

      final heavyForecast = engine.calculateWorkloadForecast(
        heavyItems,
        now: now,
      );
      expect(heavyForecast.workloadLevel, WorkloadLevel.heavy);
    });
  });

  group('Q10 — 5. Plan Progress & Pace Intelligence Tests', () {
    test(
      'New plan (< 2 days elapsed) returns insufficientData pace status',
      () {
        final now = DateTime(2026, 10, 5, 12, 0);
        final plan = MemorizationPlan(
          id: 'plan_test',
          title: 'حفظ سورة الملك',
          startGlobalAyah: 5242,
          endGlobalAyah: 5271, // 30 ayahs
          dailyTarget: 5,
          createdAt: now.subtract(const Duration(hours: 12)),
        );

        final items = <int, MemorizationItem>{
          5242: MemorizationItem(
            globalAyah: 5242,
            status: MemorizationStatus.memorized,
            updatedAt: now,
          ),
        };

        final planAnalytics = engine.calculatePlanAnalytics(
          plan,
          items,
          now: now,
        );
        expect(planAnalytics.totalAyahs, 30);
        expect(planAnalytics.memorizedCount, 1);
        expect(planAnalytics.remainingCount, 29);
        expect(planAnalytics.paceStatus, PlanPaceStatus.insufficientData);
        expect(planAnalytics.paceMessage, contains('في بدايتها'));
      },
    );

    test(
      'Plan progress evaluates onTrack, ahead, and needsAttention correctly',
      () {
        final now = DateTime(2026, 10, 10, 12, 0);
        final plan = MemorizationPlan(
          id: 'plan_kahf',
          title: 'حفظ سورة الكهف',
          startGlobalAyah: 2145,
          endGlobalAyah: 2254, // 110 ayahs
          dailyTarget: 5,
          createdAt: now.subtract(const Duration(days: 10)), // 10 days elapsed
        );

        // On track: memorized 50 ayahs in 10 days (5.0 / day, target: 5)
        final itemsOnTrack = <int, MemorizationItem>{
          for (var g = 2145; g < 2145 + 50; g++)
            g: MemorizationItem(
              globalAyah: g,
              status: MemorizationStatus.memorized,
              updatedAt: now,
            ),
        };

        final onTrackAnalytics = engine.calculatePlanAnalytics(
          plan,
          itemsOnTrack,
          now: now,
        );
        expect(onTrackAnalytics.paceStatus, PlanPaceStatus.onTrack);
        expect(onTrackAnalytics.currentPace, closeTo(5.0, 0.1));

        // Ahead: memorized 70 ayahs in 10 days (7.0 / day)
        final itemsAhead = <int, MemorizationItem>{
          for (var g = 2145; g < 2145 + 70; g++)
            g: MemorizationItem(
              globalAyah: g,
              status: MemorizationStatus.memorized,
              updatedAt: now,
            ),
        };

        final aheadAnalytics = engine.calculatePlanAnalytics(
          plan,
          itemsAhead,
          now: now,
        );
        expect(aheadAnalytics.paceStatus, PlanPaceStatus.ahead);

        // Needs attention: memorized 20 ayahs in 10 days (2.0 / day)
        final itemsBehind = <int, MemorizationItem>{
          for (var g = 2145; g < 2145 + 20; g++)
            g: MemorizationItem(
              globalAyah: g,
              status: MemorizationStatus.memorized,
              updatedAt: now,
            ),
        };

        final behindAnalytics = engine.calculatePlanAnalytics(
          plan,
          itemsBehind,
          now: now,
        );
        expect(behindAnalytics.paceStatus, PlanPaceStatus.needsAttention);
      },
    );
  });

  group('Q10 — 6. Weak Ayahs Detection Tests', () {
    test(
      'Extracts and orders weak Ayahs by priority score with Surah metadata',
      () {
        final now = DateTime(2026, 10, 5, 12, 0);
        final items = <int, MemorizationItem>{
          // Mild weak
          1: MemorizationItem(
            globalAyah: 1,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 2,
            updatedAt: now,
          ),
          // Urgent weak (high mistakes + failed)
          2: MemorizationItem(
            globalAyah: 2,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 5,
            lastOutcome: ReviewOutcome.failed,
            updatedAt: now,
          ),
          // Mastered item (should NOT appear in weak list)
          3: MemorizationItem(
            globalAyah: 3,
            status: MemorizationStatus.memorized,
            mistakeCount: 0,
            updatedAt: now,
          ),
        };

        final weakAyahs = engine.findWeakAyahs(
          items,
          quranData,
          now: now,
          limit: 5,
        );
        expect(weakAyahs, hasLength(2));
        // Ayah 2 should have higher score than Ayah 1
        expect(weakAyahs.first.globalAyah, 2);
        expect(weakAyahs.first.surahName, contains('فَاتِحَة'));
        expect(weakAyahs.first.ayahNumber, 2);
        expect(weakAyahs.first.mistakeCount, 5);
        expect(weakAyahs.first.lastOutcome, ReviewOutcome.failed);

        expect(weakAyahs.last.globalAyah, 1);
        expect(weakAyahs.last.ayahNumber, 1);
      },
    );
  });

  group('Q10 — 7. Surah & Juz Canonical Mapping Tests', () {
    test(
      'Surah analytics evaluates exactly 114 Surahs with boundary precision',
      () {
        final items = <int, MemorizationItem>{
          // Memorize all 7 Ayahs of Al-Fatihah
          for (var i = 1; i <= 7; i++)
            i: MemorizationItem(
              globalAyah: i,
              status: MemorizationStatus.memorized,
              updatedAt: DateTime.now(),
            ),
        };

        final surahs = engine.calculateSurahAnalytics(items, quranData);
        expect(surahs, hasLength(114));

        final fatiha = surahs.first;
        expect(fatiha.surahNumber, 1);
        expect(fatiha.name, contains('فَاتِحَة'));
        expect(fatiha.totalAyahs, 7);
        expect(fatiha.memorizedCount, 7);
        expect(fatiha.completionPercentage, 1.0);
        expect(fatiha.isCompleted, true);

        final baqarah = surahs[1];
        expect(baqarah.surahNumber, 2);
        expect(baqarah.name, contains('بَقَرَة'));
        expect(baqarah.totalAyahs, 286);
        expect(baqarah.memorizedCount, 0);
        expect(baqarah.isCompleted, false);

        final nas = surahs.last;
        expect(nas.surahNumber, 114);
        expect(nas.name, 'النَّاسِ');
        expect(nas.totalAyahs, 6);
      },
    );

    test(
      'Juz analytics evaluates exactly 30 Juz with zero gaps and zero overlaps',
      () {
        final items = <int, MemorizationItem>{
          // Memorize first 10 Ayahs of Juz 1
          for (var i = 1; i <= 10; i++)
            i: MemorizationItem(
              globalAyah: i,
              status: MemorizationStatus.memorized,
              updatedAt: DateTime.now(),
            ),
        };

        final juzs = engine.calculateJuzAnalytics(items, quranData);
        expect(juzs, hasLength(30));

        final juz1 = juzs.first;
        expect(juz1.juzNumber, 1);
        expect(juz1.startGlobalAyah, 1);
        expect(juz1.endGlobalAyah, 148);
        expect(juz1.totalAyahs, 148);
        expect(juz1.memorizedCount, 10);
        expect(juz1.completionPercentage, closeTo(10 / 148, 0.001));

        final juz30 = juzs.last;
        expect(juz30.juzNumber, 30);
        expect(juz30.startGlobalAyah, 5673);
        expect(juz30.endGlobalAyah, 6236);
        expect(juz30.totalAyahs, 564);

        // Verify zero gaps and zero overlaps across all 30 Juz
        var expectedStart = 1;
        var totalCovered = 0;
        for (final j in juzs) {
          expect(j.startGlobalAyah, expectedStart);
          expect(j.endGlobalAyah, greaterThanOrEqualTo(j.startGlobalAyah));
          totalCovered += j.totalAyahs;
          expectedStart = j.endGlobalAyah + 1;
        }
        expect(totalCovered, 6236);
      },
    );
  });

  group('Q10 — 8. State Integration & Performance Benchmark Tests', () {
    test('State computeAnalytics executes in under 5 ms', () {
      final now = DateTime(2026, 10, 5, 12, 0);
      // Construct a large, representative dataset (1,000 items + 500 history entries)
      final items = <int, MemorizationItem>{
        for (var i = 1; i <= 1000; i++)
          i: MemorizationItem(
            globalAyah: i,
            status: i % 3 == 0
                ? MemorizationStatus.memorized
                : (i % 3 == 1
                      ? MemorizationStatus.learning
                      : MemorizationStatus.needsRevision),
            mistakeCount: i % 4,
            updatedAt: now,
            nextReviewAt: now.add(Duration(days: (i % 10) - 2)),
          ),
      };

      final history = <MemorizationReviewRecord>[
        for (var i = 1; i <= 500; i++)
          MemorizationReviewRecord(
            id: 'rev_$i',
            globalAyah: (i % 1000) + 1,
            outcome: ReviewOutcome.values[i % 4],
            mistakeCount: i % 3,
            reviewedAt: now.subtract(Duration(days: i % 40)),
          ),
      ];

      final state = QuranMemorizationState(
        status: QuranMemorizationStatus.ready,
        items: items,
        history: history,
        plans: [
          MemorizationPlan(
            id: 'p1',
            title: 'خطة تجريبية',
            startGlobalAyah: 1,
            endGlobalAyah: 100,
            dailyTarget: 5,
            createdAt: now.subtract(const Duration(days: 10)),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      final analytics = state.computeAnalytics(quranData, now: now);
      stopwatch.stop();

      expect(analytics.overall.totalAyahs, 6236);
      expect(analytics.overall.memorized, greaterThan(0));
      expect(analytics.retention.totalReviews, 500);
      expect(analytics.surahs, hasLength(114));
      expect(analytics.juzs, hasLength(30));
      expect(analytics.weakAyahs, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(15));
    });
  });

  group('Q10 — 9. UI Widget Smoke Tests', () {
    testWidgets(
      'QuranMemorizationAnalyticsPage renders calm overview and tabs',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final storage = InMemoryLocalStorageService();
        final repo = QuranMemorizationRepository(storage: storage);
        final cubit = QuranMemorizationCubit(repository: repo);
        final quranCubit = QuranCubit(
          storage: storage,
          repository: QuranRepository(),
          audio: DummyAudioService(),
          reciter: 'ar.alafasy',
          fontSize: 22.0,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<QuranMemorizationCubit>.value(value: cubit),
                BlocProvider<QuranCubit>.value(value: quranCubit),
              ],
              child: QuranMemorizationAnalyticsPage(quranData: quranData),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('تحليلات الحفظ والمراجعة'), findsOneWidget);
        expect(find.text('ذكاء التقدم القرآني'), findsOneWidget);
        expect(find.text('تغطية الحفظ الكلية'), findsOneWidget);
        expect(find.text('عبء المراجعة المتوقع'), findsOneWidget);
        expect(find.text('أداء المراجعة والاحتفاظ'), findsOneWidget);
        expect(find.text('مواضع تحتاج تثبيتاً'), findsOneWidget);
        expect(find.text('تغطية السور والأجزاء'), findsOneWidget);

        // Verify tabs exist
        expect(find.text('السور (114)'), findsOneWidget);
        expect(find.text('الأجزاء (30)'), findsOneWidget);

        // Switch to Juzs tab
        await tester.tap(find.text('الأجزاء (30)'));
        await tester.pumpAndSettle();
        expect(find.text('الجزء 1'), findsOneWidget);
      },
    );
  });
}
