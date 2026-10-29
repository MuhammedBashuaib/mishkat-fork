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
        customDhikrTarget: state.dhikrId == tasbihCustomDhikrId
            ? value
            : state.customDhikrTarget,
      ),
    );
    await _persist();
  }

  Future<void> selectDhikr(String id) async {
    if (id == tasbihCustomDhikrId && state.customDhikrText.isNotEmpty) {
      if (state.dhikrId == id) return;
      emit(
        _withCurrentDay(state)
            .copyWith(count: 0, dhikrId: id, target: state.customDhikrTarget),
      );
      await _persist();
      return;
    }
    final selected = tasbihDhikrOptions
        .where((item) => item.id == id)
        .firstOrNull;
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

  Future<void> setCustomDhikr(String text, {required int target}) async {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.length > 160) return;
    if (target < 1 || target > 9999) return;
    emit(
      _withCurrentDay(state).copyWith(
        count: 0,
        dhikrId: tasbihCustomDhikrId,
        target: target,
        customDhikrText: normalized,
        customDhikrTarget: target,
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
      'customDhikrText': value.customDhikrText,
      'customDhikrTarget': value.customDhikrTarget,
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
    final customDhikrText = saved['customDhikrText'] is String
        ? (saved['customDhikrText'] as String).trim()
        : '';
    final hasValidCustomDhikr =
        rawDhikrId == tasbihCustomDhikrId && customDhikrText.isNotEmpty;
    final validDhikrId =
        hasValidCustomDhikr ||
            tasbihDhikrOptions.any((item) => item.id == rawDhikrId)
        ? rawDhikrId
        : tasbihDhikrOptions.first.id;
    final target = _readPositiveInt(saved['target'], 33).clamp(1, 9999);
    final customDhikrTarget = _readPositiveInt(
      saved['customDhikrTarget'],
      33,
    ).clamp(1, 9999);
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
      customDhikrText: customDhikrText,
      customDhikrTarget: customDhikrTarget,
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
