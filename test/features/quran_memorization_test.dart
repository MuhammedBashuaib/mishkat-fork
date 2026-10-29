import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_item.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_plan.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_session.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/memorization_plan_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/memorization_session_page.dart';
import 'package:mishkat_app/features/quran/presentation/pages/quran_memorization_page.dart';

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
  int readInt(String key, [int fallback = 0]) {
    final val = _store[key];
    return val is num ? val.toInt() : fallback;
  }

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
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

QuranData createDummyQuranData() {
  final fatiha = const QuranChapter(
    number: 1,
    name: 'الفاتحة',
    englishName: 'Al-Faatiha',
    revelationType: 'Meccan',
    page: 1,
    ayahs: [
      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
      'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      'الرَّحْمَٰنِ الرَّحِيمِ',
      'مَالِكِ يَوْمِ الدِّينِ',
      'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
      'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ',
      'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ',
    ],
    globalStart: 1,
  );

  final baqarah = const QuranChapter(
    number: 2,
    name: 'البقرة',
    englishName: 'Al-Baqara',
    revelationType: 'Medinan',
    page: 2,
    ayahs: [
      'الم',
      'ذَٰلِكَ الْكِتَابُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ',
      'الَّذِينَ يُؤْمِنُونَ بِالْغَيْبِ وَيُقِيمُونَ الصَّلَاةَ وَمِمَّا رَزَقْنَاهُمْ يُنفِقُونَ',
      'وَالَّذِينَ يُؤْمِنُونَ بِمَا أُنزِلَ إِلَيْكَ وَمَا أُنزِلَ مِن قَبْلِكَ وَبِالْآخِرَةِ هُمْ يُوقِنُونَ',
      'أُولَٰئِكَ عَلَىٰ هُدًى مِّن رَّبِّهِمْ ۖ وَأُولَٰئِكَ هُمُ الْمُفْلِحُونَ',
    ],
    globalStart: 8,
  );

  return QuranData(
    chapters: [fatiha, baqarah],
    juz: const [JuzStart(number: 1, surah: 1, ayah: 1)],
    pages: const [
      MushafPageInfo(
        page: 1,
        first: QuranPoint(surah: 1, ayah: 1, global: 1),
        last: QuranPoint(surah: 1, ayah: 7, global: 7),
      ),
      MushafPageInfo(
        page: 2,
        first: QuranPoint(surah: 2, ayah: 1, global: 8),
        last: QuranPoint(surah: 2, ayah: 5, global: 12),
      ),
    ],
  );
}

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
  Duration get currentPosition => Duration.zero;

  @override
  Duration? get duration => null;

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

void main() {
  group('Q8 — Domain Models & Serialization', () {
    test('MemorizationStatus parsing, fallback, and labels', () {
      expect(
        MemorizationStatus.fromString('memorized'),
        MemorizationStatus.memorized,
      );
      expect(
        MemorizationStatus.fromString('learning'),
        MemorizationStatus.learning,
      );
      expect(
        MemorizationStatus.fromString('needsRevision'),
        MemorizationStatus.needsRevision,
      );
      expect(
        MemorizationStatus.fromString('notStarted'),
        MemorizationStatus.notStarted,
      );
      expect(
        MemorizationStatus.fromString('unknown_state'),
        MemorizationStatus.notStarted,
      );
      expect(
        MemorizationStatus.fromString(null),
        MemorizationStatus.notStarted,
      );

      expect(MemorizationStatus.memorized.label, 'تم الحفظ');
      expect(MemorizationStatus.memorized.arabicLabel, 'تم الحفظ');
      expect(MemorizationStatus.needsRevision.arabicLabel, 'تحتاج مراجعة');
      expect(MemorizationStatus.learning.arabicLabel, 'قيد الحفظ');
      expect(MemorizationStatus.notStarted.arabicLabel, 'لم تبدأ');
    });

    test('MemorizationItem JSON round-trip and validation clamping', () {
      final now = DateTime(2026, 10, 4, 12, 0);
      final item = MemorizationItem(
        globalAyah: 255,
        status: MemorizationStatus.memorized,
        mistakeCount: 2,
        lastReviewedAt: now,
        updatedAt: now,
      );

      final json = item.toJson();
      final restored = MemorizationItem.fromJson(json);

      expect(restored.globalAyah, 255);
      expect(restored.status, MemorizationStatus.memorized);
      expect(restored.mistakeCount, 2);
      expect(restored.lastReviewedAt, now);
      expect(restored.updatedAt, now);

      // Clamping test
      final clamped = MemorizationItem.fromJson(const {
        'globalAyah': 9999,
        'status': 'invalid',
        'mistakeCount': -5,
      });
      expect(clamped.globalAyah, 6236);
      expect(clamped.status, MemorizationStatus.notStarted);
      expect(clamped.mistakeCount, 0);
    });

    test(
      'MemorizationPlan properties, estimated days, and completion status',
      () {
        final now = DateTime(2026, 10, 4, 10, 0);
        final plan = MemorizationPlan(
          id: 'plan_1',
          title: 'حفظ سورة الفاتحة',
          surah: 1,
          startGlobalAyah: 1,
          endGlobalAyah: 7,
          dailyTarget: 3,
          createdAt: now,
        );

        expect(plan.totalAyahs, 7);
        expect(plan.estimatedDays, 3); // (7 / 3).ceil() = 3
        expect(plan.isCompleted, false);

        final completedPlan = plan.copyWith(completedAt: now);
        expect(completedPlan.isCompleted, true);

        final json = plan.toJson();
        final restored = MemorizationPlan.fromJson(json);
        expect(restored, plan);
        expect(restored.totalAyahs, 7);
      },
    );

    test('MemorizationSession progress, finishes, and currentGlobalAyah', () {
      final session = MemorizationSession(
        planId: 'plan_1',
        queue: const [1, 2, 3, 4, 5],
        currentIndex: 2,
        isTextHidden: true,
        sessionType: MemorizationSessionType.memorization,
        completedCount: 2,
      );

      expect(session.currentGlobalAyah, 3);
      expect(session.progress, 2 / 5);
      expect(session.isFinished, false);

      final finishedSession = session.copyWith(currentIndex: 5);
      expect(finishedSession.currentGlobalAyah, null);
      expect(finishedSession.isFinished, true);
    });
  });

  group('Q8 — QuranMemorizationRepository Persistence & Resilience', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository repository;

    setUp(() {
      storage = InMemoryLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
    });

    test('Persists and loads clean data correctly', () async {
      final now = DateTime(2026, 10, 4, 10, 0);
      final plan = MemorizationPlan(
        id: 'plan_1',
        title: 'خطة حفظ الفاتحة',
        surah: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 7,
        dailyTarget: 2,
        createdAt: now,
      );
      final item = MemorizationItem(
        globalAyah: 1,
        status: MemorizationStatus.memorized,
        updatedAt: now,
      );
      final session = const MemorizationSession(
        planId: 'plan_1',
        queue: [1, 2, 3],
        currentIndex: 1,
        isTextHidden: true,
        sessionType: MemorizationSessionType.memorization,
      );

      await repository.saveData(
        plans: [plan],
        items: {1: item},
        session: session,
      );

      final loaded = await repository.loadData();
      expect(loaded.plans.length, 1);
      expect(loaded.plans.first.id, 'plan_1');
      expect(loaded.items.length, 1);
      expect(loaded.items[1]?.status, MemorizationStatus.memorized);
      expect(loaded.sessionResume?.currentIndex, 1);
    });

    test(
      'Resiliently ignores corrupted records and parses valid ones',
      () async {
        await storage.writeMap(QuranMemorizationRepository.storageKey, {
          'version': 1,
          'plans': [
            {
              'id': 'valid_plan',
              'title': 'Valid',
              'startGlobal': 1,
              'endGlobal': 7,
              'dailyTarget': 5,
              'createdAt': '2026-10-04T00:00:00.000',
            },
            'corrupted_entry',
            {'invalid': 'no_id'},
          ],
          'items': {
            '1': {'globalAyah': 1, 'status': 'memorized'},
            'corrupted_key': 'not_a_map',
            '99999': {
              'globalAyah': 99999,
              'status': 'learning',
            }, // Should be clamped to 6236
          },
          'session': 'corrupted_session_string',
        });

        final loaded = await repository.loadData();
        expect(loaded.plans.length, 1);
        expect(loaded.plans.first.id, 'valid_plan');
        expect(loaded.items.containsKey(1), true);
        expect(loaded.items[1]?.status, MemorizationStatus.memorized);
        expect(loaded.items[6236]?.status, MemorizationStatus.learning);
        expect(loaded.sessionResume, null);
      },
    );
  });

  group('Q8 — QuranMemorizationCubit Plan CRUD & Progress', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository repository;
    late QuranMemorizationCubit cubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
      cubit = QuranMemorizationCubit(repository: repository);
      await cubit.load();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('Creates plan, pauses, resumes, and deletes correctly', () async {
      final plan = await cubit.createPlan(
        title: 'حفظ سورة الفاتحة',
        surah: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 7,
        dailyTarget: 3,
      );

      expect(cubit.state.plans.length, 1);
      expect(cubit.state.activePlan?.id, plan.id);
      expect(cubit.state.activePlan?.totalAyahs, 7);

      // Pause plan
      await cubit.pausePlan(plan.id);
      expect(cubit.state.activePlan, null);
      expect(cubit.state.plans.first.isActive, false);

      // Resume plan
      await cubit.resumePlan(plan.id);
      expect(cubit.state.activePlan?.id, plan.id);
      expect(cubit.state.plans.first.isActive, true);

      // Delete plan
      await cubit.deletePlan(plan.id);
      expect(cubit.state.plans.isEmpty, true);
      expect(cubit.state.activePlan, null);
    });

    test(
      'setItemStatus updates mastery and calculates plan breakdown accurately',
      () async {
        final plan = await cubit.createPlan(
          title: 'خطة تجريبية',
          startGlobalAyah: 1,
          endGlobalAyah: 5,
          dailyTarget: 2,
        );

        await cubit.setItemStatus(1, MemorizationStatus.memorized);
        await cubit.setItemStatus(2, MemorizationStatus.memorized);
        await cubit.setItemStatus(3, MemorizationStatus.learning);
        await cubit.setItemStatus(4, MemorizationStatus.needsRevision);

        final progress = cubit.state.planProgress(plan);
        expect(progress.total, 5);
        expect(progress.memorized, 2);
        expect(progress.learning, 1);
        expect(progress.needsRevision, 1);
        expect(progress.remaining, 3);
        expect(progress.percentage, 0.4);

        expect(cubit.state.totalMemorizedCount, 2);
        expect(cubit.state.totalLearningCount, 1);
        expect(cubit.state.totalNeedsRevisionCount, 1);
      },
    );

    test(
      'All 6,236 Ayahs can be set and queried without bounds errors',
      () async {
        await cubit.setItemStatus(1, MemorizationStatus.memorized);
        await cubit.setItemStatus(6236, MemorizationStatus.needsRevision);

        expect(cubit.state.isAyahMemorized(1), true);
        expect(cubit.state.isAyahNeedsRevision(6236), true);
        expect(cubit.state.getItem(1).status, MemorizationStatus.memorized);
        expect(
          cubit.state.getItem(6236).status,
          MemorizationStatus.needsRevision,
        );
        expect(cubit.state.getItem(3000).status, MemorizationStatus.notStarted);
      },
    );
  });

  group('Q8 — Daily Target Ayahs Calculation', () {
    test(
      'Calculates consecutive unmemorized slice and handles partial final day',
      () {
        final state = QuranMemorizationState(
          plans: [
            MemorizationPlan(
              id: 'p1',
              title: 'Plan 1',
              startGlobalAyah: 1,
              endGlobalAyah: 7,
              dailyTarget: 3,
              createdAt: DateTime.now(),
            ),
          ],
          items: {
            1: MemorizationItem(
              globalAyah: 1,
              status: MemorizationStatus.memorized,
              updatedAt: DateTime.now(),
            ),
            2: MemorizationItem(
              globalAyah: 2,
              status: MemorizationStatus.memorized,
              updatedAt: DateTime.now(),
            ),
          },
        );

        final plan = state.plans.first;
        // Ayahs 1 and 2 are memorized, target size 3 -> should pick [3, 4, 5]
        final today = state.todayTargetAyahs(plan);
        expect(today, [3, 4, 5]);

        // When only 2 Ayahs remain (6 and 7), target size 3 -> should return [6, 7]
        final nearCompleteState = QuranMemorizationState(
          plans: state.plans,
          items: {
            for (var i = 1; i <= 5; i++)
              i: MemorizationItem(
                globalAyah: i,
                status: MemorizationStatus.memorized,
                updatedAt: DateTime.now(),
              ),
          },
        );
        final partialSlice = nearCompleteState.todayTargetAyahs(plan);
        expect(partialSlice, [6, 7]);
      },
    );
  });

  group('Q8 — Deterministic 4-Tier Revision Queue Algorithm', () {
    test(
      'Prioritizes according to 4 tiers and sorts with stable tie-breaker',
      () {
        final now = DateTime(2026, 10, 4, 12, 0);
        final oldTime = now.subtract(const Duration(hours: 72));

        final items = <int, MemorizationItem>{
          // Tier 4: Memorized
          1: MemorizationItem(
            globalAyah: 1,
            status: MemorizationStatus.memorized,
            lastReviewedAt: oldTime,
            updatedAt: oldTime,
          ),
          // Tier 1: Needs revision, mistakeCount = 1
          10: MemorizationItem(
            globalAyah: 10,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 1,
            updatedAt: now,
          ),
          // Tier 1: Needs revision, mistakeCount = 4 (should be before 10)
          20: MemorizationItem(
            globalAyah: 20,
            status: MemorizationStatus.needsRevision,
            mistakeCount: 4,
            updatedAt: now,
          ),
          // Tier 2: mistakeCount > 0, reviewed > 48h ago
          30: MemorizationItem(
            globalAyah: 30,
            status: MemorizationStatus.memorized,
            mistakeCount: 2,
            lastReviewedAt: oldTime,
            updatedAt: oldTime,
          ),
          // Tier 3: Learning
          40: MemorizationItem(
            globalAyah: 40,
            status: MemorizationStatus.learning,
            lastReviewedAt: oldTime,
            updatedAt: oldTime,
          ),
        };

        final state = QuranMemorizationState(items: items);
        final queue = state.generateRevisionQueue(limit: 10, now: now);

        // Expected order:
        // Tier 1: 20 (mistakeCount 4), then 10 (mistakeCount 1)
        // Tier 2: 30
        // Tier 3: 40
        // Tier 4: 1
        expect(queue, [20, 10, 30, 40, 1]);
      },
    );

    test('Enforces queue limit parameter', () {
      final items = <int, MemorizationItem>{
        for (var i = 1; i <= 25; i++)
          i: MemorizationItem(
            globalAyah: i,
            status: MemorizationStatus.needsRevision,
            mistakeCount: i,
            updatedAt: DateTime.now(),
          ),
      };
      final state = QuranMemorizationState(items: items);
      final queue = state.generateRevisionQueue(limit: 5);
      expect(queue.length, 5);
      // Highest mistakeCount first: 25, 24, 23, 22, 21
      expect(queue, [25, 24, 23, 22, 21]);
    });
  });

  group('Q8 — Active Recall Practice Session Flow', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository repository;
    late QuranMemorizationCubit cubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
      cubit = QuranMemorizationCubit(repository: repository);
      await cubit.load();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('Session text hiding, reveal, and navigation', () async {
      final plan = await cubit.createPlan(
        title: 'ورد اليوم',
        startGlobalAyah: 1,
        endGlobalAyah: 3,
        dailyTarget: 3,
      );

      cubit.startPlanSession(plan);
      expect(cubit.state.activeSession != null, true);
      expect(cubit.state.activeSession?.currentGlobalAyah, 1);
      expect(cubit.state.activeSession?.isTextHidden, true);

      // Reveal text
      cubit.revealText();
      expect(cubit.state.activeSession?.isTextHidden, false);

      // Toggle text hidden
      cubit.toggleTextHidden();
      expect(cubit.state.activeSession?.isTextHidden, true);

      // Advance without assessment
      cubit.advanceSession();
      expect(cubit.state.activeSession?.currentGlobalAyah, 2);

      // Previous session ayah
      cubit.previousSessionAyah();
      expect(cubit.state.activeSession?.currentGlobalAyah, 1);
    });

    test('Self-assessment: recordKnows and recordNeedsRevision', () async {
      final plan = await cubit.createPlan(
        title: 'خطة الاختبار',
        startGlobalAyah: 1,
        endGlobalAyah: 2,
        dailyTarget: 2,
      );

      cubit.startPlanSession(plan);
      expect(cubit.state.activeSession?.currentGlobalAyah, 1);

      // Ayah 1: Needs revision
      await cubit.recordNeedsRevision();
      expect(cubit.state.getItem(1).status, MemorizationStatus.needsRevision);
      expect(cubit.state.getItem(1).mistakeCount, 1);
      // Automatically advanced to Ayah 2
      expect(cubit.state.activeSession?.currentGlobalAyah, 2);

      // Ayah 2: Knows / Memorized
      await cubit.recordKnows();
      expect(cubit.state.getItem(2).status, MemorizationStatus.memorized);

      // Session finished (queue size was 2)
      expect(cubit.state.activeSession?.isFinished, true);

      // Ending session clears activeSession
      cubit.endSession();
      expect(cubit.state.activeSession, null);
    });

    test('Auto-completes plan when all its Ayahs are memorized', () async {
      final plan = await cubit.createPlan(
        title: 'خطة سريعة',
        startGlobalAyah: 1,
        endGlobalAyah: 2,
        dailyTarget: 2,
      );

      cubit.startPlanSession(plan);
      await cubit.recordKnows(); // Ayah 1
      await cubit.recordKnows(); // Ayah 2

      final updatedPlan = cubit.state.plans.firstWhere((p) => p.id == plan.id);
      expect(updatedPlan.isCompleted, true);
      expect(updatedPlan.isActive, false);
    });
  });

  group('Q8 — Widget Smoke Tests', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository repository;
    late QuranMemorizationCubit cubit;
    late QuranCubit quranCubit;
    late QuranData dummyData;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
      cubit = QuranMemorizationCubit(repository: repository);
      await cubit.load();
      dummyData = createDummyQuranData();
      quranCubit = QuranCubit(
        storage: storage,
        repository: DummyQuranRepository(dummyData),
        audio: DummyAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await quranCubit.load();
    });

    tearDown(() async {
      await cubit.close();
      await quranCubit.close();
    });

    testWidgets('MemorizationPlanPage renders form controls', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: cubit),
              BlocProvider<QuranCubit>.value(value: quranCubit),
            ],
            child: MemorizationPlanPage(quranData: dummyData),
          ),
        ),
      );

      expect(find.text('خطة حفظ جديدة'), findsOneWidget);
      expect(find.text('اسم الخطة'), findsOneWidget);
      expect(find.text('اختر السورة'), findsOneWidget);
      expect(find.text('الورد اليومي للآيات الجديد'), findsOneWidget);
      expect(find.text('بدء وتثبيت خطة الحفظ'), findsOneWidget);
    });

    testWidgets('MemorizationPlanPage stays calm without overflow at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: cubit),
              BlocProvider<QuranCubit>.value(value: quranCubit),
            ],
            child: MemorizationPlanPage(quranData: dummyData),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('خطة بسيطة يمكنك الاستمرار عليها'), findsOneWidget);
      expect(find.text('بدء وتثبيت خطة الحفظ'), findsOneWidget);
    });

    testWidgets(
      'MemorizationSessionPage renders recall card and evaluation buttons',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final plan = await cubit.createPlan(
          title: 'خطة الورد',
          startGlobalAyah: 1,
          endGlobalAyah: 2,
          dailyTarget: 2,
        );
        cubit.startPlanSession(plan);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<QuranMemorizationCubit>.value(value: cubit),
                BlocProvider<QuranCubit>.value(value: quranCubit),
              ],
              child: MemorizationSessionPage(quranData: dummyData),
            ),
          ),
        );

        expect(find.text('جلسة حفظ الورد'), findsOneWidget);
        expect(find.text('استحضر الآية الكريمة غيباً'), findsOneWidget);
        expect(find.text('إظهار نص الآية للتأكد'), findsOneWidget);
        expect(find.text('أعرفها ومحفوظة'), findsOneWidget);
        expect(find.text('أحتاج مراجعة'), findsOneWidget);

        // Tap reveal
        await tester.tap(find.text('إظهار نص الآية للتأكد'));
        await tester.pumpAndSettle();

        expect(find.text('نص الآية الكريمة'), findsOneWidget);
      },
    );

    testWidgets(
      'Tutor session keeps the memorization flow to two clear actions',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final plan = await cubit.createPlan(
          title: 'خطة التلقين',
          startGlobalAyah: 1,
          endGlobalAyah: 2,
          dailyTarget: 2,
        );
        cubit.startPlanSession(plan);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<QuranMemorizationCubit>.value(value: cubit),
                BlocProvider<QuranCubit>.value(value: quranCubit),
              ],
              child: MemorizationSessionPage(
                quranData: dummyData,
                startWithAudio: true,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.text('جلسة حفظ الورد'), findsOneWidget);
        expect(find.text('الآية 1 من 2'), findsOneWidget);
        expect(find.text('استمع للآية'), findsOneWidget);
        expect(find.text('ردّد في وقت الصمت'), findsOneWidget);
        expect(find.text('أتقنتها، الآية التالية'), findsOneWidget);
        expect(find.text('أعد التلقين'), findsOneWidget);
        expect(find.text('تقييم الحفظ لهذه الآية'), findsNothing);
        expect(find.text('التفسير'), findsNothing);

        await tester.tap(find.text('أتقنتها، الآية التالية'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('الآية 2 من 2'), findsOneWidget);
        expect(
          find.text('الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ'),
          findsOneWidget,
        );

        final finishButton = find.text('أتقنتها، إنهاء الجلسة');
        await tester.ensureVisible(finishButton);
        await tester.tap(finishButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('أتممت وردك'), findsOneWidget);
        expect(find.text('إجمالي المحفوظ'), findsNothing);
      },
    );

    testWidgets('QuranMemorizationPage renders dashboard and statistics', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: cubit),
              BlocProvider<QuranCubit>.value(value: quranCubit),
            ],
            child: const QuranMemorizationPage(),
          ),
        ),
      );

      expect(find.text('الحفظ والمراجعة'), findsOneWidget);
      expect(find.text('إحصائيات الحفظ الكلية'), findsOneWidget);
      expect(find.text('المحفوظ'), findsOneWidget);
      expect(find.text('المراجعة الذكية والتثبيت'), findsOneWidget);
    });

    testWidgets('QuranMemorizationPage switches the plan used for training', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final first = await cubit.createPlan(
        title: 'خطة الفاتحة',
        surah: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 3,
        dailyTarget: 2,
      );
      await cubit.createPlan(
        title: 'خطة البقرة',
        surah: 2,
        startGlobalAyah: 8,
        endGlobalAyah: 10,
        dailyTarget: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: cubit),
              BlocProvider<QuranCubit>.value(value: quranCubit),
            ],
            child: const QuranMemorizationPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('التدريب الآن على: خطة البقرة'), findsOneWidget);
      await tester.tap(find.text('تبديل'));
      await tester.pumpAndSettle();
      expect(find.text('اختر خطة التدريب'), findsOneWidget);

      await tester.tap(find.text('خطة الفاتحة').last);
      await tester.pumpAndSettle();

      expect(cubit.state.activePlan?.id, first.id);
      expect(find.text('التدريب الآن على: خطة الفاتحة'), findsOneWidget);
    });

    testWidgets('Oral recitation offers plan and free Surah range', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await cubit.createPlan(
        title: 'خطة الفاتحة',
        surah: 1,
        startGlobalAyah: 1,
        endGlobalAyah: 7,
        dailyTarget: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<QuranMemorizationCubit>.value(value: cubit),
              BlocProvider<QuranCubit>.value(value: quranCubit),
            ],
            child: const QuranMemorizationPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('التسميع الذكي'));
      await tester.tap(find.text('التسميع الذكي'));
      await tester.pumpAndSettle();
      expect(find.text('ماذا تريد أن تسمّع؟'), findsOneWidget);
      expect(find.text('خطة الفاتحة'), findsWidgets);

      await tester.tap(find.text('تسميع حر'));
      await tester.pumpAndSettle();
      expect(find.text('السورة'), findsOneWidget);
      expect(find.text('السورة كاملة'), findsOneWidget);
      expect(find.text('من الآية'), findsOneWidget);
      expect(find.text('إلى الآية'), findsOneWidget);
    });
  });
}
