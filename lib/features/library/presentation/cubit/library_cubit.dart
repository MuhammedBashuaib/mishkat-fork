import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/local_storage_service.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/library_repository.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._repository, this._storage) : super(const LibraryState());
  final LibraryRepository _repository;
  final LocalStorageService _storage;
  int _dataRevision = 0;

  void invalidatePendingOperations() => ++_dataRevision;

  void resetLocalData() {
    invalidatePendingOperations();
    emit(
      LibraryState(
        status: state.books.isEmpty
            ? LibraryStatus.initial
            : LibraryStatus.ready,
        books: state.books,
      ),
    );
  }

  Future<void> load() async {
    final revision = _dataRevision;
    emit(state.copyWith(status: LibraryStatus.loading));
    try {
      final books = await _repository.loadCatalog();
      if (isClosed || revision != _dataRevision) return;
      final saved = _storage.readMap('library');
      emit(
        state.copyWith(
          status: LibraryStatus.ready,
          books: books,
          favorites: (saved['favorites'] as List? ?? const [])
              .map((item) => '$item')
              .toSet(),
          history: (saved['history'] as List? ?? const [])
              .map((item) => '$item')
              .toList(),
          bookmarks: (saved['bookmarks'] as List? ?? const [])
              .map((item) => '$item')
              .toSet(),
          readingPositions: saved['readingPositions'] is Map
              ? {
                  for (final entry
                      in (saved['readingPositions'] as Map).entries)
                    '${entry.key}': '${entry.value}',
                }
              : const {},
        ),
      );
    } on Object catch (error) {
      if (isClosed || revision != _dataRevision) return;
      emit(
        state.copyWith(
          status: LibraryStatus.failure,
          error: 'تعذّر تحميل المكتبة: $error',
        ),
      );
    }
  }

  void setSection(LibrarySection value) => emit(state.copyWith(section: value));
  void search(String value) => emit(state.copyWith(query: value));
  void setCategory(String value) => emit(state.copyWith(category: value));

  List<LibraryBook> filteredBooks() {
    final query = AppFormatters.normalizeArabic(state.query);
    final byCategory = state.category == 'الكل'
        ? state.books
        : state.books.where((book) => book.category == state.category);
    if (query.isEmpty) return byCategory.toList();
    return byCategory
        .where(
          (book) => AppFormatters.normalizeArabic(
            '${book.title} ${book.author} ${book.category}',
          ).contains(query),
        )
        .toList();
  }

  Future<void> openBook(LibraryBook book) async {
    final revision = _dataRevision;
    emit(state.copyWith(status: LibraryStatus.loading, selectedBook: book));
    try {
      final entries = await _repository.loadBook(book);
      if (isClosed || revision != _dataRevision) return;
      final history = [
        book.id,
        ...state.history.where((id) => id != book.id),
      ].take(30).toList();
      emit(
        state.copyWith(
          status: LibraryStatus.ready,
          selectedBook: book,
          entries: entries,
          history: history,
        ),
      );
      await _persist();
    } on Object catch (error) {
      if (isClosed || revision != _dataRevision) return;
      emit(
        state.copyWith(
          status: LibraryStatus.failure,
          error: 'تعذّر فتح الكتاب: $error',
        ),
      );
    }
  }

  Future<void> toggleFavorite(String id) async {
    final favorites = {...state.favorites};
    favorites.contains(id) ? favorites.remove(id) : favorites.add(id);
    emit(state.copyWith(favorites: favorites));
    await _persist();
  }

  String bookmarkKey(String bookId, String entryId) => '$bookId::$entryId';

  bool isBookmarked(String bookId, String entryId) =>
      state.bookmarks.contains(bookmarkKey(bookId, entryId));

  Future<void> toggleBookmark(String bookId, String entryId) async {
    final bookmarks = {...state.bookmarks};
    final key = bookmarkKey(bookId, entryId);
    bookmarks.contains(key) ? bookmarks.remove(key) : bookmarks.add(key);
    emit(state.copyWith(bookmarks: bookmarks));
    await _persist();
  }

  Future<void> saveReadingPosition(String bookId, String entryId) async {
    final positions = {...state.readingPositions, bookId: entryId};
    emit(state.copyWith(readingPositions: positions));
    await _persist();
  }

  int readingIndexFor(String bookId) {
    final entryId = state.readingPositions[bookId];
    if (entryId == null) return 0;
    final index = state.entries.indexWhere((entry) => entry.id == entryId);
    return index < 0 ? 0 : index;
  }

  int bookmarksForBook(String bookId) =>
      state.bookmarks.where((key) => key.startsWith('$bookId::')).length;

  Future<void> _persist() => _storage.writeMap('library', {
    'favorites': state.favorites.toList(),
    'history': state.history,
    'bookmarks': state.bookmarks.toList(),
    'readingPositions': state.readingPositions,
  });
}
