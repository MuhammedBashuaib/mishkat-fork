import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/mushaf_layout_models.dart';
import '../../data/repositories/mushaf_layout_repository.dart';
import 'mushaf_interaction_state.dart';

/// Cubit responsible for managing Ayah selection, highlighting, and Action Sheet lifecycle.
///
/// Keeps the selection state cleanly decoupled from [QuranCubit] to avoid unnecessary
/// page-level rebuilds during reader touch interactions.
class MushafInteractionCubit extends Cubit<MushafInteractionState> {
  MushafInteractionCubit({MushafLayoutRepository? layoutRepository})
    : _layoutRepository = layoutRepository ?? MushafLayoutRepository.instance,
      super(const MushafInteractionState.initial());

  final MushafLayoutRepository _layoutRepository;

  /// Underlying layout repository providing O(1) page/Ayah geometry lookups.
  MushafLayoutRepository get layoutRepository => _layoutRepository;

  /// Ensures layout geometry metadata is loaded in memory.
  Future<void> load() async {
    if (!_layoutRepository.isLoaded) {
      await _layoutRepository.load();
    }
  }

  /// Sets the currently selected [ayah] on its corresponding Mushaf page.
  /// Optionally requests opening the [AyahActionSheet].
  void selectAyah(AyahBounds ayah, {bool openActionSheet = false}) {
    emit(
      state.copyWith(
        selectedAyah: ayah,
        selectedPage: ayah.page,
        isActionSheetOpen: openActionSheet,
      ),
    );
  }

  /// Selects an Ayah by its 1-based [globalAyah] index (1..6236).
  /// Resolves geometry via [_layoutRepository].
  void selectAyahByGlobal(int globalAyah, {bool openActionSheet = false}) {
    final ayah = _layoutRepository.getAyah(globalAyah);
    if (ayah != null) {
      selectAyah(ayah, openActionSheet: openActionSheet);
    }
  }

  /// Clears the current Ayah selection.
  void clearSelection() {
    if (state.hasSelection || state.isActionSheetOpen) {
      emit(state.copyWith(clearSelection: true, isActionSheetOpen: false));
    }
  }

  /// Updates whether the Ayah Action Sheet modal is open.
  void setActionSheetOpen(bool isOpen) {
    if (state.isActionSheetOpen != isOpen) {
      emit(state.copyWith(isActionSheetOpen: isOpen));
    }
  }

  /// Sets or clears the currently playing global Ayah for audio highlighting (Q5 foundation).
  void setPlayingAyah(int? globalAyah) {
    emit(
      state.copyWith(playingAyah: globalAyah, clearPlaying: globalAyah == null),
    );
  }

  /// Clears selection if the user navigates away from the page of the current selection.
  void onPageChanged(int newPage) {
    if (state.selectedPage != null && state.selectedPage != newPage) {
      clearSelection();
    }
  }
}
