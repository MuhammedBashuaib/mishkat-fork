import 'package:equatable/equatable.dart';

import '../../data/models/quran_audio_station.dart';
import '../../data/models/quran_models.dart';
import '../../domain/models/audio_repeat_config.dart';

const _unset = Object();

enum QuranStatus { initial, loading, ready, failure }

enum QuranIndexMode { surahs, juz, bookmarks }

enum QuranAudioStatus { idle, loading, playing, paused, failure }

enum QuranListeningMode { once, repeat, next }

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
    this.audioSurah,
    this.audioWordIndex,
    this.readerSelectedAyah,
    this.listeningMode = QuranListeningMode.once,
    this.sleepTimerRemaining,
    this.playbackSpeed = 1,
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
  final int? audioSurah;
  final int? audioWordIndex;
  final int? readerSelectedAyah;
  final QuranListeningMode listeningMode;
  final Duration? sleepTimerRemaining;
  final double playbackSpeed;
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
    Object? audioSurah = _unset,
    Object? audioWordIndex = _unset,
    Object? readerSelectedAyah = _unset,
    QuranListeningMode? listeningMode,
    Object? sleepTimerRemaining = _unset,
    double? playbackSpeed,
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
    audioSurah: identical(audioSurah, _unset)
        ? this.audioSurah
        : audioSurah as int?,
    audioWordIndex: identical(audioWordIndex, _unset)
        ? this.audioWordIndex
        : audioWordIndex as int?,
    readerSelectedAyah: identical(readerSelectedAyah, _unset)
        ? this.readerSelectedAyah
        : readerSelectedAyah as int?,
    listeningMode: listeningMode ?? this.listeningMode,
    sleepTimerRemaining: identical(sleepTimerRemaining, _unset)
        ? this.sleepTimerRemaining
        : sleepTimerRemaining as Duration?,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
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
    audioSurah,
    audioWordIndex,
    readerSelectedAyah,
    listeningMode,
    sleepTimerRemaining,
    playbackSpeed,
    activeStation,
    repeatConfig,
    repeatState,
    error,
  ];
}
