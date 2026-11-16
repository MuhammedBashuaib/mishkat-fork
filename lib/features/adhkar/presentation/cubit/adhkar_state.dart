import 'package:equatable/equatable.dart';

import '../../data/models/adhkar_models.dart';

enum AdhkarStatus { initial, loading, ready, failure }

class AdhkarState extends Equatable {
  const AdhkarState({
    this.status = AdhkarStatus.initial,
    this.categories = const [],
    this.customDuas = const [],
    this.nextCustomId = -1,
    this.progress = const {},
    this.countTargets = const {},
    this.query = '',
    this.selectedId,
    this.error,
  });

  final AdhkarStatus status;
  final List<AdhkarCategory> categories;
  final List<AdhkarCategory> customDuas;
  final int nextCustomId;
  List<DhikrItem> get customItems => [
    for (final dua in customDuas) ...dua.items,
  ];
  final Map<int, Map<int, int>> progress;
  final Map<int, Map<int, int>> countTargets;
  final String query;
  final int? selectedId;
  final String? error;

  List<AdhkarCategory> get allCategories => [
    AdhkarCategory(id: 0, name: 'أدعيتي', items: customItems, custom: true),
    for (final category in categories)
      AdhkarCategory(
        id: category.id,
        name: category.name,
        custom: category.custom,
        items: [
          for (var i = 0; i < category.items.length; i++)
            if (category.items[i].countOptions.contains(
              countTargets[category.id]?[i],
            ))
              category.items[i].withCount(countTargets[category.id]![i]!)
            else
              category.items[i],
        ],
      ),
  ];
  AdhkarCategory? categoryById(int id) => (id < 0 ? customDuas : allCategories)
      .where((item) => item.id == id)
      .firstOrNull;

  AdhkarCategory? get selected =>
      selectedId == null ? null : categoryById(selectedId!);

  AdhkarState copyWith({
    AdhkarStatus? status,
    List<AdhkarCategory>? categories,
    List<AdhkarCategory>? customDuas,
    int? nextCustomId,
    Map<int, Map<int, int>>? progress,
    Map<int, Map<int, int>>? countTargets,
    String? query,
    int? selectedId,
    String? error,
  }) => AdhkarState(
    status: status ?? this.status,
    categories: categories ?? this.categories,
    customDuas: customDuas ?? this.customDuas,
    nextCustomId: nextCustomId ?? this.nextCustomId,
    progress: progress ?? this.progress,
    countTargets: countTargets ?? this.countTargets,
    query: query ?? this.query,
    selectedId: selectedId ?? this.selectedId,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [
    status,
    categories,
    customDuas,
    nextCustomId,
    progress,
    countTargets,
    query,
    selectedId,
    error,
  ];
}
