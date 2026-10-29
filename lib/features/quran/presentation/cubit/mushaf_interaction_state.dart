import 'package:equatable/equatable.dart';

import '../../data/models/mushaf_layout_models.dart';

/// Represents the interaction and selection state of the interactive Mushaf reader.
class MushafInteractionState extends Equatable {
  const MushafInteractionState({
    this.selectedAyah,
    this.selectedPage,
    this.isActionSheetOpen = false,
    this.playingAyah,
  });

  /// Initial state with no selection or active action sheet.
  const MushafInteractionState.initial() : this();

  /// The currently selected Ayah geometry and metadata, or `null` if none.
  final AyahBounds? selectedAyah;

  /// The Mushaf page number (1..604) where the selection resides.
  final int? selectedPage;

  /// Whether the Ayah Action Sheet is currently presented.
  final bool isActionSheetOpen;

  /// Global Ayah index (1..6236) currently playing audio, separate from selection (Q5 foundation).
  final int? playingAyah;

  /// Whether an Ayah is currently selected.
  bool get hasSelection => selectedAyah != null;

  MushafInteractionState copyWith({
    AyahBounds? selectedAyah,
    int? selectedPage,
    bool? isActionSheetOpen,
    int? playingAyah,
    bool clearSelection = false,
    bool clearPlaying = false,
  }) {
    return MushafInteractionState(
      selectedAyah: clearSelection ? null : (selectedAyah ?? this.selectedAyah),
      selectedPage: clearSelection ? null : (selectedPage ?? this.selectedPage),
      isActionSheetOpen: isActionSheetOpen ?? this.isActionSheetOpen,
      playingAyah: clearPlaying ? null : (playingAyah ?? this.playingAyah),
    );
  }

  @override
  List<Object?> get props => [
    selectedAyah,
    selectedPage,
    isActionSheetOpen,
    playingAyah,
  ];
}
