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
      final custom = <DhikrItem>[
        if (saved['custom'] is List)
          for (final item in saved['custom'] as List)
            if (item is Map)
              DhikrItem.fromJson(Map<String, dynamic>.from(item)),
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
      final needsMigration = saved['schemaVersion'] != 2;
      final old = progress[1];
      if (needsMigration && old != null) {
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
      emit(
        state.copyWith(
          status: AdhkarStatus.ready,
          categories: categories,
          customItems: custom,
          progress: progress,
          countTargets: countTargets,
        ),
      );
      if (shouldResetDailyWirds || needsMigration) await _persist();
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
      return category.items.any(
        (item) => AppFormatters.normalizeArabic(item.text).contains(query),
      );
    }).toList();
  }

  int countFor(int categoryId, int index) =>
      state.progress[categoryId]?[index] ?? 0;

  Future<void> setCountTarget(int categoryId, int index, int target) async {
    final item = state.allCategories
        .firstWhere((category) => category.id == categoryId)
        .items[index];
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
    final category = state.allCategories.firstWhere(
      (item) => item.id == categoryId,
    );
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

  Future<void> saveCustom({
    int? index,
    required String title,
    required String text,
    required int count,
  }) async {
    final items = [...state.customItems];
    final value = DhikrItem(
      title: title.trim(),
      text: text.trim(),
      count: count.clamp(1, 10000),
    );
    if (index == null) {
      items.add(value);
    } else {
      items[index] = value;
    }
    emit(state.copyWith(customItems: items));
    await _persist();
  }

  Future<void> deleteCustom(int index) async {
    final items = [...state.customItems]..removeAt(index);
    final progress = _copyProgress();
    final existing = progress[0] ?? <int, int>{};
    progress[0] = {
      for (final entry in existing.entries)
        if (entry.key < index)
          entry.key: entry.value
        else if (entry.key > index)
          entry.key - 1: entry.value,
    };
    emit(state.copyWith(customItems: items, progress: progress));
    await _persist();
  }

  Map<int, Map<int, int>> _copyProgress() => {
    for (final entry in state.progress.entries)
      entry.key: Map<int, int>.from(entry.value),
  };

  Future<void> _persist() => _storage.writeMap('adhkar', {
    'schemaVersion': 2,
    'custom': state.customItems.map((item) => item.toJson()).toList(),
    'dailyDate': _dayKey(DateTime.now()),
    'countTargets': {
      for (final category in state.countTargets.entries)
        '${category.key}': {
          for (final value in category.value.entries)
            '${value.key}': value.value,
        },
    },
    'progress': {
      for (final category in state.progress.entries)
        '${category.key}': {
          for (final value in category.value.entries)
            '${value.key}': value.value,
        },
    },
  });

  String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
