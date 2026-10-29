import 'package:equatable/equatable.dart';

import '../../data/models/tafsir_models.dart';

enum TafsirStatus { initial, loading, loaded, unavailable, error }

class TafsirState extends Equatable {
  const TafsirState({
    this.status = TafsirStatus.initial,
    this.selectedSource,
    this.availableSources = const [],
    this.entry,
    this.globalAyah,
    this.errorMessage,
  });

  final TafsirStatus status;
  final TafsirSource? selectedSource;
  final List<TafsirSource> availableSources;
  final TafsirEntry? entry;
  final int? globalAyah;
  final String? errorMessage;

  bool get isLoading => status == TafsirStatus.loading;
  bool get isLoaded => status == TafsirStatus.loaded;
  bool get isUnavailable => status == TafsirStatus.unavailable;
  bool get isError => status == TafsirStatus.error;

  TafsirState copyWith({
    TafsirStatus? status,
    TafsirSource? selectedSource,
    List<TafsirSource>? availableSources,
    TafsirEntry? entry,
    int? globalAyah,
    String? errorMessage,
    bool clearEntry = false,
    bool clearError = false,
  }) {
    return TafsirState(
      status: status ?? this.status,
      selectedSource: selectedSource ?? this.selectedSource,
      availableSources: availableSources ?? this.availableSources,
      entry: clearEntry ? null : (entry ?? this.entry),
      globalAyah: globalAyah ?? this.globalAyah,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    selectedSource,
    availableSources,
    entry,
    globalAyah,
    errorMessage,
  ];
}
