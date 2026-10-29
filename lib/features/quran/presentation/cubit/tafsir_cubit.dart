import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/tafsir_repository.dart';
import 'tafsir_state.dart';

class TafsirCubit extends Cubit<TafsirState> {
  TafsirCubit({TafsirRepository? repository})
    : _repository = repository ?? TafsirRepository(),
      super(const TafsirState());

  final TafsirRepository _repository;

  /// Loads Tafsir for a specific global Ayah.
  ///
  /// If [sourceId] is omitted, defaults to the repository's default source or currently selected source.
  Future<void> loadTafsir(int globalAyah, {String? sourceId}) async {
    final effectiveSourceId =
        sourceId ??
        state.selectedSource?.id ??
        TafsirRepository.defaultSourceId;

    emit(
      state.copyWith(
        status: TafsirStatus.loading,
        globalAyah: globalAyah,
        clearEntry: true,
        clearError: true,
      ),
    );

    try {
      final package = await _repository.load(sourceId: effectiveSourceId);
      final sources = _repository.getSources();
      final entry = package.getEntry(globalAyah);

      if (entry == null) {
        emit(
          state.copyWith(
            status: TafsirStatus.unavailable,
            selectedSource: package.source,
            availableSources: sources,
            globalAyah: globalAyah,
            clearEntry: true,
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: TafsirStatus.loaded,
            selectedSource: package.source,
            availableSources: sources,
            entry: entry,
            globalAyah: globalAyah,
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: TafsirStatus.error,
          errorMessage: 'تعذر تحميل التفسير. يرجى المحاولة مرة أخرى.',
          globalAyah: globalAyah,
        ),
      );
    }
  }

  /// Switches commentary source and refreshes the current Ayah's Tafsir.
  Future<void> changeSource(String sourceId) async {
    final currentAyah = state.globalAyah;
    if (currentAyah == null) return;
    await loadTafsir(currentAyah, sourceId: sourceId);
  }

  /// Resets state.
  void clear() {
    emit(const TafsirState());
  }
}
