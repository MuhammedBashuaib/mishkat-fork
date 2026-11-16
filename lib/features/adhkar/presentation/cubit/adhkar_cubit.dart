import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_storage_service.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../data/models/adhkar_models.dart';
import '../../data/repositories/adhkar_repository.dart';
import 'adhkar_state.dart';

class AdhkarCubit extends Cubit<AdhkarState> {
  AdhkarCubit(this._repository, this._storage) : super(const AdhkarState());
  final AdhkarRepository _repository;
  final LocalStorageService _storage;
  int _loadRevision = 0;

  void invalidatePendingOperations() => ++_loadRevision;

  void resetLocalData() {
    invalidatePendingOperations();
    emit(
      AdhkarState(
        status: state.categories.isEmpty
            ? AdhkarStatus.initial
            : AdhkarStatus.ready,
        categories: state.categories,
      ),
    );
  }

  Future<void> load() async {
    final revision = ++_loadRevision;
    emit(state.copyWith(status: AdhkarStatus.loading));
    try {
      final categories = await _repository.load();
      if (isClosed || revision != _loadRevision) return;
      final saved = _storage.readMap('adhkar');
      final needsCustomMigration = saved['customDuas'] is! List;
      final customDuas = <AdhkarCategory>[
        if (!needsCustomMigration)
          for (final item in saved['customDuas'] as List)
            AdhkarCategory.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
      final progress = <int, Map<int, int>>{};
      final countTargets = <int, Map<int, int>>{};
      if (saved['countTargets'] is Map) {
        for (final category in (saved['countTargets'] as Map).entries) {
          if (category.value is Map) {
            countTargets[int.parse('${category.key}')] = {
              for (final entry in (category.value as Map).entries)
                int.parse('${entry.key}'): (entry.value as num).toInt(),
            };
          }
        }
      }
      if (saved['progress'] is Map) {
        for (final entry in (saved['progress'] as Map).entries) {
          if (entry.value is Map) {
            progress[int.tryParse('${entry.key}') ?? 0] = {
              for (final value in (entry.value as Map).entries)
                int.tryParse('${value.key}') ?? 0:
                    (value.value as num?)?.toInt() ?? 0,
            };
          }
        }
      }
      final today = _dayKey(DateTime.now());
      final shouldResetDailyWirds = saved['dailyDate'] != today;
      if (shouldResetDailyWirds) {
        progress
          ..remove(1)
          ..remove(133);
      }
      final schemaVersion = (saved['schemaVersion'] as num?)?.toInt() ?? 1;
      final needsMigration = schemaVersion < 3;
      final old = progress[1];
      if (schemaVersion < 2 && old != null) {
        // Morning card 18 was merged into card 17. Keep the larger count,
        // never add the two narrations together, and shift subsequent cards.
        final ten = old[17] ?? 0;
        final hundred = old[18] ?? 0;
        progress[1] = {
          for (final entry in old.entries)
            if (entry.key < 17)
              entry.key: entry.value
            else if (entry.key > 18)
              entry.key - 1: entry.value,
          17: ten > hundred ? ten : hundred,
        };
        if (hundred > 0) countTargets.putIfAbsent(1, () => {})[17] = 100;
      }
      if (schemaVersion < 3) {
        for (final categoryId in const [1, 133]) {
          final previousProgress = progress[categoryId];
          if (previousProgress != null) {
            // Each repetition of the combined card included all three surahs.
            // Carry it to each new card, then move the remaining saved counts.
            progress[categoryId] = {
              for (final entry in previousProgress.entries)
                if (entry.key == 1)
                  for (var index = 1; index <= 3; index++)
                    index: entry.value.clamp(0, 3)
                else
                  (entry.key > 1 ? entry.key + 2 : entry.key): entry.value,
            };
          }
          final previousTargets = countTargets[categoryId];
          if (previousTargets != null) {
            // Targets survive the daily reset, so migrate them independently.
            countTargets[categoryId] = {
              for (final entry in previousTargets.entries)
                (entry.key > 1 ? entry.key + 2 : entry.key): entry.value,
            };
          }
        }
      }
      if (needsCustomMigration) {
        final legacyProgress = progress.remove(0) ?? const <int, int>{};
        final legacyTargets = countTargets.remove(0) ?? const <int, int>{};
        final legacyItems = saved['custom'] as List? ?? const [];
        for (final entry in legacyItems.indexed) {
          if (entry.$2 is! Map) continue;
          final item = DhikrItem.fromJson(
            Map<String, dynamic>.from(entry.$2 as Map),
          );
          final id = -entry.$1 - 1;
          customDuas.add(
            AdhkarCategory(
              id: id,
              name: item.title.trim().isEmpty ? 'دعاء ${-id}' : item.title,
              items: [item],
              custom: true,
            ),
          );
          if (legacyProgress.containsKey(entry.$1)) {
            progress[id] = {0: legacyProgress[entry.$1]!};
          }
          if (legacyTargets.containsKey(entry.$1)) {
            countTargets[id] = {0: legacyTargets[entry.$1]!};
          }
        }
      }
      var nextCustomId = (saved['nextCustomId'] as num?)?.toInt() ?? -1;
      if (nextCustomId >= 0) nextCustomId = -1;
      for (final dua in customDuas) {
        if (!dua.custom || dua.id >= 0) {
          throw const FormatException('معرّف الدعاء الخاص غير صالح');
        }
        if (dua.id <= nextCustomId) nextCustomId = dua.id - 1;
      }
      emit(
        state.copyWith(
          status: AdhkarStatus.ready,
          categories: categories,
          customDuas: customDuas,
          nextCustomId: nextCustomId,
          progress: progress,
          countTargets: countTargets,
        ),
      );
      if (shouldResetDailyWirds || needsMigration || needsCustomMigration) {
        await _persist();
      }
    } on Object catch (error) {
      if (isClosed || revision != _loadRevision) return;
      emit(
        state.copyWith(
          status: AdhkarStatus.failure,
          error: 'تعذّر تحميل الأذكار: $error',
        ),
      );
    }
  }

  void search(String value) => emit(state.copyWith(query: value));
  void select(int id) => emit(state.copyWith(selectedId: id));

  List<AdhkarCategory> filteredCategories() {
    final query = AppFormatters.normalizeArabic(state.query);
    if (query.isEmpty) return state.allCategories;
    return state.allCategories.where((category) {
      if (AppFormatters.normalizeArabic(category.name).contains(query)) {
        return true;
      }
      if (category.id == 0 &&
          state.customDuas.any(
            (dua) => AppFormatters.normalizeArabic(dua.name).contains(query),
          )) {
        return true;
      }
      return category.items.any(
        (item) =>
            AppFormatters.normalizeArabic(item.text).contains(query) ||
            AppFormatters.normalizeArabic(item.title).contains(query),
      );
    }).toList();
  }

  int countFor(int categoryId, int index) =>
      state.progress[categoryId]?[index] ?? 0;

  Future<void> setCountTarget(int categoryId, int index, int target) async {
    final item = state.categoryById(categoryId)!.items[index];
    if (!item.countOptions.contains(target)) return;
    final targets = {
      for (final entry in state.countTargets.entries)
        entry.key: Map<int, int>.from(entry.value),
    };
    targets.putIfAbsent(categoryId, () => {})[index] = target;
    // Preserve repetitions when switching targets; only an explicit reset
    // should discard recitations the user has already counted.
    emit(state.copyWith(countTargets: targets));
    await _persist();
  }

  Future<void> increment(int categoryId, int index) async {
    final category = state.categoryById(categoryId)!;
    final target = category.items[index].count;
    if (countFor(categoryId, index) >= target) return;
    final progress = _copyProgress();
    final categoryProgress = progress.putIfAbsent(
      categoryId,
      () => <int, int>{},
    );
    categoryProgress[index] = ((categoryProgress[index] ?? 0) + 1).clamp(
      0,
      target,
    );
    emit(state.copyWith(progress: progress));
    await _persist();
  }

  Future<void> reset(int categoryId, int index) async {
    final progress = _copyProgress();
    progress.putIfAbsent(categoryId, () => <int, int>{})[index] = 0;
    emit(state.copyWith(progress: progress));
    await _persist();
  }

  Future<void> resetCategory(int categoryId) async {
    final progress = _copyProgress()..remove(categoryId);
    emit(state.copyWith(progress: progress));
    await _persist();
  }

  Future<int> saveCustomCards({
    int? duaId,
    required String title,
    required List<DhikrItem> items,
  }) {
    final submittedItems = List<DhikrItem>.of(items);
    return _queueCustom(() async {
      if (submittedItems.isEmpty) {
        throw ArgumentError.value(items, 'items', 'أضف بطاقة واحدة على الأقل');
      }
      final cards = <DhikrItem>[];
      for (final item in submittedItems) {
        if (item.text.trim().isEmpty) {
          throw ArgumentError.value(item.text, 'text', 'نص كل بطاقة مطلوب');
        }
        if (item.count < 1 || item.count > 10000) {
          throw ArgumentError.value(
            item.count,
            'count',
            'عدد مرات التكرار يجب أن يكون بين 1 و10000',
          );
        }
        cards.add(
          DhikrItem(
            title: item.title.trim(),
            text: item.text.trim(),
            count: item.count,
          ),
        );
      }
      final id = duaId ?? state.nextCustomId;
      final customDuas = [...state.customDuas];
      if (duaId == null) {
        customDuas.add(
          AdhkarCategory(
            id: id,
            name: title.trim().isEmpty ? 'دعاء ${-id}' : title.trim(),
            items: cards,
            custom: true,
          ),
        );
      } else {
        final index = _customIndex(duaId);
        final dua = customDuas[index];
        customDuas[index] = dua.copyWith(items: [...dua.items, ...cards]);
      }
      await _commitCustom(
        state.copyWith(
          customDuas: customDuas,
          nextCustomId: duaId == null ? id - 1 : state.nextCustomId,
        ),
      );
      return id;
    });
  }

  Future<int> saveCustom({
    int? duaId,
    int? index,
    required String title,
    required String text,
    required int count,
  }) => _queueCustom(() async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'نص الدعاء مطلوب');
    }
    if (duaId == null && index != null) {
      throw ArgumentError('يجب تحديد الدعاء عند تعديل بطاقة');
    }
    final value = DhikrItem(
      title: title.trim(),
      text: text.trim(),
      count: count.clamp(1, 10000),
    );
    final customDuas = [...state.customDuas];
    final progress = _copyProgress();
    final id = duaId ?? state.nextCustomId;
    if (duaId == null) {
      customDuas.add(
        AdhkarCategory(
          id: id,
          name: value.title.isEmpty ? 'دعاء ${-id}' : value.title,
          items: [value],
          custom: true,
        ),
      );
    } else {
      final duaIndex = _customIndex(duaId);
      final dua = customDuas[duaIndex];
      final items = [...dua.items];
      if (index == null) {
        items.add(value);
      } else {
        if (items[index].text != value.text) {
          progress[duaId]?.remove(index);
        }
        items[index] = value;
      }
      customDuas[duaIndex] = dua.copyWith(items: items);
    }
    await _commitCustom(
      state.copyWith(
        customDuas: customDuas,
        progress: progress,
        nextCustomId: duaId == null ? id - 1 : state.nextCustomId,
      ),
    );
    return id;
  });

  Future<void> deleteCustom(int index, {required int duaId}) =>
      _queueCustom(() async {
        final customDuas = [...state.customDuas];
        final duaIndex = _customIndex(duaId);
        final dua = customDuas[duaIndex];
        final items = [...dua.items]..removeAt(index);
        customDuas[duaIndex] = dua.copyWith(items: items);
        final progress = _copyProgress();
        progress[duaId] = _withoutCard(progress[duaId] ?? const {}, index);
        final targets = Map<int, Map<int, int>>.from(state.countTargets);
        if (targets.containsKey(duaId)) {
          targets[duaId] = _withoutCard(targets[duaId]!, index);
        }
        await _commitCustom(
          state.copyWith(
            customDuas: customDuas,
            progress: progress,
            countTargets: targets,
          ),
        );
      });

  Future<void> renameCustomDua(int duaId, String name) =>
      _queueCustom(() async {
        if (name.trim().isEmpty) {
          throw ArgumentError.value(name, 'name', 'عنوان الدعاء مطلوب');
        }
        final customDuas = [...state.customDuas];
        final index = _customIndex(duaId);
        customDuas[index] = customDuas[index].copyWith(name: name.trim());
        await _commitCustom(state.copyWith(customDuas: customDuas));
      });

  Future<void> deleteCustomDua(int duaId) => _queueCustom(() async {
    final customDuas = [...state.customDuas]..removeAt(_customIndex(duaId));
    final progress = _copyProgress()..remove(duaId);
    final targets = Map<int, Map<int, int>>.from(state.countTargets)
      ..remove(duaId);
    await _commitCustom(
      state.copyWith(
        customDuas: customDuas,
        progress: progress,
        countTargets: targets,
        selectedId: state.selectedId == duaId ? 0 : state.selectedId,
      ),
    );
  });

  int _customIndex(int duaId) {
    final index = state.customDuas.indexWhere((dua) => dua.id == duaId);
    if (index < 0) throw StateError('الدعاء غير موجود');
    return index;
  }

  Map<int, int> _withoutCard(Map<int, int> values, int index) => {
    for (final entry in values.entries)
      if (entry.key < index)
        entry.key: entry.value
      else if (entry.key > index)
        entry.key - 1: entry.value,
  };

  Future<void>? _pendingCustomWrite;

  Future<T> _queueCustom<T>(Future<T> Function() action) {
    final revision = _loadRevision;
    Future<T> run() {
      if (isClosed || revision != _loadRevision) {
        throw StateError('أُلغيت العملية بعد تحديث البيانات');
      }
      return action();
    }

    final previous = _pendingCustomWrite;
    final result = previous == null
        ? Future<T>.sync(run)
        : previous.then((_) => run());
    // Keep later edits usable even if one disk write fails.
    late final Future<void> completion;
    void finish() {
      if (identical(_pendingCustomWrite, completion)) {
        _pendingCustomWrite = null;
      }
    }

    completion = result.then<void>(
      (_) => finish(),
      onError: (Object _) => finish(),
    );
    _pendingCustomWrite = completion;
    return result;
  }

  Future<void> _commitCustom(AdhkarState candidate) async {
    final revision = _loadRevision;
    final before = state;
    var observed = before;
    var saved = candidate;
    while (true) {
      await _persist(saved);
      if (isClosed || revision != _loadRevision) return;
      if (!identical(state.progress, observed.progress) ||
          !identical(state.countTargets, observed.countTargets)) {
        // Counting remains immediate while a custom edit is saving. Reconcile
        // unrelated counters and persist again if one changed during the write.
        observed = state;
        saved = candidate.copyWith(
          progress: _mergeCustomMapChanges(
            before.progress,
            candidate.progress,
            observed.progress,
          ),
          countTargets: _mergeCustomMapChanges(
            before.countTargets,
            candidate.countTargets,
            observed.countTargets,
          ),
        );
        continue;
      }
      emit(
        saved.copyWith(
          query: state.query,
          selectedId: state.selectedId == before.selectedId
              ? candidate.selectedId
              : state.selectedId,
        ),
      );
      return;
    }
  }

  Map<int, Map<int, int>> _mergeCustomMapChanges(
    Map<int, Map<int, int>> before,
    Map<int, Map<int, int>> edited,
    Map<int, Map<int, int>> current,
  ) {
    final merged = Map<int, Map<int, int>>.from(current);
    for (final id in {...before.keys, ...edited.keys}) {
      if (mapEquals(before[id], edited[id])) continue;
      if (edited.containsKey(id)) {
        merged[id] = edited[id]!;
      } else {
        merged.remove(id);
      }
    }
    return merged;
  }

  Map<int, Map<int, int>> _copyProgress() => {
    for (final entry in state.progress.entries)
      entry.key: Map<int, int>.from(entry.value),
  };

  Future<void> _persist([AdhkarState? candidate]) {
    final saved = candidate ?? state;
    return _storage.writeMap('adhkar', {
      'schemaVersion': 3,
      'customDuas': saved.customDuas.map((dua) => dua.toJson()).toList(),
      'nextCustomId': saved.nextCustomId,
      'dailyDate': _dayKey(DateTime.now()),
      'countTargets': {
        for (final category in saved.countTargets.entries)
          '${category.key}': {
            for (final value in category.value.entries)
              '${value.key}': value.value,
          },
      },
      'progress': {
        for (final category in saved.progress.entries)
          '${category.key}': {
            for (final value in category.value.entries)
              '${value.key}': value.value,
          },
      },
    });
  }

  String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
