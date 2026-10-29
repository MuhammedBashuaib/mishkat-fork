import '../../../../core/services/local_storage_service.dart';
import '../models/memorization_item.dart';
import '../models/memorization_plan.dart';
import '../models/memorization_session.dart';
import '../models/murajaah_models.dart';

/// Repository responsible for persisting and restoring Quran memorization plans,
/// Ayah-level mastery records, active session checkpoints, and review history.
class QuranMemorizationRepository {
  QuranMemorizationRepository({required this.storage});

  final LocalStorageService storage;
  static const String storageKey = 'quran_memorization';
  static const String historyStorageKey = 'quran_memorization_history';
  static const int maxHistoryRecords = 2000;

  /// Loads all persisted memorization plans, item records, session checkpoint, and review history.
  /// Highly resilient against corrupted JSON or malformed records.
  Future<
    ({
      List<MemorizationPlan> plans,
      Map<int, MemorizationItem> items,
      MemorizationSession? sessionResume,
      List<MemorizationReviewRecord> history,
    })
  >
  loadData() async {
    final rawMap = storage.readMap(storageKey);

    // 1. Parse plans
    final plans = <MemorizationPlan>[];
    final seenPlanIds = <String>{};
    final rawPlans = rawMap['plans'];
    if (rawPlans is List) {
      for (final raw in rawPlans) {
        if (raw is Map) {
          try {
            final plan = MemorizationPlan.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (!seenPlanIds.contains(plan.id)) {
              seenPlanIds.add(plan.id);
              plans.add(plan);
            }
          } catch (_) {
            // Discard malformed plan record safely
          }
        }
      }
    }

    // 2. Parse memorization items (keyed by globalAyah 1..6236)
    final items = <int, MemorizationItem>{};
    final rawItems = rawMap['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          try {
            final item = MemorizationItem.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (item.globalAyah >= 1 && item.globalAyah <= 6236) {
              items[item.globalAyah] = item;
            }
          } catch (_) {
            // Discard malformed item record safely
          }
        }
      }
    } else if (rawItems is Map) {
      for (final entry in rawItems.entries) {
        if (entry.value is Map) {
          try {
            final item = MemorizationItem.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
            if (item.globalAyah >= 1 && item.globalAyah <= 6236) {
              items[item.globalAyah] = item;
            }
          } catch (_) {
            // Discard malformed item record safely
          }
        }
      }
    }

    // 3. Parse session resume checkpoint if present
    MemorizationSession? session;
    final rawSession = rawMap['session'];
    if (rawSession is Map) {
      try {
        session = MemorizationSession.fromJson(
          Map<String, dynamic>.from(rawSession),
        );
        if (session.queue.isEmpty || session.isFinished) {
          session = null;
        }
      } catch (_) {
        session = null;
      }
    }

    // 4. Parse review history (prefer atomic snapshot inside storageKey, fallback to legacy storage key)
    final history = <MemorizationReviewRecord>[];
    final rawHistory = rawMap['history'];
    if (rawHistory is List) {
      for (final raw in rawHistory) {
        if (raw is Map) {
          try {
            history.add(
              MemorizationReviewRecord.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {
            // Skip corrupt history record
          }
        }
      }
    } else {
      history.addAll(await loadHistory());
    }

    return (
      plans: plans,
      items: items,
      sessionResume: session,
      history: history,
    );
  }

  /// Loads review history from atomic snapshot or dedicated storage key with safe fallback.
  Future<List<MemorizationReviewRecord>> loadHistory() async {
    final rawMap = storage.readMap(storageKey);
    final rawHistory = rawMap['history'];
    final rawList = rawHistory is List
        ? rawHistory
        : storage.readList(historyStorageKey);
    final history = <MemorizationReviewRecord>[];
    for (final raw in rawList) {
      if (raw is Map) {
        try {
          final record = MemorizationReviewRecord.fromJson(
            Map<String, dynamic>.from(raw),
          );
          history.add(record);
        } catch (_) {
          // Skip corrupt history record
        }
      }
    }
    return history;
  }

  /// Persists review history capped at [maxHistoryRecords] to maintain local performance.
  Future<void> saveHistory(List<MemorizationReviewRecord> history) async {
    final trimmed = history.length > maxHistoryRecords
        ? history.sublist(history.length - maxHistoryRecords)
        : history;
    final payload = trimmed.map((r) => r.toJson()).toList();

    // Synchronize into atomic storageKey snapshot first if storageKey exists
    final rawMap = storage.readMap(storageKey);
    if (rawMap.isNotEmpty) {
      rawMap['history'] = payload;
      await storage.writeMap(storageKey, rawMap);
    }

    try {
      await storage.writeList(historyStorageKey, payload);
    } catch (_) {
      // Non-fatal if storageKey succeeded
    }
  }

  /// Persists memorization data deterministically and atomically.
  Future<void> saveData({
    required List<MemorizationPlan> plans,
    required Map<int, MemorizationItem> items,
    MemorizationSession? session,
    List<MemorizationReviewRecord>? history,
  }) async {
    List<Map<String, dynamic>>? historyPayload;
    if (history != null) {
      final trimmed = history.length > maxHistoryRecords
          ? history.sublist(history.length - maxHistoryRecords)
          : history;
      historyPayload = trimmed.map((r) => r.toJson()).toList();
    }

    final payload = <String, dynamic>{
      'plans': plans.map((p) => p.toJson()).toList(),
      'items': items.values.map((i) => i.toJson()).toList(),
      if (session != null && !session.isFinished)
        'session': session.toJson()
      else
        'session': null,
      'history': ?historyPayload,
    };

    // Single atomic write containing plans, items, session, AND history in one snapshot!
    await storage.writeMap(storageKey, payload);

    // Also update historyStorageKey for backwards-compatibility with legacy readers
    if (historyPayload != null) {
      try {
        await storage.writeList(historyStorageKey, historyPayload);
      } catch (_) {
        // Non-fatal: history is already durably committed inside primary storageKey
      }
    }
  }

  /// Clears all memorization data (used primarily in tests or reset).
  Future<void> clear() async {
    await storage.remove(storageKey);
    await storage.remove(historyStorageKey);
  }
}
