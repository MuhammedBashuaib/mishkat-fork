import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/audio_service.dart';
import '../../data/models/oral_recitation_models.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/models/recitation_feedback_event.dart';
import '../../data/repositories/quran_repository.dart';
import '../services/quran_alignment_engine.dart';
import '../services/quran_recitation_text.dart';
import '../services/speech_recognition_service.dart';
import '../services/offline_speech_recognition_service.dart';
import 'quran_memorization_cubit.dart';
import 'quran_oral_recitation_state.dart';

/// Cubit responsible for orchestrating real microphone oral recitation,
/// streaming speech recognition, real-time Quran alignment, and mistake detection.
class QuranOralRecitationCubit extends Cubit<QuranOralRecitationState> {
  QuranOralRecitationCubit({
    required this.speechService,
    QuranAlignmentEngine? alignmentEngine,
    required this.quranRepository,
    required this.memorizationCubit,
    this.audioService,
    this.ownsSpeechService = false,
  }) : alignmentEngine = alignmentEngine ?? const QuranAlignmentEngine(),
       super(
         QuranOralRecitationState(
           isOfflineEngine:
               speechService is OfflineSpeechDiagnostics &&
               (speechService as OfflineSpeechDiagnostics).isOffline,
         ),
       );

  final SpeechRecognitionService speechService;
  final QuranAlignmentEngine alignmentEngine;
  final QuranRepository quranRepository;
  final QuranMemorizationCubit memorizationCubit;
  final QuranAudioService? audioService;
  final bool ownsSpeechService;

  final _feedback = StreamController<RecitationFeedbackEvent>.broadcast(
    sync: true,
  );
  Stream<RecitationFeedbackEvent> get feedbackStream => _feedback.stream;

  StreamSubscription<SpeechRecognitionResultData>? _resultSubscription;
  StreamSubscription<SpeechRecognitionFailure>? _errorSubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<double>? _levelSubscription;
  StreamSubscription<bool>? _processingSubscription;
  Timer? _durationTimer;
  Timer? _recognitionRestartTimer;
  QuranData? _quranData;
  bool _isProcessingPermission = false;
  bool _isRestartingRecognition = false;
  bool _isStartingRecognition = false;
  bool _isRefreshingPermission = false;
  bool _isClosing = false;
  int _captureOperation = 0;
  int _busyRestartAttempts = 0;
  int _networkRestartAttempts = 0;
  bool _recoveryPending = false;
  Future<void>? _captureRelease;
  Future<void>? _drainOperation;
  Future<void>? _finishOperation;
  bool _acceptDrainingResults = false;
  Set<int>? _selectedGlobalAyahs;
  bool get _isOffline =>
      speechService is OfflineSpeechDiagnostics &&
      (speechService as OfflineSpeechDiagnostics).isOffline;

  String get _engineUnavailableMessage => _isOffline
      ? (kIsWeb || defaultTargetPlatform != TargetPlatform.android
            ? 'التسميع بالنموذج المضمّن متاح على Android في هذه النسخة.'
            : 'تعذّر تجهيز نموذج التسميع المضمّن. أعد فتح الجلسة، وتأكد من تثبيت نسخة Android الكاملة من مشكاة.')
      : 'خدمة التعرف الصوتي غير جاهزة على هذا الجهاز. فعّل خدمة التعرف على الكلام أو نزّل حزمة اللغة العربية ثم أعد المحاولة.';

  Future<void> _releaseCapture({bool stop = false}) {
    final previous = _captureRelease;
    final release = () async {
      await previous;
      try {
        if (stop) {
          await speechService.stopListening();
        } else {
          await speechService.cancelListening();
        }
      } catch (_) {}
    }();
    _captureRelease = release;
    return release;
  }

  bool _isCurrentOperation(int operation) =>
      !isClosed && !_isClosing && operation == _captureOperation;

  void _emitFeedback(RecitationCue cue, {Set<int> wordIndices = const {}}) {
    final sessionId = state.sessionId;
    if (isClosed || _isClosing || sessionId == null || _feedback.isClosed) {
      return;
    }
    _feedback.add(
      RecitationFeedbackEvent(
        cue,
        sessionId: sessionId,
        wordIndices: Set<int>.unmodifiable(wordIndices),
      ),
    );
  }

  int _committedTargetIndex = 0;
  List<RecitationWordAlignment> _committedAlignedWords = const [];
  List<RecitationDiscrepancy> _committedDiscrepancies = const [];
  String _lastProcessedTranscript = '';
  Set<int> _previousPreviewAyahs = const {};
  Set<int> _exposedPreviewAyahs = const {};
  Set<int> _previousPreviewWords = const {};
  Set<int> _exposedPreviewWords = const {};

  /// Prepares an oral recitation session for a target Surah or Ayah range.
  Future<void> prepareSession({
    required int surahNumber,
    int? startGlobalAyah,
    int? endGlobalAyah,
    String? planId,
    Set<int>? selectedGlobalAyahs,
  }) async {
    if (isClosed || _isClosing) return;
    final operation = ++_captureOperation;
    _busyRestartAttempts = 0;
    _networkRestartAttempts = 0;
    _recoveryPending = false;
    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    _cancelSubscriptions();
    try {
      await _releaseCapture();
    } catch (_) {}
    if (!_isCurrentOperation(operation)) return;
    _committedTargetIndex = 0;
    _committedAlignedWords = const [];
    _committedDiscrepancies = const [];
    _previousPreviewAyahs = const {};
    _exposedPreviewAyahs = const {};
    _previousPreviewWords = const {};
    _exposedPreviewWords = const {};
    _lastProcessedTranscript = '';
    _acceptDrainingResults = false;
    _selectedGlobalAyahs = selectedGlobalAyahs == null
        ? null
        : Set.unmodifiable(selectedGlobalAyahs);

    emit(
      QuranOralRecitationState(
        mode: state.mode,
        isOfflineEngine: _isOffline,
        lifecycle: OralRecitationLifecycle.initializingSpeechEngine,
      ),
    );

    try {
      _quranData ??= await quranRepository.load();
      if (!_isCurrentOperation(operation)) return;
      final chapters = _quranData!.chapters;

      final chapter = chapters.firstWhere(
        (c) => c.number == surahNumber,
        orElse: () => chapters.first,
      );

      final chapterEnd = chapter.globalStart + chapter.ayahs.length - 1;
      final rawStart = (startGlobalAyah ?? chapter.globalStart).clamp(
        chapter.globalStart,
        chapterEnd,
      );
      final rawEnd =
          (endGlobalAyah ?? (chapter.globalStart + chapter.ayahs.length - 1))
              .clamp(chapter.globalStart, chapterEnd);
      final resolvedStart = min(rawStart, rawEnd);
      final resolvedEnd = max(rawStart, rawEnd);

      final preparedWords = alignmentEngine.prepareTargetTokens(
        chapters: chapters,
        startGlobalAyah: resolvedStart,
        endGlobalAyah: resolvedEnd,
      );
      final targetWords = <AuthoritativeWord>[];
      for (final word in preparedWords) {
        if (selectedGlobalAyahs != null &&
            !selectedGlobalAyahs.contains(word.globalAyah)) {
          continue;
        }
        targetWords.add(
          AuthoritativeWord(
            globalAyah: word.globalAyah,
            surah: word.surah,
            ayahInSurah: word.ayahInSurah,
            wordIndex: targetWords.length,
            uthmaniText: word.uthmaniText,
            normalizedText: word.normalizedText,
          ),
        );
      }
      if (targetWords.isEmpty) {
        throw StateError('لا توجد آيات في المقطع المختار');
      }

      final initialAligned = targetWords
          .map(
            (w) => RecitationWordAlignment(
              authoritativeWord: w,
              status: WordAlignmentStatus.upcoming,
            ),
          )
          .toList(growable: false);

      final sessionId =
          'oral_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

      final hasPerm = await speechService.hasPermission();
      if (!_isCurrentOperation(operation)) return;
      var lifecycle = OralRecitationLifecycle.permissionDenied;
      String? errorMessage;
      if (hasPerm || _isOffline) {
        final available = await speechService.initialize();
        if (!_isCurrentOperation(operation)) return;
        if (available) {
          lifecycle = hasPerm
              ? OralRecitationLifecycle.ready
              : OralRecitationLifecycle.permissionDenied;
        } else {
          lifecycle = OralRecitationLifecycle.recognizerUnavailable;
          errorMessage = _engineUnavailableMessage;
        }
      }

      emit(
        QuranOralRecitationState(
          mode: state.mode,
          isOfflineEngine: _isOffline,
          lifecycle: lifecycle,
          errorMessage: errorMessage,
          sessionId: sessionId,
          surahNumber: chapter.number,
          surahName: chapter.name,
          startGlobalAyah: resolvedStart,
          endGlobalAyah: resolvedEnd,
          planId: planId,
          targetWords: targetWords,
          alignedWords: initialAligned,
          discrepancies: const [],
          currentGlobalAyah: targetWords.first.globalAyah,
          currentWordIndex: 0,
          committedTargetIndex: 0,
          liveTranscript: '',
          progressPercentage: 0.0,
          matchedWordsCount: 0,
          omissionsCount: 0,
          substitutionsCount: 0,
          uncertainCount: 0,
          durationSeconds: 0,
          revealedGlobals: const {},
          completedGlobalAyahs: const {},
          summary: null,
        ),
      );
    } catch (e) {
      if (!_isCurrentOperation(operation)) return;
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.error,
          errorMessage: 'تعذّر إعداد جلسة التسميع: $e',
        ),
      );
    }
  }

  /// Requests native microphone permission and initializes the speech recognition engine.
  /// Prevents concurrent requests and transitions through explicit states.
  Future<void> requestPermissionAndInitialize() async {
    if (_isProcessingPermission || isClosed || _isClosing) return;
    if (_isOffline &&
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android)) {
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.recognizerUnavailable,
          errorMessage: _engineUnavailableMessage,
        ),
      );
      return;
    }
    final operation = _captureOperation;
    _isProcessingPermission = true;

    try {
      // 1. Immediately enter a visible requesting state
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.requestingPermission,
          clearError: true,
        ),
      );

      // 2. Check current microphone permission status
      var hasPerm = await speechService.hasPermission();
      if (!_isCurrentOperation(operation)) return;

      // 3. If not yet granted, invoke native permission request
      if (!hasPerm) {
        final permission = await speechService.requestPermission();
        if (!_isCurrentOperation(operation)) return;
        hasPerm = permission.isGranted;

        if (!hasPerm && permission.requiresSettings) {
          emit(
            state.copyWith(
              lifecycle: OralRecitationLifecycle.permissionPermanentlyDenied,
              errorMessage: 'إذن الميكروفون أو التعرف على الكلام مرفوض من إعدادات الجهاز. افتح إعدادات التطبيق وفعّل الإذن للمتابعة.',
            ),
          );
          return;
        }
      }

      if (!_isCurrentOperation(operation)) return;

      if (!hasPerm) {
        // Permission was denied
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.permissionDenied,
            errorMessage:
                'نحتاج إلى إذن الميكروفون حتى نتمكن من الاستماع إلى تلاوتك.',
          ),
        );
        return;
      }

      // 4. Permission granted -> transition to engine initialization
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.permissionGranted,
          clearError: true,
        ),
      );

      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.initializingSpeechEngine,
          clearError: true,
        ),
      );

      // 5. Initialize the speech recognition engine
      final isAvailable = await speechService.initialize();
      if (!_isCurrentOperation(operation)) return;

      if (!isAvailable) {
        final stillHasPerm = await speechService.hasPermission();
        if (!_isCurrentOperation(operation)) return;
        if (!stillHasPerm) {
          emit(
            state.copyWith(
              lifecycle: OralRecitationLifecycle.permissionDenied,
              errorMessage:
                  'نحتاج إلى إذن الميكروفون حتى نتمكن من الاستماع إلى تلاوتك.',
            ),
          );
        } else {
          emit(
            state.copyWith(
              lifecycle: OralRecitationLifecycle.recognizerUnavailable,
              errorMessage: _engineUnavailableMessage,
            ),
          );
        }
        return;
      }

      // 6. Transition to ready
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.ready,
          clearError: true,
        ),
      );
    } catch (e) {
      if (!_isCurrentOperation(operation)) return;
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.error,
          errorMessage: 'تعذر تهيئة التعرف الصوتي. حاول مرة أخرى.',
        ),
      );
    } finally {
      _isProcessingPermission = false;
    }
  }

  /// Opens application system settings so the user can grant permission manually.
  Future<void> openAppSettings() async {
    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.permissionPermanentlyDenied,
        errorMessage: 'إذن الميكروفون مرفوض من إعدادات الجهاز. افتح إعدادات التطبيق وفعّل الميكروفون، ثم ارجع وحاول مرة أخرى.',
      ),
    );
    await speechService.openAppSettings();
  }

  /// Opens Android voice-input settings (or app settings as a fallback) so
  /// Arabic recognition can be installed/enabled without leaving the flow.
  Future<void> openSpeechRecognitionSettings() async {
    if (isClosed) return;
    final opened = await speechService.openSpeechRecognitionSettings();
    if (!opened && !isClosed) {
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.languageUnavailable,
          errorMessage: 'تعذّر فتح إعدادات التعرف الصوتي تلقائيًا. افتح إعدادات الجهاز ثم: النظام ← اللغات والإدخال ← الإدخال الصوتي، وأضف العربية.',
        ),
      );
    }
  }

  /// Re-evaluates permission status and engine availability (e.g. after returning from Settings).
  Future<void> checkAndRefreshPermission() async {
    if (isClosed ||
        _isClosing ||
        _isRefreshingPermission ||
        _isProcessingPermission ||
        _isStartingRecognition ||
        state.isDraining ||
        state.lifecycle.isIdle ||
        state.lifecycle.isListening ||
        state.lifecycle.isCompleted) {
      return;
    }
    final operation = _captureOperation;
    final lifecycle = state.lifecycle;
    bool canRefresh() =>
        _isCurrentOperation(operation) &&
        state.lifecycle == lifecycle &&
        !_isStartingRecognition &&
        !_isProcessingPermission;
    _isRefreshingPermission = true;
    try {
      final hasPerm = await speechService.hasPermission();
      if (!canRefresh()) return;
      if (!hasPerm) {
        if (lifecycle.isPermissionPermanentlyDenied) return;
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.permissionDenied,
            errorMessage:
                'نحتاج إلى إذن الميكروفون حتى نتمكن من الاستماع إلى تلاوتك.',
          ),
        );
        return;
      }

      final isAvailable = await speechService.initialize();
      if (!canRefresh()) return;
      if (isAvailable) {
        if (lifecycle.isLanguageUnavailable) {
          final hasArabic = await speechService.hasArabicLocale();
          if (!canRefresh()) return;
          if (hasArabic == false) {
            emit(
              state.copyWith(
                lifecycle: OralRecitationLifecycle.languageUnavailable,
                errorMessage: 'العربية لم تظهر بعد ضمن لغات التعرف الصوتي. أضف العربية إلى خدمة التعرف على الكلام ثم أعد الفحص.',
              ),
            );
            return;
          }
        }
        emit(
          state.copyWith(
            lifecycle: lifecycle.isPaused
                ? OralRecitationLifecycle.paused
                : OralRecitationLifecycle.ready,
            clearError: true,
          ),
        );
      } else {
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.recognizerUnavailable,
            errorMessage: _engineUnavailableMessage,
          ),
        );
      }
    } catch (_) {
      if (canRefresh()) {
        emit(
          state.copyWith(
            errorMessage: 'تعذّر فحص الميكروفون. حاول بدء التسميع مرة أخرى.',
          ),
        );
      }
    } finally {
      _isRefreshingPermission = false;
    }
  }

  /// Begins capture once, including when resuming after a platform failure.
  Future<void> startRecitation({bool notifyFeedback = true}) async {
    if (isClosed ||
        _isClosing ||
        _isStartingRecognition ||
        _isRestartingRecognition ||
        _isProcessingPermission ||
        state.isDraining ||
        state.targetWords.isEmpty ||
        state.lifecycle.isListening ||
        state.lifecycle.isCompleted) {
      return;
    }
    _isStartingRecognition = true;
    final operation = ++_captureOperation;
    _busyRestartAttempts = 0;
    _networkRestartAttempts = 0;
    _recoveryPending = false;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    try {
      await _captureRelease;
      if (!_isCurrentOperation(operation)) return;
      // Release playback before acquiring the microphone.
      try {
        await audioService?.stop();
      } catch (_) {}
      if (!_isCurrentOperation(operation)) return;

      if (!state.lifecycle.isReady) {
        await requestPermissionAndInitialize();
        if (!_isCurrentOperation(operation) || !state.lifecycle.isReady) return;
      }

      _cancelSubscriptions();
      _resultSubscription = speechService.resultsStream.listen(_onSpeechResult);
      _errorSubscription = speechService.errorStream.listen(_onSpeechError);
      _statusSubscription = speechService.statusStream.listen(_onSpeechStatus);
      if (speechService is OfflineSpeechDiagnostics) {
        final diagnostics = speechService as OfflineSpeechDiagnostics;
        _levelSubscription = diagnostics.soundLevelStream.listen((level) {
          if (!isClosed && state.isListening && !state.isDraining) {
            emit(state.copyWith(audioLevel: level.clamp(0, 1)));
          }
        });
        _processingSubscription = diagnostics.processingStream.listen((busy) {
          if (!isClosed && !_isClosing) {
            emit(state.copyWith(isProcessingSpeech: busy));
          }
        });
      }
      // Accept synchronous native callbacks during startup.
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.listening,
          clearError: true,
        ),
      );
      final ok = await speechService.startListening(
        localeId: 'ar_SA',
        contextualPhrases: _isOffline ? const [] : _recognitionHints(),
      );
      if (!_isCurrentOperation(operation) || !state.lifecycle.isListening) {
        // A late native start must not turn the mic back on after pause/exit.
        try {
          await _releaseCapture();
        } catch (_) {}
        return;
      }
      if (!ok) {
        // Preserve the specific failure delivered by the adapter. Transient
        // failures may already have queued a safe restart.
        if (_recognitionRestartTimer != null) return;
        _cancelSubscriptions();
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.error,
            errorMessage: 'تعذر تشغيل الميكروفون وبدء الاستماع. حاول مرة أخرى.',
          ),
        );
        return;
      }
      _startDurationTimer();
      if (notifyFeedback) _emitFeedback(RecitationCue.ready);
    } catch (_) {
      if (_isCurrentOperation(operation) && state.lifecycle.isListening) {
        _onSpeechError(
          const SpeechRecognitionFailure(
            type: SpeechRecognitionFailureType.audio,
            message: 'تعذّر تشغيل الميكروفون. تأكد من إتاحته ثم اضغط متابعة.',
          ),
        );
      }
    } finally {
      _isStartingRecognition = false;
    }
  }

  /// Pauses capture, including an in-flight native startup.
  Future<void> pauseRecitation({bool notifyFeedback = true}) async {
    if (isClosed ||
        _isClosing ||
        state.lifecycle.isCompleted ||
        (!state.lifecycle.isListening && !_isStartingRecognition)) {
      return;
    }
    final sessionId = state.sessionId;
    final alreadyDraining = _drainOperation != null;
    await _drainCapture();
    if (notifyFeedback &&
        !alreadyDraining &&
        _finishOperation == null &&
        state.sessionId == sessionId &&
        state.isPaused &&
        !state.isDraining) {
      _emitFeedback(RecitationCue.paused);
    }
  }

  Future<void> resumeRecitation({bool notifyFeedback = true}) async {
    if (!state.lifecycle.isPaused) return;
    await _drainOperation;
    if (isClosed || _isClosing || !state.lifecycle.isPaused) return;
    await startRecitation(notifyFeedback: notifyFeedback);
  }

  /// Reveals the authoritative Uthmani text for a specific Ayah during the session.
  void revealAyah(int globalAyah) {
    if (isClosed ||
        state.isDraining ||
        !state.targetWords.any((w) => w.globalAyah == globalAyah)) {
      return;
    }
    final updated = Set<int>.from(state.revealedGlobals)..add(globalAyah);
    final hinted = {...state.hintedGlobalAyahs, globalAyah};
    emit(
      state.copyWith(
        revealedGlobals: updated,
        hintedGlobalAyahs: hinted,
        hintCount:
            state.hintCount +
            (state.hintedGlobalAyahs.contains(globalAyah) ? 0 : 1),
      ),
    );
  }

  /// Hides the authoritative text for an Ayah again.
  void hideAyah(int globalAyah) {
    if (isClosed) return;
    final updated = Set<int>.from(state.revealedGlobals)..remove(globalAyah);
    emit(state.copyWith(revealedGlobals: updated));
  }

  void setMode(OralRecitationMode mode) {
    if (isClosed || !state.canChangeMode) {
      return;
    }
    emit(state.copyWith(mode: mode));
  }

  void hintCurrentWord() {
    if (isClosed ||
        state.isDraining ||
        state.lifecycle.isCompleted ||
        state.targetWords.isEmpty) {
      return;
    }
    final index = _isOffline
        ? state.currentWordIndex
        : state.correctionWordIndex ?? state.currentWordIndex;
    if (index < 0 ||
        index >= state.targetWords.length ||
        state.hintedWordIndices.contains(index) ||
        (_isOffline && state.visibleWordIndices.contains(index))) {
      return;
    }
    emit(
      state.copyWith(
        hintedWordIndices: {...state.hintedWordIndices, index},
        hintedGlobalAyahs: {
          ...state.hintedGlobalAyahs,
          state.targetWords[index].globalAyah,
        },
        hintCount: state.hintCount + 1,
      ),
    );
  }

  /// A manual escape hatch for recognition errors. It is never counted as a
  /// correct word or independent memorization; the ayah stays due for review.
  Future<void> skipCurrentWord() async {
    if (isClosed || state.isDraining || state.lifecycle.isCompleted) return;
    final index = state.correctionWordIndex;
    if (index == null || index < 0 || index >= state.targetWords.length) return;
    final wasListening = state.isListening;
    if (wasListening) await pauseRecitation(notifyFeedback: false);
    if (isClosed || _isClosing || state.lifecycle.isCompleted) return;
    // A final decode may have corrected the word while the microphone drained.
    if (state.correctionWordIndex != index) {
      if (wasListening) await resumeRecitation(notifyFeedback: false);
      return;
    }
    final word = state.targetWords[index];
    final aligned = List<RecitationWordAlignment>.from(state.alignedWords);
    aligned[index] = aligned[index].copyWith(
      status: WordAlignmentStatus.uncertain,
    );
    final discrepancies =
        state.discrepancies.where((d) => d.wordIndex != index).toList()..add(
          RecitationDiscrepancy(
            id: 'assisted_${word.globalAyah}_$index',
            globalAyah: word.globalAyah,
            surah: word.surah,
            ayahInSurah: word.ayahInSurah,
            wordIndex: index,
            expectedUthmani: word.uthmaniText,
            expectedNormalized: word.normalizedText,
            status: WordAlignmentStatus.uncertain,
            explanation: 'تجاوزتها للمراجعة لاحقاً؛ لم تُحتسب كلمة متقنة.',
          ),
        );
    _committedTargetIndex = max(_committedTargetIndex, index + 1);
    _committedAlignedWords = List.unmodifiable(aligned);
    _committedDiscrepancies = List.unmodifiable(discrepancies);
    _lastProcessedTranscript = '';
    emit(
      state.copyWith(
        assistedWordIndices: {...state.assistedWordIndices, index},
        clearCorrection: true,
      ),
    );
    _restoreConfirmedAlignment();
    if (_committedTargetIndex >= state.targetWords.length &&
        state.unresolvedMistakeWordIndices.isEmpty) {
      await finishSession(notifyFeedback: false);
    } else if (wasListening) {
      await resumeRecitation(notifyFeedback: false);
    }
  }

  Future<void> retrySession({
    int? globalAyah,
    bool onlyWeakAyahs = false,
  }) async {
    if (isClosed ||
        _isClosing ||
        state.isDraining ||
        state.isCommittingToMemorization) {
      return;
    }
    final previous = state;
    Set<int>? selection = _selectedGlobalAyahs;
    if (globalAyah != null) {
      selection = {globalAyah};
    } else if (onlyWeakAyahs) {
      selection = {
        ...previous.hintedGlobalAyahs,
        for (final word in previous.alignedWords)
          if (!word.status.isMatched ||
              previous.mistakeWordIndices.contains(
                word.authoritativeWord.wordIndex,
              ) ||
              previous.assistedWordIndices.contains(
                word.authoritativeWord.wordIndex,
              ))
            word.authoritativeWord.globalAyah,
      };
      if (selection.isEmpty) return;
    }
    await prepareSession(
      surahNumber: previous.surahNumber,
      startGlobalAyah: previous.startGlobalAyah,
      endGlobalAyah: previous.endGlobalAyah,
      planId: previous.planId,
      selectedGlobalAyahs: selection,
    );
  }

  /// Manually finishes the oral recitation session and builds the honest summary.
  Future<void> finishSession({bool notifyFeedback = true}) {
    if (isClosed || _isClosing || state.lifecycle.isCompleted) {
      return Future<void>.value();
    }
    final pending = _finishOperation;
    if (pending != null) return pending;
    final operation = _finishSession(notifyFeedback: notifyFeedback);
    _finishOperation = operation;
    return operation.whenComplete(() {
      if (identical(_finishOperation, operation)) _finishOperation = null;
    });
  }

  Future<void> _finishSession({required bool notifyFeedback}) async {
    final sessionId = state.sessionId;
    await _drainCapture();
    if (isClosed ||
        _isClosing ||
        state.lifecycle.isCompleted ||
        state.sessionId != sessionId) {
      return;
    }
    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.completed,
        summary: _buildSummary(),
        isDraining: false,
        isProcessingSpeech: false,
        audioLevel: 0,
      ),
    );
    if (notifyFeedback) {
      final completedCorrectly =
          state.targetWords.isNotEmpty &&
          state.alignedWords.length == state.targetWords.length &&
          state.alignedWords.every((word) => word.status.isMatched) &&
          state.unresolvedMistakeWordIndices.isEmpty;
      _emitFeedback(
        completedCorrectly ? RecitationCue.complete : RecitationCue.paused,
      );
    }
  }

  /// Preserve the final spoken phrase when stopping. Recognition stays
  /// subscribed until the native decoder has flushed its pending audio.
  Future<void> _drainCapture() {
    final pending = _drainOperation;
    if (pending != null) return pending;
    final operation = ++_captureOperation;
    final sessionId = state.sessionId;
    final drain = _performDrain(operation, sessionId);
    _drainOperation = drain;
    return drain.whenComplete(() {
      if (identical(_drainOperation, drain)) _drainOperation = null;
    });
  }

  Future<void> _performDrain(int operation, String? sessionId) async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    _acceptDrainingResults = true;
    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.paused,
        isDraining: true,
        audioLevel: 0,
      ),
    );

    try {
      await _releaseCapture(stop: true);
    } catch (_) {}
    // Broadcast stream delivery may follow the method-channel acknowledgement.
    await Future<void>.delayed(Duration.zero);
    if (!_isCurrentOperation(operation) || state.sessionId != sessionId) return;
    _acceptDrainingResults = false;
    _cancelSubscriptions();
    _restoreConfirmedAlignment();
    emit(state.copyWith(isDraining: false, isProcessingSpeech: false));
  }

  /// Commits verified session outcomes to [QuranMemorizationCubit] idempotently.
  Future<void> commitToMemorization() async {
    final summary = state.summary;
    final sessionId = state.sessionId;
    if (summary == null ||
        sessionId == null ||
        state.isMemorizationCommitted ||
        state.isCommittingToMemorization) {
      return;
    }

    emit(state.copyWith(isCommittingToMemorization: true, clearError: true));

    try {
      final heardAyahs = <int>{
        for (final word in state.alignedWords)
          if (!word.status.isUpcoming) word.authoritativeWord.globalAyah,
      };
      final evaluatedAyahs = heardAyahs
          .where(
            (ayah) => state.alignedWords
                .where((w) => w.authoritativeWord.globalAyah == ayah)
                .every(
                  (w) =>
                      !w.status.isUpcoming &&
                      w.authoritativeWord.wordIndex <
                          state.committedTargetIndex,
                ),
          )
          .toSet();
      if (evaluatedAyahs.isEmpty) {
        emit(
          state.copyWith(
            isCommittingToMemorization: false,
            errorMessage:
                'لم تُسمع آية مكتملة بعد، لذلك لم تُسجّل نتيجة في سجل الحفظ.',
          ),
        );
        return;
      }

      for (final globalAyah in evaluatedAyahs) {
        final opId = 'rec_oral_${sessionId}_$globalAyah';
        await memorizationCubit.recordReviewOutcome(
          globalAyah: globalAyah,
          outcome: _outcomeForAyah(globalAyah),
          sessionId: sessionId,
          planId: state.planId,
          operationId: opId,
        );
        if (isClosed || _isClosing || state.sessionId != sessionId) return;
      }

      emit(
        state.copyWith(
          isCommittingToMemorization: false,
          isMemorizationCommitted: true,
        ),
      );
    } catch (e) {
      if (isClosed || _isClosing || state.sessionId != sessionId) return;
      emit(
        state.copyWith(
          isCommittingToMemorization: false,
          errorMessage: 'تعذّر تسجيل التقدم في سجل الحفظ: $e',
        ),
      );
    }
  }

  void _onSpeechResult(SpeechRecognitionResultData result) {
    if (isClosed ||
        _isClosing ||
        (!state.lifecycle.isListening && !_acceptDrainingResults)) {
      return;
    }
    if (_acceptDrainingResults && !result.isFinal) return;

    final transcript = result.recognizedWords.trim();
    if (transcript.isEmpty) {
      _restoreConfirmedAlignment();
      emit(state.copyWith(liveTranscript: ''));
      return;
    }
    // Actual recognized speech establishes a healthy cycle. A previous
    // intermittent failure must not consume the budget for this whole session.
    _networkRestartAttempts = 0;
    _busyRestartAttempts = 0;

    // Deduplicate identical repeated callbacks if transcript hasn't changed
    if (transcript == _lastProcessedTranscript &&
        !result.isFinal &&
        !_isOffline) {
      return;
    }
    _lastProcessedTranscript = transcript;

    final alignResult = alignmentEngine.align(
      targetWords: state.targetWords,
      transcript: transcript,
      confidence: result.confidence,
      committedTargetIndex: _committedTargetIndex,
      committedAlignedWords: _committedAlignedWords.isNotEmpty
          ? _committedAlignedWords
          : null,
      committedDiscrepancies: _committedDiscrepancies.isNotEmpty
          ? _committedDiscrepancies
          : null,
      isFinal: result.isFinal,
      stopAtFirstMistake: !_isOffline,
      followRecitation: _isOffline,
      commitCompleteAyahsOnPartial: false,
    );

    final previewAyahs = <int>{};
    final previewWords = <int>{};
    if (_isOffline && !result.isFinal) {
      final wordCandidates = {
        for (final word in alignResult.alignedWords)
          if (word.status.isMatched &&
              word.authoritativeWord.wordIndex >= _committedTargetIndex)
            word.authoritativeWord.wordIndex,
      };
      previewWords.addAll(wordCandidates.intersection(_previousPreviewWords));
      previewWords.addAll(_contextBackedPreviewWords(alignResult.alignedWords));
      _previousPreviewWords = wordCandidates;
      final byAyah = <int, List<RecitationWordAlignment>>{};
      for (final word in alignResult.alignedWords) {
        (byAyah[word.authoritativeWord.globalAyah] ??= []).add(word);
      }
      final candidates = {
        for (final entry in byAyah.entries)
          if (entry.value.every((word) => word.status.isMatched)) entry.key,
      };
      // Two consecutive complete hypotheses may reveal the printed Ayah.
      // They never commit its cursor, finish a session, or award memorization.
      previewAyahs.addAll(candidates.intersection(_previousPreviewAyahs));
      _previousPreviewAyahs = candidates;
    } else {
      _previousPreviewAyahs = const {};
      _previousPreviewWords = const {};
    }

    final confirmedWords = result.isFinal
        ? alignResult.alignedWords
        : _committedAlignedWords;
    final confirmedVisible = _visibleConfirmedWords(confirmedWords);
    final visibleWords = {...confirmedVisible, ...previewWords};
    final retractedWords = _exposedPreviewWords.difference(visibleWords);
    _exposedPreviewWords = result.isFinal ? const {} : Set.of(previewWords);
    final unresolvedMistakes = _confirmedMistakes(confirmedWords);
    final previousUnresolved = state.unresolvedMistakeWordIndices;
    final mistakeHistory = {...state.mistakeWordIndices, ...unresolvedMistakes};
    final assistedWords = {
      ...state.assistedWordIndices,
      ...retractedWords,
      ...mistakeHistory,
    };

    final previewAssistance = _exposedPreviewAyahs
        .difference(
          result.isFinal ? alignResult.completedGlobalAyahs : previewAyahs,
        )
        .difference(state.hintedGlobalAyahs);
    // A later-retracted printed Ayah has nevertheless helped the reader.
    // Keep that assistance in the grade, while normally confirmed previews
    // retain ordinary credit.
    _exposedPreviewAyahs = result.isFinal ? const {} : Set.of(previewAyahs);

    // Monotonic invariant: committed cursor can only advance forward
    if (result.isFinal) {
      _committedTargetIndex = max(
        _committedTargetIndex,
        alignResult.committedTargetIndex,
      );
      _committedAlignedWords = List.unmodifiable(alignResult.alignedWords);
      _committedDiscrepancies = List.unmodifiable(alignResult.discrepancies);
    }

    if (result.isFinal) {
      _lastProcessedTranscript = ''; // Reset for next utterance
    }

    if (kDebugMode) {
      debugPrint(
        '[Q14_CUBIT_COMMIT] session=${state.sessionId} '
        'isFinal=${result.isFinal} '
        'alignCommitted=${alignResult.committedTargetIndex} '
        'newCommitted=$_committedTargetIndex '
        'currentAyah=${alignResult.currentGlobalAyah} '
        'currentWord=${alignResult.currentWordIndex} '
        'matched=${alignResult.matchedWordsCount} '
        'omi=${alignResult.omissionsCount} '
        'disc=${alignResult.discrepancies.length}',
      );
    }

    emit(
      state.copyWith(
        liveTranscript: transcript,
        alignedWords: alignResult.alignedWords,
        discrepancies: alignResult.discrepancies,
        currentGlobalAyah: _isOffline
            ? _displayAyah(visibleWords)
            : alignResult.currentGlobalAyah,
        currentWordIndex: alignResult.currentWordIndex,
        committedTargetIndex: _committedTargetIndex,
        progressPercentage: alignResult.progressPercentage,
        matchedWordsCount: alignResult.matchedWordsCount,
        omissionsCount: alignResult.omissionsCount,
        substitutionsCount: alignResult.substitutionsCount,
        uncertainCount: alignResult.uncertainCount,
        completedGlobalAyahs: alignResult.completedGlobalAyahs,
        previewCompletedGlobalAyahs: previewAyahs,
        visibleWordIndices: visibleWords,
        mistakeWordIndices: mistakeHistory,
        unresolvedMistakeWordIndices: unresolvedMistakes,
        assistedWordIndices: assistedWords,
        hintedGlobalAyahs: {...state.hintedGlobalAyahs, ...previewAssistance},
        hintCount: state.hintCount + previewAssistance.length,
        correctionWordIndex: alignResult.correctionWordIndex,
        clearCorrection: alignResult.correctionWordIndex == null,
      ),
    );

    if (result.isFinal) {
      final newMistakes = unresolvedMistakes.difference(previousUnresolved);
      final corrected = {
        for (final word in confirmedWords)
          if (word.status.isMatched &&
              previousUnresolved.contains(word.authoritativeWord.wordIndex) &&
              !unresolvedMistakes.contains(word.authoritativeWord.wordIndex))
            word.authoritativeWord.wordIndex,
      };
      if (newMistakes.isNotEmpty) {
        _emitFeedback(RecitationCue.mistake, wordIndices: newMistakes);
      } else if (corrected.isNotEmpty) {
        _emitFeedback(RecitationCue.corrected, wordIndices: corrected);
      }
    }

    if (result.isFinal &&
        alignResult.isCompleted &&
        unresolvedMistakes.isEmpty &&
        !_acceptDrainingResults) {
      unawaited(finishSession());
    }
  }

  /// A first hypothesis can show an exact prefix once a later recognized
  /// group supplies context. Keep its entire trailing group provisional:
  /// one ASR token such as الحمدلله can represent two Quranic words.
  /// This affects display only; committing, red errors and grading still use
  /// final speech, and retracted displayed words retain assistance accounting.
  Set<int> _contextBackedPreviewWords(List<RecitationWordAlignment> aligned) {
    final groups = <List<int>>[];
    var cursor = _committedTargetIndex;
    final whitespace = RegExp(r'\s+');
    while (cursor < aligned.length) {
      final first = aligned[cursor];
      final recognized = first.recognizedWord;
      if (!first.status.isMatched || recognized == null) break;
      var end = cursor + 1;
      while (end < aligned.length &&
          aligned[end].status.isMatched &&
          aligned[end].recognizedWord == recognized) {
        end++;
      }
      final actual = QuranRecitationText.normalize(recognized)
          .replaceAll(whitespace, '');
      var expectedForms = <String>{''};
      for (var index = cursor; index < end; index++) {
        final spellings = QuranRecitationText.spellings(
          aligned[index].authoritativeWord.uthmaniText,
        ).map((form) => form.replaceAll(whitespace, ''));
        expectedForms = {
          for (final prefix in expectedForms)
            for (final form in spellings)
              if (actual.startsWith('$prefix$form')) '$prefix$form',
        };
        if (expectedForms.isEmpty) break;
      }
      // Accept only exact documented orthographic forms, never similarity.
      // A mismatch or uncertain gap ends this fast path rather than jumping it.
      if (actual.isEmpty || !expectedForms.contains(actual)) break;
      groups.add([
        for (var index = cursor; index < end; index++)
          aligned[index].authoritativeWord.wordIndex,
      ]);
      cursor = end;
    }
    return {
      for (final group in groups.take(max(0, groups.length - 1))) ...group,
    };
  }

  void _onSpeechError(SpeechRecognitionFailure failure) {
    if (isClosed ||
        _isClosing ||
        (!state.lifecycle.isListening && !_acceptDrainingResults)) {
      return;
    }
    if (_acceptDrainingResults) {
      emit(state.copyWith(errorMessage: failure.message));
      return;
    }

    // Silence/no-match and a recognizer-busy race are normal boundaries of a
    // native speech session, especially on Android. Keep the UI listening and
    // start a clean recognition cycle instead of presenting a fatal error.
    final isBusy = failure.type == SpeechRecognitionFailureType.busy;
    final isNetwork = failure.type == SpeechRecognitionFailureType.network;
    final recoverable =
        !_isOffline &&
        (failure.type == SpeechRecognitionFailureType.noMatch ||
            failure.type == SpeechRecognitionFailureType.timeout ||
            isBusy ||
            isNetwork);
    final exhaustedBusyRetries = isBusy && ++_busyRestartAttempts > 3;
    final exhaustedNetworkRetries = isNetwork && ++_networkRestartAttempts > 2;
    if (recoverable && !exhaustedBusyRetries && !exhaustedNetworkRetries) {
      _recoveryPending = true;
      _scheduleRecognitionRestart(
        delay: isNetwork
            ? Duration(milliseconds: 750 * (1 << (_networkRestartAttempts - 1)))
            : isBusy
            ? Duration(milliseconds: 250 * _busyRestartAttempts)
            : const Duration(milliseconds: 250),
      );
      return;
    }

    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    _recoveryPending = false;
    // End capture on every fatal error, including network/audio failures.
    unawaited(_releaseCapture());
    _restoreConfirmedAlignment();
    if (failure.type == SpeechRecognitionFailureType.languageUnavailable) {
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.languageUnavailable,
          errorMessage: failure.message,
        ),
      );
      return;
    }

    if (failure.type == SpeechRecognitionFailureType.permissionDenied) {
      emit(
        state.copyWith(
          lifecycle: failure.isPermanent
              ? OralRecitationLifecycle.permissionPermanentlyDenied
              : OralRecitationLifecycle.permissionDenied,
          errorMessage: failure.message,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.paused,
        errorMessage: exhaustedBusyRetries
            ? 'خدمة التعرف الصوتي لا تستجيب. أغلق أي تطبيق يستخدم الميكروفون ثم اضغط متابعة، أو غيّر خدمة الإدخال الصوتي من إعدادات الجهاز.'
            : failure.message,
      ),
    );
  }

  void _onSpeechStatus(String status) {
    if (isClosed || _isClosing || !state.lifecycle.isListening) return;
    if (kDebugMode) {
      debugPrint(
        '[Q14_CUBIT_STATUS] status="$status" listening=${state.lifecycle.isListening}',
      );
    }
    if ((status == 'notListening' || status == 'done') &&
        state.lifecycle.isListening) {
      // Errors are commonly followed by both status events. Preserve the
      // error recovery backoff instead of repeatedly shortening it to 80ms.
      if (_recoveryPending) return;
      // A status event is not recognition evidence. Only finalized speech
      // commits words, otherwise a quiet timeout could freeze a false match.
      _lastProcessedTranscript =
          ''; // Reset deduplication buffer for fresh utterance

      // `done` means all callbacks from the previous native cycle have been
      // delivered and it is safe to re-arm. Keep a short fallback for devices
      // that only emit `notListening`.
      if (_isOffline) {
        _durationTimer?.cancel();
        _restoreConfirmedAlignment();
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.paused,
            audioLevel: 0,
            isProcessingSpeech: false,
          ),
        );
      } else if (!state.lifecycle.isPaused && !state.lifecycle.isCompleted) {
        _scheduleRecognitionRestart(
          delay: status == 'done'
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 450),
        );
      }
    } else if (status == 'listening') {
      _recognitionRestartTimer?.cancel();
      _recognitionRestartTimer = null;
    }
  }

  void _scheduleRecognitionRestart({
    Duration delay = const Duration(milliseconds: 250),
  }) {
    if (isClosed || !state.lifecycle.isListening) return;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = Timer(delay, () {
      _recognitionRestartTimer = null;
      unawaited(_restartRecognition());
    });
  }

  Future<void> _restartRecognition() async {
    if (isClosed || _isClosing || !state.lifecycle.isListening) {
      return;
    }
    if (_isStartingRecognition || _isRestartingRecognition) {
      _scheduleRecognitionRestart();
      return;
    }
    _isRestartingRecognition = true;
    _recoveryPending = true;
    final operation = _captureOperation;
    try {
      // Ensure the prior timed-out/error cycle releases the native recognizer
      // before the next listen call. This prevents Android's error_busy loop.
      try {
        await _releaseCapture();
      } catch (_) {}
      if (!_isCurrentOperation(operation) || !state.lifecycle.isListening) {
        return;
      }
      _recoveryPending = false;
      final restarted = await speechService.startListening(
        localeId: 'ar_SA',
        contextualPhrases: _recognitionHints(),
      );
      if (!_isCurrentOperation(operation) || !state.lifecycle.isListening) {
        try {
          await _releaseCapture();
        } catch (_) {}
        return;
      }
      if (!restarted && !isClosed && state.lifecycle.isListening) {
        if (_recognitionRestartTimer != null) return;
        _durationTimer?.cancel();
        _durationTimer = null;
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.paused,
            errorMessage: 'توقف الاستماع. اضغط متابعة، وتأكد من جاهزية حزمة اللغة العربية على الجهاز.',
          ),
        );
      } else if (restarted) {
        _startDurationTimer();
      }
    } catch (_) {
      if (_isCurrentOperation(operation)) {
        _onSpeechError(
          const SpeechRecognitionFailure(
            type: SpeechRecognitionFailureType.audio,
            message: 'تعذّر استئناف الميكروفون. اضغط متابعة للمحاولة مجددًا.',
          ),
        );
      }
    } finally {
      _isRestartingRecognition = false;
    }
  }

  ReviewOutcome _outcomeForAyah(int globalAyah) {
    final words = state.alignedWords
        .where((word) => word.authoritativeWord.globalAyah == globalAyah)
        .toList(growable: false);
    if (words.isEmpty) return ReviewOutcome.failed;
    if (state.hintedGlobalAyahs.contains(globalAyah) ||
        state.mode == OralRecitationMode.reading ||
        words.any((w) => !w.status.isMatched) ||
        words.any(
          (w) =>
              state.assistedWordIndices.contains(w.authoritativeWord.wordIndex),
        )) {
      return ReviewOutcome.difficult;
    }
    return state.mode == OralRecitationMode.hidden
        ? ReviewOutcome.easy
        : ReviewOutcome.good;
  }

  /// Supplies a compact window of upcoming Quranic words to recognizers that
  /// support contextual vocabulary (notably Apple Speech). Duplicates are
  /// removed to stay well below platform phrase limits.
  List<String> _recognitionHints() {
    if (state.targetWords.isEmpty) return const [];
    final start = _committedTargetIndex.clamp(0, state.targetWords.length);
    final end = min(state.targetWords.length, start + 80);
    return state.targetWords
        .sublist(start, end)
        .map((word) => word.normalizedText)
        .where((word) => word.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      emit(state.copyWith(durationSeconds: state.durationSeconds + 1));
    });
  }

  /// Remove speculative live words after pause, interruption, or finish.
  /// A missing final callback must never turn a preview into memorization.
  void _restoreConfirmedAlignment() {
    if (isClosed || _isClosing || state.targetWords.isEmpty) return;
    _previousPreviewAyahs = const {};
    _previousPreviewWords = const {};
    final words = _committedAlignedWords.isNotEmpty
        ? _committedAlignedWords
        : state.targetWords
              .map(
                (w) => RecitationWordAlignment(
                  authoritativeWord: w,
                  status: WordAlignmentStatus.upcoming,
                ),
              )
              .toList(growable: false);
    final matched = words.where((w) => w.status.isMatched).length;
    final ayahs = <int, List<RecitationWordAlignment>>{};
    for (final word in words) {
      (ayahs[word.authoritativeWord.globalAyah] ??= []).add(word);
    }
    final completed = {
      for (final entry in ayahs.entries)
        if (entry.value.every((w) => w.status.isMatched)) entry.key,
    };
    final previewAssistance = _exposedPreviewAyahs
        .difference(completed)
        .difference(state.hintedGlobalAyahs);
    _exposedPreviewAyahs = const {};
    final visibleWords = _visibleConfirmedWords(words);
    final retractedWords = _exposedPreviewWords.difference(visibleWords);
    _exposedPreviewWords = const {};
    final unresolvedMistakes = _confirmedMistakes(words);
    int? correction;
    for (
      var i = _isOffline ? 0 : _committedTargetIndex;
      i < words.length;
      i++
    ) {
      if (words[i].status.isUncertain &&
          state.assistedWordIndices.contains(i)) {
        continue;
      }
      if (words[i].status.isOmission ||
          words[i].status.isSubstitution ||
          words[i].status.isUncertain) {
        correction = i;
        break;
      }
    }
    final current = _isOffline
        ? _committedTargetIndex
        : correction ?? _committedTargetIndex;
    emit(
      state.copyWith(
        alignedWords: words,
        discrepancies: _committedDiscrepancies,
        committedTargetIndex: _committedTargetIndex,
        currentWordIndex: current,
        currentGlobalAyah: _isOffline
            ? _displayAyah(visibleWords)
            : state
                  .targetWords[current.clamp(0, state.targetWords.length - 1)]
                  .globalAyah,
        matchedWordsCount: matched,
        omissionsCount: words.where((w) => w.status.isOmission).length,
        substitutionsCount: words.where((w) => w.status.isSubstitution).length,
        uncertainCount: words.where((w) => w.status.isUncertain).length,
        progressPercentage: matched / words.length * 100,
        completedGlobalAyahs: completed,
        previewCompletedGlobalAyahs: const {},
        visibleWordIndices: visibleWords,
        unresolvedMistakeWordIndices: unresolvedMistakes,
        assistedWordIndices: {
          ...state.assistedWordIndices,
          ...retractedWords,
          ...state.mistakeWordIndices,
        },
        hintedGlobalAyahs: {...state.hintedGlobalAyahs, ...previewAssistance},
        hintCount: state.hintCount + previewAssistance.length,
        correctionWordIndex: correction,
        clearCorrection: correction == null,
      ),
    );
  }

  Set<int> _visibleConfirmedWords(Iterable<RecitationWordAlignment> words) => {
    for (final word in words)
      if (word.status.isMatched ||
          word.status.isSubstitution ||
          word.status.isOmission)
        word.authoritativeWord.wordIndex,
  };

  Set<int> _confirmedMistakes(Iterable<RecitationWordAlignment> words) => {
    for (final word in words)
      if (word.status.isSubstitution || word.status.isOmission)
        word.authoritativeWord.wordIndex,
  };

  int _displayAyah(Set<int> visibleWords) {
    // The next listening cursor can lie in an unread Ayah/page. Only a
    // supported visible word can make the Mushaf follow to that page.
    final index = visibleWords.isEmpty ? 0 : visibleWords.reduce(max);
    return state
        .targetWords[index.clamp(0, state.targetWords.length - 1)]
        .globalAyah;
  }

  OralRecitationSessionSummary _buildSummary() {
    final totalAyahs = state.targetWords
        .map((w) => w.globalAyah)
        .toSet()
        .length;
    final matchedAyahs = state.completedGlobalAyahs.length;
    final attempted = state.attemptedWords;

    return OralRecitationSessionSummary(
      sessionId:
          state.sessionId ?? 'oral_${DateTime.now().millisecondsSinceEpoch}',
      startGlobalAyah: state.startGlobalAyah,
      endGlobalAyah: state.endGlobalAyah,
      surahNumber: state.surahNumber,
      surahName: state.surahName,
      totalAyahs: totalAyahs,
      matchedAyahs: matchedAyahs,
      totalWords: state.targetWords.length,
      matchedWords: state.matchedWordsCount,
      omissionsCount: state.omissionsCount,
      substitutionsCount: state.substitutionsCount,
      uncertainCount: state.uncertainCount,
      accuracyPercentage: attempted == 0
          ? 0
          : state.matchedWordsCount / attempted * 100,
      attemptedWords: attempted,
      coveragePercentage: state.coveragePercentage,
      hintCount: state.hintCount,
      assistedWords: state.assistedWordIndices.length,
      mode: state.mode,
      durationSeconds: state.durationSeconds,
      discrepancies: state.discrepancies,
      detectedMistakesCount: state.mistakeWordIndices.length,
      correctedMistakesCount: state.mistakeWordIndices
          .difference(state.unresolvedMistakeWordIndices)
          .where((index) => state.alignedWords[index].status.isMatched)
          .length,
      completedAt: DateTime.now(),
    );
  }

  void _cancelSubscriptions() {
    _resultSubscription?.cancel();
    _errorSubscription?.cancel();
    _statusSubscription?.cancel();
    _levelSubscription?.cancel();
    _processingSubscription?.cancel();
    _resultSubscription = null;
    _errorSubscription = null;
    _statusSubscription = null;
    _levelSubscription = null;
    _processingSubscription = null;
  }

  @override
  Future<void> close() async {
    _isClosing = true;
    ++_captureOperation;
    _durationTimer?.cancel();
    _recognitionRestartTimer?.cancel();
    _cancelSubscriptions();
    try {
      if (ownsSpeechService) {
        await speechService.dispose();
      } else {
        await _releaseCapture(stop: true);
      }
    } catch (_) {}
    await _feedback.close();
    return super.close();
  }
}
