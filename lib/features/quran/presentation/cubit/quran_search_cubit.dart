import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/quran_models.dart';
import '../../data/models/quran_search_models.dart';
import '../../data/repositories/quran_search_repository.dart';
import 'quran_search_state.dart';

/// Cubit responsible for managing search input, debounce timing, filtering,
/// query execution, and recent search history.
class QuranSearchCubit extends Cubit<QuranSearchState> {
  QuranSearchCubit({
    required QuranData quranData,
    QuranSearchRepository? searchRepository,
    this.debounceDuration = const Duration(milliseconds: 250),
  }) : _data = quranData,
       _searchRepository = searchRepository ?? QuranSearchRepository(),
       super(const QuranSearchState()) {
    _loadRecentSearches();
    // Warm up the index in the background
    _searchRepository.initialize(_data);
  }

  final QuranData _data;
  final QuranSearchRepository _searchRepository;
  final Duration debounceDuration;

  Timer? _debounceTimer;

  void _loadRecentSearches() {
    final recent = _searchRepository.getRecentSearches();
    emit(state.copyWith(recentSearches: recent));
  }

  /// Triggers a search with optional debouncing.
  void onQueryChanged(String query, {bool immediate = false}) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      emit(
        state.copyWith(
          status: QuranSearchStatus.initial,
          query: '',
          results: QuranSearchResults.empty,
        ),
      );
      return;
    }

    emit(state.copyWith(query: query, status: QuranSearchStatus.loading));

    if (immediate) {
      _executeSearch(trimmed);
    } else {
      _debounceTimer = Timer(debounceDuration, () {
        _executeSearch(trimmed);
      });
    }
  }

  void _executeSearch(String query) {
    try {
      final results = _searchRepository.search(
        data: _data,
        query: query,
        filter: state.filter,
      );

      if (results.isEmpty) {
        emit(
          state.copyWith(
            status: QuranSearchStatus.empty,
            results: results,
            clearError: true,
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: QuranSearchStatus.success,
            results: results,
            clearError: true,
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: QuranSearchStatus.error,
          errorMessage: 'حدث خطأ أثناء البحث. يرجى المحاولة مرة أخرى.',
        ),
      );
    }
  }

  /// Saves the search query to history when the user selects a result or commits.
  Future<void> commitSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await _searchRepository.addRecentSearch(trimmed);
    _loadRecentSearches();
  }

  /// Sets the active search filter (All, Ayahs, Surahs, Pages).
  void setFilter(QuranSearchFilter filter) {
    if (state.filter == filter) return;
    emit(state.copyWith(filter: filter));
    if (state.query.trim().isNotEmpty) {
      onQueryChanged(state.query, immediate: true);
    }
  }

  /// Clears the current search query and resets to initial state.
  void clearQuery() {
    _debounceTimer?.cancel();
    emit(
      state.copyWith(
        status: QuranSearchStatus.initial,
        query: '',
        results: QuranSearchResults.empty,
      ),
    );
  }

  /// Removes a single query from recent search history.
  Future<void> removeRecentSearch(String query) async {
    await _searchRepository.removeRecentSearch(query);
    _loadRecentSearches();
  }

  /// Clears all recent searches.
  Future<void> clearRecentSearches() async {
    await _searchRepository.clearRecentSearches();
    _loadRecentSearches();
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
