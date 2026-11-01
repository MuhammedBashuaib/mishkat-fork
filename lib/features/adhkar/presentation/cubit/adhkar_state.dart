import 'package:equatable/equatable.dart';

import '../../data/models/adhkar_models.dart';

enum AdhkarStatus { initial, loading, ready, failure }

class AdhkarState extends Equatable {
  const AdhkarState({
    this.status = AdhkarStatus.initial,
    this.categories = const [],
    this.customItems = const [],
    this.progress = const {},
    this.countTargets = const {},
    this.query = '',
    this.selectedId,
    this.error,
  });

  final AdhkarStatus status;
  final List<AdhkarCategory> categories;
  final List<DhikrItem> customItems;
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
  AdhkarCategory? get selected =>
      allCategories.where((item) => item.id == selectedId).firstOrNull;

  AdhkarState copyWith({
    AdhkarStatus? status,
    List<AdhkarCategory>? categories,
    List<DhikrItem>? customItems,
    Map<int, Map<int, int>>? progress,
    Map<int, Map<int, int>>? countTargets,
    String? query,
    int? selectedId,
    String? error,
  }) => AdhkarState(
    status: status ?? this.status,
    categories: categories ?? this.categories,
    customItems: customItems ?? this.customItems,
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
    customItems,
    progress,
    countTargets,
    query,
    selectedId,
    error,
  ];
}
