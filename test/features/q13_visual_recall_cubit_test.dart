import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/models/visual_recall_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_visual_recall_cubit.dart';

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> store = {};
  bool failOnWrite = false;

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final val = store[key];
    return val is Map ? Map<String, dynamic>.from(val) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final val = store[key];
    return val is List ? List<dynamic>.from(val) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final val = store[key];
    return val is num ? val.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    if (failOnWrite) throw FileSystemException('Simulated disk full');
    store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    if (failOnWrite) throw FileSystemException('Simulated disk full');
    store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    store.remove(key);
  }

  @override
  Future<void> clear() async {
    store.clear();
  }
}

void main() {
  group('Q13 Phase 1A — Domain & State Machine Tests', () {
    late InMemoryLocalStorageService storage;
    late QuranMemorizationRepository memoRepo;
    late QuranMemorizationCubit memoCubit;
    late QuranVisualRecallCubit recallCubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      memoRepo = QuranMemorizationRepository(storage: storage);
      memoCubit = QuranMemorizationCubit(repository: memoRepo);
      await memoCubit.load();
      recallCubit = QuranVisualRecallCubit(
        memorizationCubit: memoCubit,
        storage: storage,
      );
      await recallCubit.init();
    });

    test('1. Initial state is idle with no session or queue', () {
      expect(recallCubit.state.phase, VisualRecallPhase.idle);
      expect(recallCubit.state.isIdle, true);
      expect(recallCubit.state.hasActiveSession, false);
      expect(recallCubit.state.currentGlobalAyah, isNull);
      expect(recallCubit.state.queue, isEmpty);
      expect(recallCubit.state.revealedGlobals, isEmpty);
      expect(recallCubit.state.activeMaskedGlobals, isEmpty);
      expect(recallCubit.state.hasCheckpointAvailable, false);
      expect(recallCubit.state.error, isNull);
    });

    test(
      '2. startSingleAyah initializes activeRecall with single-item queue',
      () async {
        await recallCubit.startSingleAyah(255);

        expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
        expect(recallCubit.state.isActiveRecall, true);
        expect(recallCubit.state.hasActiveSession, true);
        expect(recallCubit.state.queue, [255]);
        expect(recallCubit.state.currentIndex, 0);
        expect(recallCubit.state.currentGlobalAyah, 255);
        expect(recallCubit.state.isCurrentAyahRevealed, false);
        expect(recallCubit.state.activeMaskedGlobals, {255});
        expect(recallCubit.state.origin, VisualRecallSessionOrigin.adhoc);
        expect(recallCubit.state.sessionId, startsWith('vrs_'));

        // Checkpoint was written to storage
        expect(
          storage.store.containsKey(QuranVisualRecallCubit.checkpointKey),
          true,
        );
      },
    );

    test('3. startSingleAyah rejects invalid out-of-bounds Ayah index', () {
      expect(() => recallCubit.startSingleAyah(0), throwsArgumentError);
      expect(() => recallCubit.startSingleAyah(6237), throwsArgumentError);
      expect(recallCubit.state.phase, VisualRecallPhase.idle);
    });

    test('4. startRange initializes multi-Ayah queue correctly', () async {
      await recallCubit.startRange(1, 5);

      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
      expect(recallCubit.state.queue, [1, 2, 3, 4, 5]);
      expect(recallCubit.state.totalCount, 5);
      expect(recallCubit.state.currentIndex, 0);
      expect(recallCubit.state.currentGlobalAyah, 1);
      expect(recallCubit.state.activeMaskedGlobals, {1, 2, 3, 4, 5});
      expect(recallCubit.state.origin, VisualRecallSessionOrigin.range);
    });

    test('5. startRange rejects inverted or invalid ranges', () {
      expect(() => recallCubit.startRange(5, 1), throwsArgumentError);
      expect(() => recallCubit.startRange(0, 5), throwsArgumentError);
      expect(() => recallCubit.startRange(6200, 6240), throwsArgumentError);
      expect(recallCubit.state.phase, VisualRecallPhase.idle);
    });

    test('6. startJourney deduplicates Ayahs while preserving order', () async {
      await recallCubit.startJourney([
        10,
        11,
        10,
        12,
        11,
        13,
      ], planId: 'test_plan');

      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
      expect(recallCubit.state.queue, [10, 11, 12, 13]);
      expect(recallCubit.state.origin, VisualRecallSessionOrigin.plan);
      expect(recallCubit.state.planId, 'test_plan');
    });

    test(
      '7. Interactive range selection workflow: enter -> update -> confirm',
      () async {
        recallCubit.enterRangeSelection(20);
        expect(recallCubit.state.phase, VisualRecallPhase.rangeSelection);
        expect(recallCubit.state.isRangeSelecting, true);
        expect(recallCubit.state.rangeSelectionStart, 20);
        expect(recallCubit.state.rangeSelectionEnd, 20);

        recallCubit.updateRangeEnd(25);
        expect(recallCubit.state.rangeSelectionEnd, 25);

        await recallCubit.confirmRangeSelection();
        expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
        expect(recallCubit.state.queue, [20, 21, 22, 23, 24, 25]);
        expect(recallCubit.state.rangeSelectionStart, isNull);
      },
    );

    test('8. Interactive range selection: cancel returns to idle', () {
      recallCubit.enterRangeSelection(30);
      expect(recallCubit.state.isRangeSelecting, true);

      recallCubit.cancelRangeSelection();
      expect(recallCubit.state.isIdle, true);
      expect(recallCubit.state.rangeSelectionStart, isNull);
    });

    test('9. Per-Ayah reveal semantics: revealing current Ayah leaves others masked', () async {
      await recallCubit.startRange(100, 103);
      expect(recallCubit.state.activeMaskedGlobals, {100, 101, 102, 103});

      // Reveal current Ayah (100)
      recallCubit.revealCurrentAyah();
      expect(recallCubit.state.phase, VisualRecallPhase.evaluating);
      expect(recallCubit.state.isEvaluating, true);
      expect(recallCubit.state.isCurrentAyahRevealed, true);
      expect(recallCubit.state.revealedGlobals, {100});

      // INVARIANT: Remaining Ayahs (101, 102, 103) remain masked!
      expect(recallCubit.state.activeMaskedGlobals, {101, 102, 103});

      // Hide current Ayah again
      recallCubit.hideCurrentAyah();
      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
      expect(recallCubit.state.isCurrentAyahRevealed, false);
      expect(recallCubit.state.activeMaskedGlobals, {100, 101, 102, 103});
    });

    test('10. toggleAyahReveal selectively toggles reveal on individual Ayahs', () async {
      await recallCubit.startRange(200, 202);

      // Toggle Ayah 201 (ahead of current pointer)
      recallCubit.toggleAyahReveal(201);
      expect(recallCubit.state.revealedGlobals, {201});
      expect(
        recallCubit.state.phase,
        VisualRecallPhase.activeRecall,
      ); // Current (200) still masked

      // Toggle current Ayah (200) -> transitions to evaluating
      recallCubit.toggleAyahReveal(200);
      expect(recallCubit.state.revealedGlobals, {200, 201});
      expect(recallCubit.state.phase, VisualRecallPhase.evaluating);

      // Toggle current Ayah (200) back to hidden -> transitions to activeRecall
      recallCubit.toggleAyahReveal(200);
      expect(recallCubit.state.revealedGlobals, {201});
      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
    });

    test('11. Assessment records through QuranMemorizationCubit and advances queue', () async {
      await recallCubit.startRange(300, 302);
      final sessionId = recallCubit.state.sessionId!;

      recallCubit.revealCurrentAyah();
      expect(recallCubit.state.phase, VisualRecallPhase.evaluating);

      // Record Good assessment for Ayah 300
      await recallCubit.recordOutcome(ReviewOutcome.good);

      // INVARIANT 1: MemorizationCubit received review and recorded mastery
      expect(memoCubit.state.history.length, 1);
      final record = memoCubit.state.history.first;
      expect(record.globalAyah, 300);
      expect(record.outcome, ReviewOutcome.good);
      expect(record.sessionId, sessionId);
      expect(record.id, 'rev_${sessionId}_300');
      expect(memoCubit.state.getItem(300).status, MemorizationStatus.memorized);

      // INVARIANT 2: RecallCubit advanced to Ayah 301 in activeRecall mode
      expect(recallCubit.state.currentIndex, 1);
      expect(recallCubit.state.currentGlobalAyah, 301);
      expect(recallCubit.state.phase, VisualRecallPhase.activeRecall);
      expect(recallCubit.state.assessmentOutcomes[300], ReviewOutcome.good);
      expect(recallCubit.state.completedCount, 1);
      expect(recallCubit.state.progress, closeTo(1 / 3, 1e-3));
    });

    test('12. Completing all queue Ayahs purges checkpoint and transitions to completed', () async {
      await recallCubit.startRange(400, 401);

      // Ayah 400
      recallCubit.revealCurrentAyah();
      await recallCubit.recordOutcome(ReviewOutcome.easy);
      expect(recallCubit.state.currentIndex, 1);

      // Ayah 401 (last)
      recallCubit.revealCurrentAyah();
      await recallCubit.recordOutcome(ReviewOutcome.good);

      // Finished!
      expect(recallCubit.state.phase, VisualRecallPhase.completed);
      expect(recallCubit.state.isCompleted, true);
      expect(recallCubit.state.currentGlobalAyah, isNull);
      expect(recallCubit.state.completedCount, 2);
      expect(recallCubit.state.progress, 1.0);

      // Checkpoint was purged from storage
      expect(
        storage.store.containsKey(QuranVisualRecallCubit.checkpointKey),
        false,
      );

      // Dismiss summary resets to idle
      recallCubit.dismissSummary();
      expect(recallCubit.state.isIdle, true);
    });

    test(
      '13. Storage/Cubit write failure blocks queue advancement and sets error',
      () async {
        await recallCubit.startSingleAyah(500);
        recallCubit.revealCurrentAyah();

        // Simulate storage write failure
        storage.failOnWrite = true;

        var threw = false;
        try {
          await recallCubit.recordOutcome(ReviewOutcome.good);
        } catch (_) {
          threw = true;
        }

        expect(threw, true);

        // INVARIANT: Advance is BLOCKED! Pointer remains at Ayah 500
        expect(recallCubit.state.currentIndex, 0);
        expect(recallCubit.state.currentGlobalAyah, 500);
        expect(recallCubit.state.error, isNotNull);
        expect(recallCubit.state.completedCount, 0);
      },
    );

    test('14. jumpToAyah and toggleAudioSync function correctly', () async {
      await recallCubit.startRange(600, 605);
      expect(recallCubit.state.currentIndex, 0);

      recallCubit.jumpToAyah(603);
      expect(recallCubit.state.currentIndex, 3);
      expect(recallCubit.state.currentGlobalAyah, 603);

      expect(recallCubit.state.isAudioSyncEnabled, false);
      recallCubit.toggleAudioSync();
      expect(recallCubit.state.isAudioSyncEnabled, true);
    });

    test(
      '15. Checkpoint saving, inspection, restoration, and 24h expiration',
      () async {
        // 1. Create a session and write checkpoint
        await recallCubit.startRange(700, 703);
        recallCubit.revealCurrentAyah();
        await recallCubit.recordOutcome(
          ReviewOutcome.good,
        ); // 700 completed, now at 701

        final checkpointMap = storage.readMap(
          QuranVisualRecallCubit.checkpointKey,
        );
        expect(checkpointMap.isNotEmpty, true);
        expect(checkpointMap['currentIndex'], 1);
        expect(checkpointMap['queue'], [700, 701, 702, 703]);

        // 2. Simulate app restart with a fresh Cubit instance
        final newRecallCubit = QuranVisualRecallCubit(
          memorizationCubit: memoCubit,
          storage: storage,
        );
        await newRecallCubit.init();

        expect(newRecallCubit.state.hasCheckpointAvailable, true);
        expect(newRecallCubit.state.checkpointToResume, isNotNull);
        expect(newRecallCubit.state.checkpointToResume!.currentIndex, 1);

        // 3. Restore checkpoint
        await newRecallCubit.restoreCheckpoint();
        expect(newRecallCubit.state.phase, VisualRecallPhase.activeRecall);
        expect(newRecallCubit.state.currentIndex, 1);
        expect(newRecallCubit.state.currentGlobalAyah, 701);
        expect(newRecallCubit.state.hasCheckpointAvailable, false);

        // 4. Test 24-hour expiration
        final expiredCheckpoint = VisualRecallSessionCheckpoint(
          sessionId: 'vrs_expired',
          origin: VisualRecallSessionOrigin.adhoc,
          queue: [800],
          savedAt: DateTime.now().subtract(const Duration(hours: 25)),
        );
        await storage.writeMap(
          QuranVisualRecallCubit.checkpointKey,
          expiredCheckpoint.toJson(),
        );

        final expiredCubit = QuranVisualRecallCubit(
          memorizationCubit: memoCubit,
          storage: storage,
        );
        await expiredCubit.init();

        // INVARIANT: Expired checkpoint is purged and not offered for resume!
        expect(expiredCubit.state.hasCheckpointAvailable, false);
        expect(
          storage.store.containsKey(QuranVisualRecallCubit.checkpointKey),
          false,
        );
      },
    );

    test('16. 128-bit session ID generation guarantees zero collisions across 500 rapid calls', () {
      final ids = <String>{};
      for (var i = 0; i < 500; i++) {
        final id = generateVisualRecallSessionId(
          origin: 'test',
          startGlobal: i + 1,
          endGlobal: i + 1,
        );
        expect(ids.add(id), true, reason: 'Collision detected on trial $i');
        expect(id, startsWith('vrs_'));
      }
      expect(ids.length, 500);
    });
  });
}
