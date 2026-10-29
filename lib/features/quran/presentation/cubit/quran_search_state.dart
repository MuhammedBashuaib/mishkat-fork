import 'package:equatable/equatable.dart';

import '../../data/models/quran_search_models.dart';

enum QuranSearchStatus { initial, loading, success, empty, error }

class QuranSearchState extends Equatable {
  const QuranSearchState({
    this.status = QuranSearchStatus.initial,
    this.query = '',
    this.filter = QuranSearchFilter.all,
    this.results = QuranSearchResults.empty,
    this.recentSearches = const [],
    this.errorMessage,
  });

  final QuranSearchStatus status;
  final String query;
  final QuranSearchFilter filter;
  final QuranSearchResults results;
  final List<String> recentSearches;
  final String? errorMessage;

  bool get isInitial => status == QuranSearchStatus.initial;
  bool get isLoading => status == QuranSearchStatus.loading;
  bool get isSuccess => status == QuranSearchStatus.success;
  bool get isEmpty => status == QuranSearchStatus.empty;
  bool get isError => status == QuranSearchStatus.error;

  QuranSearchState copyWith({
    QuranSearchStatus? status,
    String? query,
    QuranSearchFilter? filter,
    QuranSearchResults? results,
    List<String>? recentSearches,
    String? errorMessage,
    bool clearError = false,
  }) {
    return QuranSearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      recentSearches: recentSearches ?? this.recentSearches,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    query,
    filter,
    results,
    recentSearches,
    errorMessage,
  ];
}
