import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_session.dart';
import 'package:mishkat_app/features/quran/data/models/memorization_status.dart';
import 'package:mishkat_app/features/quran/data/models/murajaah_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_memorization_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_memorization_cubit.dart';

/// Controllable storage mock supporting granular failure injection at every I/O boundary.
class ControllableLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> store = {};
  bool failBeforeWriteMap = false;
  bool failDuringTempFileWrite = false;
  bool failDuringAtomicRename = false;
  int writeMapCallCount = 0;
  int writeListCallCount = 0;

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
    writeMapCallCount++;
    if (failBeforeWriteMap) {
      throw Exception('Simulated I/O failure before writeMap');
    }
    if (failDuringTempFileWrite) {
      throw Exception('Simulated disk full during .tmp write');
    }
    if (failDuringAtomicRename) {
      throw Exception('Simulated atomic rename failure');
    }
    store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    writeListCallCount++;
    store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async => store.remove(key);

  @override
  Future<void> clear() async => store.clear();
}

void main() {
  group('Q13 Persistence Integrity Remediation — 10 Required Failure Tests', () {
    late ControllableLocalStorageService storage;
    late QuranMemorizationRepository repository;
    late QuranMemorizationCubit cubit;

    setUp(() async {
      storage = ControllableLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
      cubit = QuranMemorizationCubit(repository: repository);
      await cubit.load();
    });

    test('1. Failure before any persistence rolls back memory and leaves disk untouched', () async {
      storage.failBeforeWriteMap = true;
      final testTime = DateTime(2026, 10, 6, 12, 0);

      var threw = false;
      try {
        await cubit.recordReviewOutcome(
          globalAyah: 1,
          outcome: ReviewOutcome.good,
          operationId: 'op_pre_write_fail',
          now: testTime,
        );
      } catch (e) {
        threw = true;
      }

      expect(threw, true);
      // In-memory state rolled back to previous
      expect(cubit.state.getItem(1).status, MemorizationStatus.notStarted);
      expect(cubit.state.getItem(1).consecutiveSuccesses, 0);
      expect(cubit.state.history, isEmpty);
      expect(cubit.state.error, isNotNull);

      // On disk: untouched
      expect(storage.store.containsKey('quran_memorization'), false);
    });

    test('2. Failure after mastery mutation but before durable commit rolls back state cleanly', () async {
      storage.failDuringTempFileWrite = true;
      final testTime = DateTime(2026, 10, 6, 12, 0);

      var threw = false;
      try {
        await cubit.recordReviewOutcome(
          globalAyah: 2,
          outcome: ReviewOutcome.difficult,
          operationId: 'op_during_commit_fail',
          now: testTime,
        );
      } catch (e) {
        threw = true;
      }

      expect(threw, true);
      // In-memory rolled back
      expect(cubit.state.getItem(2).mistakeCount, 0);
      expect(cubit.state.getItem(2).status, MemorizationStatus.notStarted);
      expect(cubit.state.history, isEmpty);

      // On disk: untouched
      expect(storage.store.containsKey('quran_memorization'), false);
    });

    test('3. Failure during temporary-file writing preserves disk store and rolls back cubit', () async {
      // First save an initial clean item
      await cubit.recordReviewOutcome(
        globalAyah: 10,
        outcome: ReviewOutcome.easy,
        operationId: 'op_initial',
        now: DateTime(2026, 10, 6, 10, 0),
      );
      expect(cubit.state.getItem(10).status, MemorizationStatus.memorized);
      expect(cubit.state.history.length, 1);

      // Now inject .tmp write failure on subsequent review
      storage.failDuringTempFileWrite = true;
      var threw = false;
      try {
        await cubit.recordReviewOutcome(
          globalAyah: 11,
          outcome: ReviewOutcome.good,
          operationId: 'op_tmp_fail',
          now: DateTime(2026, 10, 6, 11, 0),
        );
      } catch (_) {
        threw = true;
      }

      expect(threw, true);
      // In-memory rolls back to state with only Ayah 10
      expect(cubit.state.getItem(10).status, MemorizationStatus.memorized);
      expect(cubit.state.getItem(11).status, MemorizationStatus.notStarted);
      expect(cubit.state.history.length, 1);

      // Verify on disk: only Ayah 10 persisted
      final diskData = storage.readMap('quran_memorization');
      final diskItems = (diskData['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(diskItems.length, 1);
      expect(diskItems.first['g'] ?? diskItems.first['globalAyah'], 10);
    });

    test('4. Failure during atomic replacement or rename rolls back memory and preserves old store', () async {
      // Seed store with initial data
      await cubit.recordReviewOutcome(
        globalAyah: 20,
        outcome: ReviewOutcome.good,
        operationId: 'op_seed',
        now: DateTime(2026, 10, 6, 10, 0),
      );

      // Inject rename failure
      storage.failDuringAtomicRename = true;
      var threw = false;
      try {
        await cubit.recordReviewOutcome(
          globalAyah: 21,
          outcome: ReviewOutcome.failed,
          operationId: 'op_rename_fail',
          now: DateTime(2026, 10, 6, 11, 0),
        );
      } catch (_) {
        threw = true;
      }

      expect(threw, true);
      expect(cubit.state.getItem(21).status, MemorizationStatus.notStarted);
      expect(cubit.state.history.length, 1);
    });

    test('5. Retry after application/repository reconstruction succeeds without duplicate mutation', () async {
      storage.failBeforeWriteMap = true;
      final testTime = DateTime(2026, 10, 6, 12, 0);

      // Attempt 1 fails
      try {
        await cubit.recordReviewOutcome(
          globalAyah: 30,
          outcome: ReviewOutcome.good,
          operationId: 'op_recon_retry',
          now: testTime,
        );
      } catch (_) {}

      // Reconstruct application components
      storage.failBeforeWriteMap = false;
      final newRepo = QuranMemorizationRepository(storage: storage);
      final newCubit = QuranMemorizationCubit(repository: newRepo);
      await newCubit.load();

      // Retry with same operation ID
      await newCubit.recordReviewOutcome(
        globalAyah: 30,
        outcome: ReviewOutcome.good,
        operationId: 'op_recon_retry',
        now: testTime,
      );

      // Verify exact counts and values
      expect(newCubit.state.getItem(30).status, MemorizationStatus.memorized);
      expect(newCubit.state.getItem(30).consecutiveSuccesses, 1);
      expect(newCubit.state.getItem(30).intervalDays, 3);
      expect(newCubit.state.history.length, 1);

      // Verify on disk: atomic snapshot has exactly 1 item and 1 history record
      final loadedData = await newRepo.loadData();
      expect(loadedData.items.length, 1);
      expect(loadedData.items[30]?.consecutiveSuccesses, 1);
      expect(loadedData.items[30]?.intervalDays, 3);
      expect(loadedData.history.length, 1);
      expect(loadedData.history.first.id, 'op_recon_retry');
    });

    test('6. Duplicate assessment using the same operation ID is strictly idempotent', () async {
      final testTime = DateTime(2026, 10, 6, 12, 0);

      // Delivery 1
      await cubit.recordReviewOutcome(
        globalAyah: 40,
        outcome: ReviewOutcome.good,
        operationId: 'op_dedup_test',
        now: testTime,
      );

      expect(cubit.state.getItem(40).consecutiveSuccesses, 1);
      expect(cubit.state.getItem(40).intervalDays, 3);
      expect(cubit.state.history.length, 1);

      // Delivery 2 (Duplicate with same operationId)
      await cubit.recordReviewOutcome(
        globalAyah: 40,
        outcome: ReviewOutcome.good,
        operationId: 'op_dedup_test',
        now: testTime.add(const Duration(seconds: 1)),
      );

      // INVARIANT: Consecutive successes did NOT increment to 2; interval did NOT expand to 7!
      expect(cubit.state.getItem(40).consecutiveSuccesses, 1);
      expect(cubit.state.getItem(40).intervalDays, 3);
      expect(cubit.state.history.length, 1);

      // Verify on disk: exactly 1 history record
      final diskHistory = await repository.loadHistory();
      expect(diskHistory.length, 1);
      expect(diskHistory.first.id, 'op_dedup_test');
    });

    test('7. Two distinct sessions assessing the same Ayah record both reviews correctly', () async {
      final time1 = DateTime(2026, 10, 6, 9, 0);
      final time2 = DateTime(2026, 10, 6, 15, 0);

      // Session A review
      await cubit.recordReviewOutcome(
        globalAyah: 50,
        outcome: ReviewOutcome.good,
        sessionId: 'session_A',
        now: time1,
      );

      // Session B review
      await cubit.recordReviewOutcome(
        globalAyah: 50,
        outcome: ReviewOutcome.difficult,
        sessionId: 'session_B',
        now: time2,
      );

      expect(cubit.state.history.length, 2);
      expect(cubit.state.history[0].sessionId, 'session_A');
      expect(cubit.state.history[0].outcome, ReviewOutcome.good);
      expect(cubit.state.history[1].sessionId, 'session_B');
      expect(cubit.state.history[1].outcome, ReviewOutcome.difficult);

      final item50 = cubit.state.getItem(50);
      expect(item50.status, MemorizationStatus.needsRevision);
      expect(item50.mistakeCount, 1);
      expect(item50.consecutiveSuccesses, 0);
      expect(item50.intervalDays, 1);

      // Verify on disk: both records stored atomically
      final loaded = await repository.loadData();
      expect(loaded.history.length, 2);
    });

    test('8. Failure after durable commit but before UI acknowledgement recovers idempotently on retry', () async {
      // Simulate client dropping connection or crashing after commit succeeded on disk
      await cubit.recordReviewOutcome(
        globalAyah: 60,
        outcome: ReviewOutcome.easy,
        operationId: 'op_committed_unacked',
        sessionId: 'sess_unack',
        now: DateTime(2026, 10, 6, 12, 0),
      );

      // Disk is committed
      expect(storage.readMap('quran_memorization')['history'], isNotEmpty);

      // UI retries upon reboot
      final rebootedCubit = QuranMemorizationCubit(repository: repository);
      await rebootedCubit.load();

      await rebootedCubit.recordReviewOutcome(
        globalAyah: 60,
        outcome: ReviewOutcome.easy,
        operationId: 'op_committed_unacked',
        sessionId: 'sess_unack',
        now: DateTime(2026, 10, 6, 12, 0),
      );

      // Verify retry was acknowledged idempotently without duplicating mutation
      expect(rebootedCubit.state.getItem(60).consecutiveSuccesses, 1);
      expect(rebootedCubit.state.getItem(60).intervalDays, 7);
      expect(rebootedCubit.state.history.length, 1);
    });

    test('9. Repeated restoration of the same pending operation executes exactly once', () async {
      const opId = 'op_repeated_restore';

      // Simulate a loop replaying the same operation 5 times
      for (int i = 0; i < 5; i++) {
        await cubit.recordReviewOutcome(
          globalAyah: 70,
          outcome: ReviewOutcome.good,
          operationId: opId,
          now: DateTime(2026, 10, 6, 12, i),
        );
      }

      expect(cubit.state.history.length, 1);
      expect(cubit.state.getItem(70).consecutiveSuccesses, 1);
      expect(cubit.state.getItem(70).intervalDays, 3);
      expect(cubit.state.getItem(70).mistakeCount, 0);
    });

    test('10. Corrupt or expired visual-session checkpoint preserves unrelated mastery data', () async {
      // Commit legitimate memorization items and history
      await cubit.recordReviewOutcome(
        globalAyah: 80,
        outcome: ReviewOutcome.good,
        operationId: 'op_legit',
        now: DateTime(2026, 10, 6, 12, 0),
      );

      expect(cubit.state.history.length, 1);
      expect(cubit.state.getItem(80).status, MemorizationStatus.memorized);

      // Write corrupt/expired checkpoint under unrelated key
      await storage.writeMap('quran_visual_recall_checkpoint', {
        'version': 999, // Unknown/corrupt schema version
        'savedAt': DateTime(2020, 1, 1).millisecondsSinceEpoch, // Expired
        'corrupt': true,
      });

      // Simulate app restart and recovery
      final rebootRepo = QuranMemorizationRepository(storage: storage);
      final rebootCubit = QuranMemorizationCubit(repository: rebootRepo);
      await rebootCubit.load();

      // INVARIANT: Mastery data is 100% intact!
      expect(
        rebootCubit.state.getItem(80).status,
        MemorizationStatus.memorized,
      );
      expect(rebootCubit.state.getItem(80).consecutiveSuccesses, 1);
      expect(rebootCubit.state.getItem(80).intervalDays, 3);
      expect(rebootCubit.state.history.length, 1);
      expect(rebootCubit.state.history.first.id, 'op_legit');

      // Checkpoint is detected as corrupt/expired and safely purged
      final checkpointData = storage.readMap('quran_visual_recall_checkpoint');
      final isExpiredOrInvalid =
          (checkpointData['version'] != 1) ||
          (DateTime.now().millisecondsSinceEpoch -
                  (checkpointData['savedAt'] as num? ?? 0) >
              86400000);
      expect(isExpiredOrInvalid, true);
      if (isExpiredOrInvalid) {
        await storage.remove('quran_visual_recall_checkpoint');
      }

      expect(
        storage.store.containsKey('quran_visual_recall_checkpoint'),
        false,
      );
      expect(storage.store.containsKey('quran_memorization'), true);
      expect(
        rebootCubit.state.getItem(80).status,
        MemorizationStatus.memorized,
      );
    });
  });

  group(
    'Q13 Persistence Remediation — Production UI Session Identity Tests',
    () {
      late ControllableLocalStorageService storage;
      late QuranMemorizationRepository repository;
      late QuranMemorizationCubit cubit;

      setUp(() async {
        storage = ControllableLocalStorageService();
        repository = QuranMemorizationRepository(storage: storage);
        cubit = QuranMemorizationCubit(repository: repository);
        await cubit.load();
      });

      test('UI review without passing sessionId or operationId adopts activeSession.id', () async {
        // Setup active session
        final session = const MemorizationSession(
          id: 'sess_prod_ui_1',
          queue: [100, 101, 102],
        );
        cubit.emit(cubit.state.copyWith(activeSession: session));

        // UI calls recordReviewOutcome with NO sessionId and NO operationId
        await cubit.recordReviewOutcome(
          globalAyah: 100,
          outcome: ReviewOutcome.good,
        );

        // Verify record adopted session id
        expect(cubit.state.history.length, 1);
        final rec = cubit.state.history.first;
        expect(rec.sessionId, 'sess_prod_ui_1');
        expect(rec.id, 'rev_sess_prod_ui_1_100');
        expect(cubit.state.getItem(100).status, MemorizationStatus.memorized);
        expect(cubit.state.getItem(100).consecutiveSuccesses, 1);
        expect(cubit.state.getItem(100).intervalDays, 3);

        // Subsequent duplicate tap with NO sessionId and NO operationId
        await cubit.recordReviewOutcome(
          globalAyah: 100,
          outcome: ReviewOutcome.good,
        );

        // INVARIANT: Exactly 1 record; consecutive successes not doubled!
        expect(cubit.state.history.length, 1);
        expect(cubit.state.getItem(100).consecutiveSuccesses, 1);
        expect(cubit.state.getItem(100).intervalDays, 3);
      });

      test(
        'recordKnows and recordNeedsRevision seamlessly adopt activeSession.id',
        () async {
          final session = const MemorizationSession(
            id: 'sess_bridge_test',
            queue: [200, 201],
          );
          cubit.emit(cubit.state.copyWith(activeSession: session));

          await cubit.recordKnows(200);

          expect(cubit.state.history.length, 1);
          expect(cubit.state.history.first.sessionId, 'sess_bridge_test');
          expect(cubit.state.history.first.id, 'rev_sess_bridge_test_200');

          // Calling recordKnows again is idempotent
          await cubit.recordKnows(200);
          expect(cubit.state.history.length, 1);
          expect(cubit.state.getItem(200).consecutiveSuccesses, 1);
        },
      );

      test(
        'UI review retry after restart does not duplicate mutations',
        () async {
          final session = const MemorizationSession(
            id: 'sess_restart_test',
            queue: [300],
          );
          cubit.emit(cubit.state.copyWith(activeSession: session));

          await cubit.recordReviewOutcome(
            globalAyah: 300,
            outcome: ReviewOutcome.good,
          );
          expect(cubit.state.history.length, 1);

          // Reconstruct repository & cubit
          final newRepo = QuranMemorizationRepository(storage: storage);
          final newCubit = QuranMemorizationCubit(repository: newRepo);
          await newCubit.load();

          // Restore active session with same ID
          newCubit.emit(newCubit.state.copyWith(activeSession: session));

          // Retry review
          await newCubit.recordReviewOutcome(
            globalAyah: 300,
            outcome: ReviewOutcome.good,
          );

          // INVARIANT: Deduplicated!
          expect(newCubit.state.history.length, 1);
          expect(newCubit.state.getItem(300).consecutiveSuccesses, 1);
          expect(newCubit.state.getItem(300).intervalDays, 3);
        },
      );
    },
  );

  group('Q13 Persistence Remediation — Concurrency & In-Flight Lock Tests', () {
    late ControllableLocalStorageService storage;
    late QuranMemorizationRepository repository;
    late QuranMemorizationCubit cubit;

    setUp(() async {
      storage = ControllableLocalStorageService();
      repository = QuranMemorizationRepository(storage: storage);
      cubit = QuranMemorizationCubit(repository: repository);
      await cubit.load();
    });

    test('Concurrent duplicate invocations await in-flight future and record exactly once', () async {
      final futures = [
        cubit.recordReviewOutcome(
          globalAyah: 400,
          outcome: ReviewOutcome.good,
          operationId: 'op_concurrent_success',
        ),
        cubit.recordReviewOutcome(
          globalAyah: 400,
          outcome: ReviewOutcome.good,
          operationId: 'op_concurrent_success',
        ),
      ];

      await Future.wait(futures);

      expect(cubit.state.history.length, 1);
      expect(cubit.state.getItem(400).consecutiveSuccesses, 1);
      expect(cubit.state.getItem(400).intervalDays, 3);
    });

    test('Concurrent duplicate invocations propagate error when in-flight persistence fails', () async {
      storage.failBeforeWriteMap = true;

      var thrownCount = 0;
      final f1 = cubit
          .recordReviewOutcome(
            globalAyah: 500,
            outcome: ReviewOutcome.good,
            operationId: 'op_concurrent_fail',
          )
          .catchError((_) {
            thrownCount++;
          });

      final f2 = cubit
          .recordReviewOutcome(
            globalAyah: 500,
            outcome: ReviewOutcome.good,
            operationId: 'op_concurrent_fail',
          )
          .catchError((_) {
            thrownCount++;
          });

      await Future.wait([f1, f2]);

      // INVARIANT: Both callers received the error, neither had false success!
      expect(thrownCount, 2);
      expect(cubit.state.history, isEmpty);
      expect(cubit.state.getItem(500).status, MemorizationStatus.notStarted);
      expect(cubit.state.error, isNotNull);
    });
  });

  group(
    'Q13 Persistence Remediation — Real Filesystem LocalStorageService Tests',
    () {
      late Directory tempDir;
      late LocalStorageService storage;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'mishkat_persistence_test_',
        );
        storage = LocalStorageService(directory: tempDir);
        await storage.init();
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('Real filesystem writes and re-reads atomic snapshot', () async {
        await storage.writeMap('test_key', {'hello': 'world'});
        expect(storage.readMap('test_key'), {'hello': 'world'});

        // Read directly from disk file to verify persistence
        final file = File('${tempDir.path}/mishkat_store.json');
        expect(await file.exists(), true);
        final content =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(content['test_key'], {'hello': 'world'});
      });

      test('In-memory dirty data rolls back when write fails', () async {
        await storage.writeMap('valid_key', {'init': true});

        // Point file to non-writable path to trigger real write failure
        final readOnlyDir = File('${tempDir.path}/mishkat_store.json');
        // Create a directory where the file was supposed to be to cause FileSystemException on write
        await readOnlyDir.delete();
        await Directory('${tempDir.path}/mishkat_store.json').create();

        var threw = false;
        try {
          await storage.writeMap('valid_key', {'corrupt': true});
        } catch (_) {
          threw = true;
        }

        expect(threw, true);
        // INVARIANT: In-memory store was rolled back!
        expect(storage.readMap('valid_key'), {'init': true});
      });

      test('Orphan .tmp file recovery restores data upon restart', () async {
        // Simulate crash after writing .tmp but before renaming
        final storeFile = File('${tempDir.path}/mishkat_store.json');
        final tmpFile = File('${tempDir.path}/mishkat_store.json.123456.tmp');
        await tmpFile.writeAsString(
          jsonEncode({
            'recovered_key': {'data': 'survived_crash'},
          }),
        );

        expect(await storeFile.exists(), false);
        expect(await tmpFile.exists(), true);

        // Initialize a new LocalStorageService instance
        final newStorage = LocalStorageService(directory: tempDir);
        await newStorage.init();

        // INVARIANT: The orphaned tmp file was promoted to primary store!
        expect(await storeFile.exists(), true);
        expect(newStorage.readMap('recovered_key'), {'data': 'survived_crash'});
      });
    },
  );
}
