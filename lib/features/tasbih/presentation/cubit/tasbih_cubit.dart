import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_storage_service.dart';
import 'tasbih_state.dart';

class TasbihCubit extends Cubit<TasbihState> {
  TasbihCubit(this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(_restore(_storage, (now ?? DateTime.now)()));

  static const _sessionKey = 'tasbihSessionV2';
  final LocalStorageService _storage;
  final DateTime Function() _now;

  /// Reset the complete session, including custom entries and lifetime totals.
  /// Persistence is cleared by the application-wide reset coordinator.
  void resetLocalData() => emit(TasbihState(sessionDate: _dateKey(_now())));

  Future<void> increment() async {
    final current = _withCurrentDay(state);
    emit(
      current.copyWith(
        count: current.count + 1,
        total: current.total + 1,
        todayTotal: current.todayTotal + 1,
      ),
    );
    await _persist();
  }

  Future<void> undo() async {
    final current = _withCurrentDay(state);
    if (current.count == 0) return;
    emit(
      current.copyWith(
        count: current.count - 1,
        total: (current.total - 1).clamp(0, current.total),
        todayTotal: (current.todayTotal - 1).clamp(0, current.todayTotal),
      ),
    );
    await _persist();
  }

  Future<void> reset() async {
    emit(_withCurrentDay(state).copyWith(count: 0));
    await _persist();
  }

  Future<void> setTarget(int value) async {
    if (value < 1 || value > 9999 || value == state.target) return;
    emit(
      _withCurrentDay(state).copyWith(
        target: value,
        customDhikrs: List.unmodifiable([
          for (final item in state.customDhikrs)
            if (item.id == state.dhikrId)
              TasbihDhikr(id: item.id, text: item.text, suggestedTarget: value)
            else
              item,
        ]),
      ),
    );
    await _persist();
  }

  Future<void> selectDhikr(String id) async {
    final selected = [
      ...tasbihDhikrOptions,
      ...state.customDhikrs,
    ].where((item) => item.id == id).firstOrNull;
    if (selected == null || selected.id == state.dhikrId) return;
    emit(
      _withCurrentDay(state).copyWith(
        count: 0,
        dhikrId: selected.id,
        target: selected.suggestedTarget,
      ),
    );
    await _persist();
  }

  /// Adds a new entry, or edits the entry identified by [id].
  Future<void> setCustomDhikr(
    String text, {
    required int target,
    String? id,
  }) async {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.length > 160) return;
    if (target < 1 || target > 9999) return;
    final existing = state.customDhikrs
        .where((item) => item.id == id)
        .firstOrNull;
    if (id != null && existing == null) return;
    if (existing?.text == normalized && existing?.suggestedTarget == target) {
      return;
    }
    var entryId = id ?? 'custom_${_now().microsecondsSinceEpoch}';
    if (id == null) {
      final base = entryId;
      var suffix = 0;
      while (state.customDhikrs.any((item) => item.id == entryId)) {
        entryId = '${base}_${++suffix}';
      }
    }
    final entry = TasbihDhikr(
      id: entryId,
      text: normalized,
      suggestedTarget: target,
    );
    final activates = id == null || state.dhikrId == id;
    emit(
      _withCurrentDay(state).copyWith(
        count: activates ? 0 : state.count,
        dhikrId: activates ? entryId : state.dhikrId,
        target: activates ? target : state.target,
        customDhikrs: List.unmodifiable([
          for (final item in state.customDhikrs)
            if (item.id == entryId) entry else item,
          if (id == null) entry,
        ]),
      ),
    );
    await _persist();
  }

  Future<void> deleteCustomDhikr(String id) async {
    if (!state.customDhikrs.any((item) => item.id == id)) return;
    final isActive = state.dhikrId == id;
    emit(
      _withCurrentDay(state).copyWith(
        customDhikrs: List.unmodifiable(
          state.customDhikrs.where((item) => item.id != id),
        ),
        dhikrId: isActive ? tasbihDhikrOptions.first.id : state.dhikrId,
        target: isActive
            ? tasbihDhikrOptions.first.suggestedTarget
            : state.target,
        count: isActive ? 0 : state.count,
      ),
    );
    await _persist();
  }

  Future<void> toggleHaptics() async {
    emit(state.copyWith(hapticsEnabled: !state.hapticsEnabled));
    await _persist();
  }

  Future<void> toggleCompletionSound() async {
    emit(state.copyWith(completionSoundEnabled: !state.completionSoundEnabled));
    await _persist();
  }

  Future<void> _persist() async {
    final value = state;
    await _storage.writeMap(_sessionKey, {
      'count': value.count,
      'total': value.total,
      'todayTotal': value.todayTotal,
      'target': value.target,
      'dhikrId': value.dhikrId,
      'hapticsEnabled': value.hapticsEnabled,
      'completionSoundEnabled': value.completionSoundEnabled,
      'customDhikrs': [
        for (final item in value.customDhikrs)
          {'id': item.id, 'text': item.text, 'target': item.suggestedTarget},
      ],
      'sessionDate': value.sessionDate,
    });
  }

  TasbihState _withCurrentDay(TasbihState value) {
    final today = _dateKey(_now());
    if (value.sessionDate == today) return value;
    return value.copyWith(todayTotal: 0, sessionDate: today);
  }

  static TasbihState _restore(LocalStorageService storage, DateTime now) {
    final saved = storage.readMap(_sessionKey);
    final today = _dateKey(now);
    final savedDate = saved['sessionDate'] as String? ?? today;
    final rawDhikrId = saved['dhikrId'] as String? ?? 'subhan_allah';
    final customDhikrs = <TasbihDhikr>[];
    final rawCustom = saved['customDhikrs'];
    if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is! Map) continue;
        final id = item['id'];
        final text = item['text'];
        final target = item['target'];
        if (id is! String ||
            (id != tasbihCustomDhikrId && !id.startsWith('custom_')) ||
            customDhikrs.any((entry) => entry.id == id) ||
            text is! String ||
            text.trim().isEmpty ||
            text.length > 160 ||
            target is! int ||
            target < 1 ||
            target > 9999) {
          continue;
        }
        customDhikrs.add(
          TasbihDhikr(
            id: id,
            text: text.trim().replaceAll(RegExp(r'\s+'), ' '),
            suggestedTarget: target,
          ),
        );
      }
    } else {
      // Migrate the single custom entry without losing its active session.
      final text = saved['customDhikrText'];
      if (text is String && text.trim().isNotEmpty) {
        customDhikrs.add(
          TasbihDhikr(
            id: tasbihCustomDhikrId,
            text: text.trim(),
            suggestedTarget: _readPositiveInt(
              saved['customDhikrTarget'],
              33,
            ).clamp(1, 9999),
          ),
        );
      }
    }
    final validDhikrId =
        [
          ...tasbihDhikrOptions,
          ...customDhikrs,
        ].any((item) => item.id == rawDhikrId)
        ? rawDhikrId
        : tasbihDhikrOptions.first.id;
    final target = _readPositiveInt(saved['target'], 33).clamp(1, 9999);
    final total = _readPositiveInt(
      saved['total'],
      storage.readInt('tasbihTotal'),
    );

    return TasbihState(
      count: _readPositiveInt(saved['count']),
      total: total,
      todayTotal: savedDate == today
          ? _readPositiveInt(saved['todayTotal'])
          : 0,
      target: target,
      dhikrId: validDhikrId,
      hapticsEnabled: saved['hapticsEnabled'] is bool
          ? saved['hapticsEnabled'] as bool
          : true,
      completionSoundEnabled: saved['completionSoundEnabled'] is bool
          ? saved['completionSoundEnabled'] as bool
          : true,
      customDhikrs: List.unmodifiable(customDhikrs),
      sessionDate: today,
    );
  }

  static int _readPositiveInt(Object? value, [int fallback = 0]) {
    if (value is! num) return fallback;
    return value.toInt().clamp(0, 1 << 31);
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
