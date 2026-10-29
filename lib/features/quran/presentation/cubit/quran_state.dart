import 'package:equatable/equatable.dart';

import '../../data/models/quran_audio_station.dart';
import '../../data/models/quran_models.dart';
import '../../domain/models/audio_repeat_config.dart';

const _unset = Object();

enum QuranStatus { initial, loading, ready, failure }

enum QuranIndexMode { surahs, juz, bookmarks }

enum QuranAudioStatus { idle, loading, playing, paused, failure }

class QuranState extends Equatable {
  const QuranState({
    this.status = QuranStatus.initial,
    this.data,
    this.mode = QuranIndexMode.surahs,
    this.query = '',
    this.results = const [],
    this.currentPage = 1,
    this.lastRead,
    this.bookmarks = const [],
    this.fontSize = 32,
    this.audioStatus = QuranAudioStatus.idle,
    this.audioGlobalAyah,
    this.activeStation,
    this.repeatConfig = AudioRepeatConfig.defaultConfig,
    this.repeatState = const AudioRepeatState(),
    this.error,
  });

  final QuranStatus status;
  final QuranData? data;
  final QuranIndexMode mode;
  final String query;
  final List<QuranSearchResult> results;
  final int currentPage;
  final QuranPoint? lastRead;
  final List<QuranBookmark> bookmarks;
  final double fontSize;
  final QuranAudioStatus audioStatus;
  final int? audioGlobalAyah;
  final QuranAudioStation? activeStation;
  final AudioRepeatConfig repeatConfig;
  final AudioRepeatState repeatState;
  final String? error;

  bool get isCurrentPageBookmarked =>
      bookmarks.any((item) => item.page == currentPage);

  bool isAyahBookmarked(int globalAyah) =>
      bookmarks.any((item) => item.point.global == globalAyah);

  QuranBookmark? getBookmarkForAyah(int globalAyah) {
    for (final item in bookmarks) {
      if (item.point.global == globalAyah) return item;
    }
    return null;
  }

  List<QuranBookmark> getBookmarksForPage(int page) =>
      bookmarks.where((item) => item.page == page).toList(growable: false);

  QuranState copyWith({
    QuranStatus? status,
    QuranData? data,
    QuranIndexMode? mode,
    String? query,
    List<QuranSearchResult>? results,
    int? currentPage,
    QuranPoint? lastRead,
    List<QuranBookmark>? bookmarks,
    double? fontSize,
    QuranAudioStatus? audioStatus,
    Object? audioGlobalAyah = _unset,
    Object? activeStation = _unset,
    AudioRepeatConfig? repeatConfig,
    AudioRepeatState? repeatState,
    String? error,
    bool clearError = false,
  }) => QuranState(
    status: status ?? this.status,
    data: data ?? this.data,
    mode: mode ?? this.mode,
    query: query ?? this.query,
    results: results ?? this.results,
    currentPage: currentPage ?? this.currentPage,
    lastRead: lastRead ?? this.lastRead,
    bookmarks: bookmarks ?? this.bookmarks,
    fontSize: fontSize ?? this.fontSize,
    audioStatus: audioStatus ?? this.audioStatus,
    audioGlobalAyah: identical(audioGlobalAyah, _unset)
        ? this.audioGlobalAyah
        : audioGlobalAyah as int?,
    activeStation: identical(activeStation, _unset)
        ? this.activeStation
        : activeStation as QuranAudioStation?,
    repeatConfig: repeatConfig ?? this.repeatConfig,
    repeatState: repeatState ?? this.repeatState,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [
    status,
    data,
    mode,
    query,
    results,
    currentPage,
    lastRead,
    bookmarks,
    fontSize,
    audioStatus,
    audioGlobalAyah,
    activeStation,
    repeatConfig,
    repeatState,
    error,
  ];
}
