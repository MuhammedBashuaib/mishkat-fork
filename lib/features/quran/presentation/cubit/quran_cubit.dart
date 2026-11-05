import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/services/audio_repeat_controller.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/services/local_storage_service.dart';
import '../../data/models/quran_audio_station.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/quran_repository.dart';
import '../../domain/models/audio_repeat_config.dart';
import 'quran_state.dart';

enum QuranPlaybackOrigin { general, mushaf, audioPlayer }

class QuranCubit extends Cubit<QuranState> {
  QuranCubit({
    required this._repository,
    required this._storage,
    required this._audio,
    required this.reciter,
    required double fontSize,
    this.autoScroll = true,
  }) : super(QuranState(fontSize: fontSize)) {
    _playerSubscription = _audio.playerState.listen(_onPlayerState);
    _repeatController = AudioRepeatController(
      onPlayAyahRequested: (ayah) => _play(ayah, autoScroll: autoScroll),
      onSequenceCompleted: () {
        _playbackOrigin = null;
        emit(
          state.copyWith(
            audioStatus: QuranAudioStatus.idle,
            audioGlobalAyah: null,
            repeatState: const AudioRepeatState(
              status: AudioRepeatStatus.completed,
            ),
          ),
        );
      },
    );
    _repeatSubscription = _repeatController.stateStream.listen(_onRepeatState);
    _playbackErrorSubscription = _audio.playbackErrors.listen((_) {
      if (isClosed || _playbackOrigin == null) return;
      _repeatController.stop();
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          error: 'انقطع الصوت أو تعذّر تشغيله. تحقق من الاتصال واضغط تشغيل للمحاولة مجدداً.',
        ),
      );
    });
  }

  final QuranRepository _repository;
  final LocalStorageService _storage;
  final QuranAudioService _audio;
  late final StreamSubscription<PlayerState> _playerSubscription;
  late final AudioRepeatController _repeatController;
  late final StreamSubscription<AudioRepeatState> _repeatSubscription;
  late final StreamSubscription<Object> _playbackErrorSubscription;

  String reciter;
  bool _continuous = true;
  bool autoScroll;
  bool _advancingContinuously = false;
  QuranPlaybackOrigin? _playbackOrigin;
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepDeadline;
  int? _completedRequestId;
  bool _readerSelectionPending = false;
  int? _readerConsumedSelection;

  QuranRepository get repository => _repository;
  QuranAudioService get audioService => _audio;
  AudioRepeatController get repeatController => _repeatController;
  bool get isContinuous => _continuous;
  QuranPlaybackOrigin? get playbackOrigin => _playbackOrigin;
  bool get hasPendingReaderSelection => _readerSelectionPending;
  void setContinuous(bool value) {
    _continuous = value;
    _repeatController.setContinuous(value);
  }

  void setAutoScroll(bool value) => autoScroll = value;

  Future<void> load() async {
    emit(state.copyWith(status: QuranStatus.loading, clearError: true));
    try {
      final data = await _repository.load();
      final saved = _storage.readMap('quran');
      final currentPage = ((saved['currentPage'] as num?)?.toInt() ?? 1).clamp(
        1,
        604,
      );
      QuranPoint? lastRead;
      if (saved['lastRead'] is Map) {
        try {
          final parsed = QuranPoint.fromJson(
            Map<String, dynamic>.from(saved['lastRead'] as Map),
          );
          if (parsed.global >= 1 &&
              parsed.global <= 6236 &&
              parsed.surah >= 1 &&
              parsed.surah <= 114) {
            lastRead = parsed;
          }
        } catch (_) {
          // Ignore corrupted lastRead entry
        }
      }
      final bookmarks = <QuranBookmark>[];
      final seenGlobals = <int>{};
      if (saved['bookmarks'] is List) {
        for (final item in saved['bookmarks'] as List) {
          if (item is Map) {
            try {
              final b = QuranBookmark.fromJson(Map<String, dynamic>.from(item));
              if (b.point.global >= 1 &&
                  b.point.global <= 6236 &&
                  !seenGlobals.contains(b.point.global)) {
                seenGlobals.add(b.point.global);
                bookmarks.add(b);
              }
            } catch (_) {
              // Safely ignore corrupted bookmark entry
            }
          }
        }
      }

      // Load saved repeat configuration
      var repeatConfig = AudioRepeatConfig.defaultConfig;
      final savedRepeat = _storage.readMap('audio_repeat_config');
      if (savedRepeat.isNotEmpty) {
        try {
          repeatConfig = AudioRepeatConfig.fromJson(savedRepeat);
        } catch (_) {}
      }
      _repeatController.updateConfig(repeatConfig);

      final listening = _storage.readMap('quran_listening_settings');
      final savedMode = listening['mode'];
      final listeningMode = QuranListeningMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => QuranListeningMode.once,
      );
      final speed = listening['speed'];
      final playbackSpeed = speed is num && speed.isFinite
          ? speed.toDouble().clamp(0.5, 2.0)
          : 1.0;

      emit(
        state.copyWith(
          status: QuranStatus.ready,
          data: data,
          currentPage: currentPage,
          lastRead: lastRead,
          bookmarks: bookmarks,
          repeatConfig: repeatConfig,
          listeningMode: listeningMode,
          playbackSpeed: playbackSpeed,
        ),
      );
    } on Object catch (error) {
      emit(
        state.copyWith(
          status: QuranStatus.failure,
          error: 'تعذّر تحميل بيانات القرآن: $error',
        ),
      );
    }
  }

  void setMode(QuranIndexMode mode) => emit(state.copyWith(mode: mode));

  void search(String value) {
    final data = state.data;
    if (data == null) return;
    emit(
      state.copyWith(query: value, results: _repository.search(data, value)),
    );
  }

  void clearSearch() => emit(state.copyWith(query: '', results: []));

  Future<void> openPage(int page, {QuranPoint? point}) async {
    final safePage = page.clamp(1, 604);
    final data = state.data;
    final lastRead =
        point ??
        (data != null
            ? data.pointForGlobal(data.page(safePage).first.global)
            : state.lastRead);
    emit(
      state.copyWith(
        currentPage: safePage,
        lastRead: lastRead,
        readerSelectedAyah: safePage == state.currentPage
            ? state.readerSelectedAyah
            : null,
      ),
    );
    await _persist();
  }

  Future<void> openSurah(int surah, {int ayah = 1}) async {
    final data = state.data;
    if (data == null) return;
    final global = data.globalFor(surah, ayah);
    await openPage(
      data.pageForGlobal(global),
      point: QuranPoint(surah: surah, ayah: ayah, global: global),
    );
  }

  Future<void> openJuz(int juzNumber) async {
    final data = state.data;
    if (data == null || data.juz.isEmpty) return;
    final safeJuz = juzNumber.clamp(1, data.juz.length);
    final juz = data.juz[safeJuz - 1];
    final global = data.globalFor(juz.surah, juz.ayah);
    final page = data.pageForGlobal(global);
    emit(
      state.copyWith(
        currentPage: page,
        lastRead: QuranPoint(surah: juz.surah, ayah: juz.ayah, global: global),
      ),
    );
    await _persist();
  }

  Future<void> toggleBookmark([QuranPoint? point, String? note]) async {
    final data = state.data;
    final targetPoint =
        point ?? state.lastRead ?? data?.page(state.currentPage).first;
    if (targetPoint == null) return;
    await toggleAyahBookmark(targetPoint.global, label: note);
  }

  Future<void> toggleAyahBookmark(int globalAyah, {String? label}) async {
    final data = state.data;
    if (data == null) return;
    final list = List<QuranBookmark>.from(state.bookmarks);
    final existingIndex = list.indexWhere(
      (item) => item.point.global == globalAyah,
    );
    if (existingIndex >= 0) {
      list.removeAt(existingIndex);
    } else {
      final safe = globalAyah.clamp(1, 6236);
      final point = data.pointForGlobal(safe);
      final page = data.pageForGlobal(safe);
      list.insert(
        0,
        QuranBookmark(
          point: point,
          createdAt: DateTime.now(),
          label: label,
          page: page,
        ),
      );
    }
    emit(state.copyWith(bookmarks: list));
    await _persist();
  }

  Future<void> clearAllBookmarks() async {
    emit(state.copyWith(bookmarks: const []));
    await _persist();
  }

  Future<void> removeBookmark(int globalAyah) async {
    final list = List<QuranBookmark>.from(state.bookmarks)
      ..removeWhere((item) => item.point.global == globalAyah);
    emit(state.copyWith(bookmarks: list));
    await _persist();
  }

  Future<void> updateBookmarkNote(int globalAyah, String note) async {
    final list = state.bookmarks.map((b) {
      if (b.point.global == globalAyah) {
        return QuranBookmark(
          page: b.page,
          point: b.point,
          createdAt: b.createdAt,
          label: note.trim().isEmpty ? null : note.trim(),
        );
      }
      return b;
    }).toList();
    emit(state.copyWith(bookmarks: list));
    await _persist();
  }

  Future<void> setLastRead(int globalAyah) async {
    final data = state.data;
    if (data == null) return;
    final safeGlobal = globalAyah.clamp(1, 6236);
    final point = data.pointForGlobal(safeGlobal);
    final page = data.pageForGlobal(safeGlobal);
    emit(state.copyWith(currentPage: page, lastRead: point));
    await _persist();
  }

  void setFontSize(double value) =>
      emit(state.copyWith(fontSize: value.clamp(20, 60)));

  void selectReaderAyah(int? global) {
    if (isClosed) return;
    _readerSelectionPending = global != null;
    emit(state.copyWith(readerSelectedAyah: global?.clamp(1, 6236)));
  }

  /// A reader selection is a starting point, never an implicit play command.
  Future<void> toggleReaderAudio({
    int? selectedGlobalAyah,
    bool autoScroll = true,
  }) async {
    final data = state.data;
    if (data == null) return;
    final page = data.page(state.currentPage);
    final selected = selectedGlobalAyah ?? state.readerSelectedAyah;
    final onPage =
        selected != null &&
        selected >= page.first.global &&
        selected <= page.last.global;
    final target = onPage ? selected : page.first.global;
    final ownsPlayback = _playbackOrigin == QuranPlaybackOrigin.mushaf;
    final hasNewSelection =
        onPage &&
        (_readerSelectionPending || selected != _readerConsumedSelection);
    if (ownsPlayback &&
        !hasNewSelection &&
        state.audioWordIndex == null &&
        (state.audioStatus == QuranAudioStatus.playing ||
            state.audioStatus == QuranAudioStatus.paused ||
            state.audioStatus == QuranAudioStatus.loading)) {
      await _toggleCurrentAudio(continuous: true, autoScroll: autoScroll);
      return;
    }
    _readerSelectionPending = false;
    _readerConsumedSelection = onPage ? selected : null;
    await playAyah(
      target,
      continuous: true,
      autoScroll: autoScroll,
      origin: QuranPlaybackOrigin.mushaf,
    );
  }

  Future<void> playSurah(int surah) async {
    final data = state.data;
    if (data == null || isClosed) return;
    final safe = surah.clamp(1, 114);
    final requestId = ++_playbackRequestId;
    _repeatController.stop();
    _playbackOrigin = QuranPlaybackOrigin.audioPlayer;
    _continuous = false;
    emit(
      state.copyWith(
        audioStatus: QuranAudioStatus.loading,
        audioSurah: safe,
        audioGlobalAyah: null,
        audioWordIndex: null,
        activeStation: null,
        repeatState: const AudioRepeatState(),
        clearError: true,
      ),
    );
    try {
      await _audio.playSurah(
        reciter: reciter,
        surah: safe,
        title: 'سورة ${data.chapter(safe).name}',
      );
      if (requestId != _playbackRequestId || isClosed) return;
      await _audio.setPlaybackSpeed(state.playbackSpeed);
    } on Object catch (error) {
      if (requestId != _playbackRequestId || isClosed) return;
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          error: error is QuranAudioOfflineException
              ? error.message
              : 'تعذّر تشغيل السورة. تحقق من اتصال الإنترنت وحاول مجدداً.',
        ),
      );
    }
  }

  Future<void> playWord({required int globalAyah, required int word}) async {
    final data = state.data;
    if (data == null || word < 1 || isClosed) return;
    final point = data.pointForGlobal(globalAyah);
    final requestId = ++_playbackRequestId;
    _cancelSleepTimer();
    _repeatController.stop();
    _continuous = false;
    _playbackOrigin = QuranPlaybackOrigin.mushaf;
    emit(
      state.copyWith(
        audioStatus: QuranAudioStatus.loading,
        audioGlobalAyah: point.global,
        audioWordIndex: word,
        audioSurah: null,
        activeStation: null,
        sleepTimerRemaining: null,
        repeatState: const AudioRepeatState(),
        clearError: true,
      ),
    );
    try {
      await _audio.playWord(surah: point.surah, ayah: point.ayah, word: word);
    } on Object catch (error) {
      if (requestId != _playbackRequestId || isClosed) return;
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          error: error is QuranAudioOfflineException
              ? error.message
              : 'تعذّر تشغيل هذه الكلمة. تحقق من الاتصال وحاول مجدداً.',
        ),
      );
    }
  }

  Future<void> toggleWordAudio() async {
    final global = state.audioGlobalAyah;
    final word = state.audioWordIndex;
    if (global == null || word == null) return;
    if (state.audioStatus == QuranAudioStatus.failure) {
      await playWord(globalAyah: global, word: word);
    } else if (_audio.isPlaying) {
      emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
      await _audio.pause();
    } else if (state.audioStatus == QuranAudioStatus.paused) {
      await _audio.resume();
    }
  }

  Future<void> setListeningMode(QuranListeningMode mode) async {
    emit(state.copyWith(listeningMode: mode));
    await _persistListeningSettings();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!speed.isFinite || state.activeStation != null) return;
    final safe = speed.clamp(0.5, 2.0);
    try {
      if (state.audioSurah != null) await _audio.setPlaybackSpeed(safe);
      if (isClosed) return;
      emit(state.copyWith(playbackSpeed: safe));
      await _persistListeningSettings();
    } on Object {
      if (!isClosed) emit(state.copyWith(error: 'تعذّر تغيير سرعة التشغيل.'));
    }
  }

  Future<void> _persistListeningSettings() => _storage.writeMap(
    'quran_listening_settings',
    {'mode': state.listeningMode.name, 'speed': state.playbackSpeed},
  );

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepTimer = null;
    _sleepTicker = null;
    _sleepDeadline = null;
  }

  /// Owned by the application Cubit, so navigation cannot reset the deadline.
  void setSleepTimer(Duration? duration) {
    _cancelSleepTimer();
    if (duration == null || duration <= Duration.zero) {
      emit(state.copyWith(sleepTimerRemaining: null));
      return;
    }
    final safe = Duration(seconds: duration.inSeconds.clamp(1, 86400));
    _sleepDeadline = DateTime.now().add(safe);
    emit(state.copyWith(sleepTimerRemaining: safe));
    _sleepTimer = Timer(safe, () => unawaited(stopAudio()));
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed || _sleepDeadline == null) return;
      final remaining = _sleepDeadline!.difference(DateTime.now());
      emit(
        state.copyWith(
          sleepTimerRemaining: remaining.isNegative ? Duration.zero : remaining,
        ),
      );
    });
  }

  Future<void> playCurrent({
    required bool continuous,
    bool? autoScroll,
    QuranPlaybackOrigin origin = QuranPlaybackOrigin.general,
  }) async {
    final data = state.data;
    if (data == null) return;
    _continuous = continuous;
    _repeatController.setContinuous(continuous);
    if (autoScroll != null) this.autoScroll = autoScroll;
    final global = origin == QuranPlaybackOrigin.mushaf
        ? state.readerSelectedAyah ?? data.page(state.currentPage).first.global
        : state.audioGlobalAyah ?? data.page(state.currentPage).first.global;
    _repeatController.stop();
    await _play(global, autoScroll: autoScroll, origin: origin);
  }

  Future<void> playAyah(
    int global, {
    bool continuous = true,
    bool? autoScroll,
    QuranPlaybackOrigin origin = QuranPlaybackOrigin.general,
  }) async {
    _continuous = continuous;
    _repeatController.setContinuous(continuous);
    _repeatController.stop();
    if (autoScroll != null) this.autoScroll = autoScroll;
    await _play(global, autoScroll: autoScroll, origin: origin);
  }

  int _playbackRequestId = 0;

  Future<void> _play(
    int global, {
    bool? autoScroll,
    QuranPlaybackOrigin? origin,
  }) async {
    final data = state.data;
    if (data == null) return;
    if (origin != null) _playbackOrigin = origin;
    _cancelSleepTimer();
    final requestId = ++_playbackRequestId;
    final safe = global.clamp(1, 6236);
    final shouldScroll = autoScroll ?? this.autoScroll;
    final page = data.pageForGlobal(safe);
    if (shouldScroll && page != state.currentPage) {
      await openPage(page, point: data.pointForGlobal(safe));
    }
    if (requestId != _playbackRequestId) {
      return;
    }
    emit(
      state.copyWith(
        audioStatus: QuranAudioStatus.loading,
        audioGlobalAyah: safe,
        audioSurah: null,
        audioWordIndex: null,
        activeStation: null,
        sleepTimerRemaining: null,
        clearError: true,
      ),
    );
    try {
      await _audio.playAyah(reciter: reciter, globalAyah: safe);
    } on QuranAudioOfflineException catch (e) {
      if (requestId != _playbackRequestId) return;
      emit(
        state.copyWith(audioStatus: QuranAudioStatus.failure, error: e.message),
      );
    } on Object {
      if (requestId != _playbackRequestId) return;
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          error: 'تعذّر تشغيل التلاوة. تحقق من اتصال الإنترنت.',
        ),
      );
    }
  }

  /// Plays a verified live stream or radio station through the single audio authority.
  ///
  /// Automatically stops any ongoing recitation or prior stream to avoid simultaneous playback.
  Future<void> playStation(QuranAudioStation station) async {
    final requestId = ++_playbackRequestId;
    _repeatController.stop();
    _playbackOrigin = QuranPlaybackOrigin.audioPlayer;

    if (!station.isAudioPlayable || station.streamUrl == null) {
      await _audio.stop();
      if (requestId != _playbackRequestId || isClosed) return;
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          activeStation: station,
          audioGlobalAyah: null,
          audioSurah: null,
          audioWordIndex: null,
          error:
              station.notes ??
              'رابط البث غير معتمد حالياً. في انتظار اعتماد رابط رسمي موثق.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        audioStatus: QuranAudioStatus.loading,
        activeStation: station,
        audioGlobalAyah: null,
        audioSurah: null,
        audioWordIndex: null,
        repeatState: const AudioRepeatState(),
        clearError: true,
      ),
    );

    try {
      await _audio.playStreamUrl(
        station.streamUrl!,
        title: station.title,
        sourceLabel: station.sourceLabel,
      );
    } on TimeoutException {
      if (requestId != _playbackRequestId || isClosed) return;
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          error: 'استغرق الاتصال بالإذاعة وقتاً طويلاً. اضغط تشغيل للمحاولة مجدداً.',
        ),
      );
    } on QuranAudioOfflineException catch (e) {
      if (requestId != _playbackRequestId) return;
      emit(
        state.copyWith(audioStatus: QuranAudioStatus.failure, error: e.message),
      );
    } on Object {
      if (requestId != _playbackRequestId) return;
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.failure,
          error: 'تعذّر الاتصال بالبث المباشر. تحقق من اتصال الإنترنت.',
        ),
      );
    }
  }

  Future<void> toggleAudio({
    required bool continuous,
    bool? autoScroll,
    QuranPlaybackOrigin origin = QuranPlaybackOrigin.general,
  }) async {
    if (origin == QuranPlaybackOrigin.mushaf) {
      await toggleReaderAudio(autoScroll: autoScroll ?? this.autoScroll);
      return;
    }
    await _toggleCurrentAudio(
      continuous: continuous,
      autoScroll: autoScroll,
      origin: origin,
    );
  }

  Future<void> _toggleCurrentAudio({
    required bool continuous,
    bool? autoScroll,
    QuranPlaybackOrigin origin = QuranPlaybackOrigin.general,
  }) async {
    _continuous = continuous;
    _repeatController.setContinuous(continuous);
    if (autoScroll != null) this.autoScroll = autoScroll;

    final surah = state.audioSurah;
    if (surah != null) {
      if (state.audioStatus == QuranAudioStatus.failure ||
          state.audioStatus == QuranAudioStatus.idle) {
        await playSurah(surah);
      } else if (_audio.isPlaying) {
        emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
        await _audio.pause();
      } else if (state.audioStatus == QuranAudioStatus.paused) {
        await _audio.resume();
      }
      return;
    }

    final station = state.activeStation;
    if (station != null) {
      if (state.audioStatus == QuranAudioStatus.failure) {
        await playStation(station);
      } else if (_audio.isPlaying) {
        emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
        await _audio.pause();
      } else if (state.audioStatus == QuranAudioStatus.paused) {
        await _audio.resume();
      }
      return;
    }

    if (state.repeatState.isDelaying) {
      _repeatController.pause();
      emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
    } else if (state.repeatState.isPaused &&
        state.repeatState.remainingDelaySeconds > 0) {
      _repeatController.resume();
      emit(state.copyWith(audioStatus: QuranAudioStatus.playing));
    } else if (_audio.isPlaying) {
      _repeatController.pause();
      emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
      await _audio.pause();
    } else if (state.audioStatus == QuranAudioStatus.paused) {
      _repeatController.resume();
      await _audio.resume();
    } else {
      await playCurrent(
        continuous: continuous,
        autoScroll: autoScroll,
        origin: origin,
      );
    }
  }

  Future<void> stopAudio() async {
    if (isClosed) return;
    ++_playbackRequestId;
    _cancelSleepTimer();
    _repeatController.stop();
    _playbackOrigin = null;
    emit(
      state.copyWith(
        audioStatus: QuranAudioStatus.idle,
        audioGlobalAyah: null,
        audioSurah: null,
        audioWordIndex: null,
        sleepTimerRemaining: null,
        activeStation: null,
        repeatState: const AudioRepeatState(),
        clearError: true,
      ),
    );
    await _audio.stop();
  }

  Future<void> stopAudioIfOwnedBy(QuranPlaybackOrigin origin) async {
    if (_playbackOrigin == origin) await stopAudio();
  }

  Future<void> nextAudioAyah({bool? autoScroll}) async {
    final surah = state.audioSurah;
    if (surah != null) {
      if (surah < 114) await playSurah(surah + 1);
      return;
    }
    if (state.repeatState.isActive) {
      _repeatController.next();
      return;
    }
    final current =
        state.audioGlobalAyah ??
        state.data?.page(state.currentPage).first.global ??
        1;
    if (current < 6236) {
      await _play(current + 1, autoScroll: autoScroll);
    } else {
      await stopAudio();
    }
  }

  Future<void> previousAudioAyah({bool? autoScroll}) async {
    final surah = state.audioSurah;
    if (surah != null) {
      if (surah > 1) await playSurah(surah - 1);
      return;
    }
    if (state.repeatState.isActive) {
      _repeatController.previous();
      return;
    }
    final current =
        state.audioGlobalAyah ??
        state.data?.page(state.currentPage).first.global ??
        1;
    if (current > 1) {
      await _play(current - 1, autoScroll: autoScroll);
    }
  }

  Future<void> seekAudio(Duration position) => _audio.seek(position);

  void skipDelay() => _repeatController.skipDelay();

  Future<void> setRepeatConfig(AudioRepeatConfig config) async {
    _repeatController.updateConfig(config);
    emit(state.copyWith(repeatConfig: config));
    await _storage.writeMap('audio_repeat_config', config.toJson());
  }

  Future<void> startRepeatPlayback(
    AudioRepeatConfig config, {
    int? initialGlobalAyah,
    List<int>? customQueue,
    bool? autoScroll,
    QuranPlaybackOrigin origin = QuranPlaybackOrigin.general,
  }) async {
    final requestId = ++_playbackRequestId;
    if (autoScroll != null) this.autoScroll = autoScroll;
    _playbackOrigin = origin;
    emit(state.copyWith(repeatConfig: config));
    await _storage.writeMap('audio_repeat_config', config.toJson());
    if (requestId != _playbackRequestId || isClosed) return;
    await _repeatController.start(
      config: config,
      initialGlobalAyah: initialGlobalAyah ?? state.audioGlobalAyah,
      customQueue: customQueue,
      continuous: _continuous,
    );
  }

  Future<void> playDailyJourney(
    List<int> queue, {
    AudioRepeatConfig? repeatConfig,
    bool? autoScroll,
  }) async {
    if (queue.isEmpty) return;
    final config =
        repeatConfig ??
        AudioRepeatConfig(
          mode: AudioRepeatMode.rangeLoop,
          startGlobalAyah: queue.first,
          endGlobalAyah: queue.last,
          rangeRepeatCount: 1,
          delaySeconds: 1,
        );
    await startRepeatPlayback(
      config,
      initialGlobalAyah: queue.first,
      customQueue: queue,
      autoScroll: autoScroll,
    );
  }

  void updateReciter(String value, {bool restartIfPlaying = true}) {
    if (reciter == value) return;
    reciter = value;
    if (restartIfPlaying &&
        state.audioSurah != null &&
        (state.audioStatus == QuranAudioStatus.playing ||
            state.audioStatus == QuranAudioStatus.loading)) {
      unawaited(playSurah(state.audioSurah!));
      return;
    }
    if (restartIfPlaying &&
        (state.audioStatus == QuranAudioStatus.playing ||
            state.audioStatus == QuranAudioStatus.loading) &&
        state.audioGlobalAyah != null &&
        state.audioWordIndex == null) {
      unawaited(_play(state.audioGlobalAyah!, autoScroll: false));
    }
  }

  void _onPlayerState(PlayerState player) {
    if (isClosed) return;
    // Ignore late native events after an explicit stop or failed preparation.
    if (_playbackOrigin == null &&
        state.audioGlobalAyah == null &&
        state.audioSurah == null &&
        state.activeStation == null) {
      return;
    }
    if (state.audioStatus == QuranAudioStatus.failure) return;
    if (state.audioSurah != null) {
      if (player.processingState == ProcessingState.completed) {
        if (state.audioStatus == QuranAudioStatus.loading ||
            _completedRequestId == _playbackRequestId) {
          return;
        }
        _completedRequestId = _playbackRequestId;
        final surah = state.audioSurah!;
        switch (state.listeningMode) {
          case QuranListeningMode.repeat:
            unawaited(playSurah(surah));
          case QuranListeningMode.next when surah < 114:
            unawaited(playSurah(surah + 1));
          case QuranListeningMode.once:
          case QuranListeningMode.next:
            unawaited(stopAudio());
        }
        return;
      }
      if (player.processingState == ProcessingState.loading ||
          player.processingState == ProcessingState.buffering) {
        if (state.audioStatus != QuranAudioStatus.paused) {
          emit(state.copyWith(audioStatus: QuranAudioStatus.loading));
        }
        return;
      }
      if (player.processingState == ProcessingState.ready) {
        if (player.playing) {
          emit(state.copyWith(audioStatus: QuranAudioStatus.playing));
        } else if (state.audioStatus != QuranAudioStatus.loading) {
          emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
        }
        return;
      }
    }
    if (state.activeStation != null) {
      // A failed load can report idle after its error has already reached the
      // UI. Retain the station so the play button can retry it.
      if (state.audioStatus == QuranAudioStatus.failure) return;
      if (player.processingState == ProcessingState.loading ||
          player.processingState == ProcessingState.buffering) {
        if (player.playing || state.audioStatus != QuranAudioStatus.paused) {
          emit(state.copyWith(audioStatus: QuranAudioStatus.loading));
        }
        return;
      }
      if (player.processingState == ProcessingState.ready) {
        if (player.playing) {
          emit(state.copyWith(audioStatus: QuranAudioStatus.playing));
        } else if (state.audioStatus != QuranAudioStatus.loading) {
          emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
        }
        return;
      }
    }
    if (player.processingState == ProcessingState.idle) {
      if (state.repeatState.isDelaying ||
          _advancingContinuously ||
          state.audioStatus == QuranAudioStatus.loading) {
        // just_audio briefly reports idle while replacing the completed Ayah
        // source. Keep the active Ayah intact until the next source is ready.
        return;
      }
      _playbackOrigin = null;
      _cancelSleepTimer();
      emit(
        state.copyWith(
          audioStatus: QuranAudioStatus.idle,
          audioGlobalAyah: null,
          audioSurah: null,
          audioWordIndex: null,
          sleepTimerRemaining: null,
          activeStation: null,
        ),
      );
    } else if (player.processingState == ProcessingState.completed) {
      if (state.audioStatus == QuranAudioStatus.loading ||
          _completedRequestId == _playbackRequestId) {
        return;
      }
      _completedRequestId = _playbackRequestId;
      if (state.activeStation != null) {
        unawaited(stopAudio());
        return;
      }
      if (state.repeatState.isActive) {
        _repeatController.onAyahPlaybackFinished();
      } else if (_continuous && (state.audioGlobalAyah ?? 6236) < 6236) {
        if (_advancingContinuously) return;
        _advancingContinuously = true;
        unawaited(
          nextAudioAyah(autoScroll: autoScroll).whenComplete(() {
            _advancingContinuously = false;
          }),
        );
      } else {
        unawaited(stopAudio());
      }
    } else if (player.processingState == ProcessingState.loading ||
        player.processingState == ProcessingState.buffering) {
      if (state.audioStatus != QuranAudioStatus.paused) {
        emit(state.copyWith(audioStatus: QuranAudioStatus.loading));
      }
    } else if (player.processingState == ProcessingState.ready) {
      if (player.playing) {
        emit(state.copyWith(audioStatus: QuranAudioStatus.playing));
      } else if (state.audioStatus != QuranAudioStatus.loading &&
          !state.repeatState.isDelaying) {
        emit(state.copyWith(audioStatus: QuranAudioStatus.paused));
      }
    }
  }

  void _onRepeatState(AudioRepeatState repeatState) {
    if (isClosed) return;
    if (repeatState.isDelaying) {
      emit(
        state.copyWith(
          repeatState: repeatState,
          audioStatus: QuranAudioStatus.playing,
          audioGlobalAyah: repeatState.currentAyah,
        ),
      );
    } else if (repeatState.isCompleted) {
      emit(
        state.copyWith(
          repeatState: repeatState,
          audioStatus: QuranAudioStatus.idle,
          audioGlobalAyah: null,
        ),
      );
    } else {
      emit(state.copyWith(repeatState: repeatState));
    }
  }

  Future<void> _persist() => _storage.writeMap('quran', {
    'currentPage': state.currentPage,
    'lastRead': state.lastRead?.toJson(),
    'bookmarks': state.bookmarks.map((item) => item.toJson()).toList(),
  });

  @override
  Future<void> close() async {
    _playbackRequestId++;
    _cancelSleepTimer();
    await _playerSubscription.cancel();
    await _repeatSubscription.cancel();
    await _playbackErrorSubscription.cancel();
    _repeatController.dispose();
    await _audio.dispose();
    return super.close();
  }
}
