import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/audio_service.dart';
import '../../data/models/oral_recitation_models.dart';
import '../../data/models/murajaah_models.dart';
import '../../data/models/quran_models.dart';
import '../../data/repositories/quran_repository.dart';
import '../services/quran_alignment_engine.dart';
import '../services/speech_recognition_service.dart';
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
       super(const QuranOralRecitationState());

  final SpeechRecognitionService speechService;
  final QuranAlignmentEngine alignmentEngine;
  final QuranRepository quranRepository;
  final QuranMemorizationCubit memorizationCubit;
  final QuranAudioService? audioService;
  final bool ownsSpeechService;

  StreamSubscription<SpeechRecognitionResultData>? _resultSubscription;
  StreamSubscription<SpeechRecognitionFailure>? _errorSubscription;
  StreamSubscription<String>? _statusSubscription;
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

  bool _isCurrentOperation(int operation) =>
      !isClosed && !_isClosing && operation == _captureOperation;

  int _committedTargetIndex = 0;
  List<RecitationWordAlignment> _committedAlignedWords = const [];
  List<RecitationDiscrepancy> _committedDiscrepancies = const [];
  String _lastProcessedTranscript = '';

  /// Prepares an oral recitation session for a target Surah or Ayah range.
  Future<void> prepareSession({
    required int surahNumber,
    int? startGlobalAyah,
    int? endGlobalAyah,
    String? planId,
  }) async {
    if (isClosed || _isClosing) return;
    final operation = ++_captureOperation;
    _busyRestartAttempts = 0;
    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    _cancelSubscriptions();
    try {
      await speechService.cancelListening();
    } catch (_) {}
    if (!_isCurrentOperation(operation)) return;
    _committedTargetIndex = 0;
    _committedAlignedWords = const [];
    _committedDiscrepancies = const [];
    _lastProcessedTranscript = '';

    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.idle,
        clearError: true,
        isMemorizationCommitted: false,
        committedTargetIndex: 0,
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

      final rawStart = (startGlobalAyah ?? chapter.globalStart).clamp(1, 6236);
      final rawEnd =
          (endGlobalAyah ?? (chapter.globalStart + chapter.ayahs.length - 1))
              .clamp(1, 6236);
      final resolvedStart = min(rawStart, rawEnd);
      final resolvedEnd = max(rawStart, rawEnd);

      final targetWords = alignmentEngine.prepareTargetTokens(
        chapters: chapters,
        startGlobalAyah: resolvedStart,
        endGlobalAyah: resolvedEnd,
      );

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
      if (hasPerm) {
        final available = await speechService.initialize();
        if (!_isCurrentOperation(operation)) return;
        if (available) {
          lifecycle = OralRecitationLifecycle.ready;
        } else {
          lifecycle = OralRecitationLifecycle.recognizerUnavailable;
          errorMessage = 'خدمة التعرف الصوتي غير جاهزة على هذا الجهاز. فعّل خدمة التعرف على الكلام أو نزّل حزمة اللغة العربية ثم أعد المحاولة.';
        }
      }

      emit(
        state.copyWith(
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
          currentGlobalAyah: resolvedStart,
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
              errorMessage: 'خدمة التعرف الصوتي غير جاهزة على هذا الجهاز. فعّل خدمة التعرف على الكلام أو نزّل حزمة اللغة العربية ثم أعد المحاولة.',
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
            errorMessage: 'خدمة التعرف الصوتي غير جاهزة على هذا الجهاز. فعّل خدمة التعرف على الكلام ثم أعد المحاولة.',
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
  Future<void> startRecitation() async {
    if (isClosed ||
        _isClosing ||
        _isStartingRecognition ||
        _isRestartingRecognition ||
        _isProcessingPermission ||
        state.targetWords.isEmpty ||
        state.lifecycle.isListening ||
        state.lifecycle.isCompleted) {
      return;
    }
    _isStartingRecognition = true;
    final operation = ++_captureOperation;
    _busyRestartAttempts = 0;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    try {
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
      // Accept synchronous native callbacks during startup.
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.listening,
          clearError: true,
        ),
      );
      final ok = await speechService.startListening(
        localeId: 'ar_SA',
        contextualPhrases: _recognitionHints(),
      );
      if (!_isCurrentOperation(operation) || !state.lifecycle.isListening) {
        // A late native start must not turn the mic back on after pause/exit.
        try {
          await speechService.cancelListening();
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
  Future<void> pauseRecitation() async {
    if (isClosed ||
        _isClosing ||
        state.lifecycle.isCompleted ||
        (!state.lifecycle.isListening && !_isStartingRecognition)) {
      return;
    }
    ++_captureOperation;
    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    emit(state.copyWith(lifecycle: OralRecitationLifecycle.paused));
    try {
      await speechService.stopListening();
    } catch (_) {}
  }

  Future<void> resumeRecitation() async {
    if (!state.lifecycle.isPaused) return;
    await startRecitation();
  }

  /// Reveals the authoritative Uthmani text for a specific Ayah during the session.
  void revealAyah(int globalAyah) {
    final updated = Set<int>.from(state.revealedGlobals)..add(globalAyah);
    emit(state.copyWith(revealedGlobals: updated));
  }

  /// Hides the authoritative text for an Ayah again.
  void hideAyah(int globalAyah) {
    final updated = Set<int>.from(state.revealedGlobals)..remove(globalAyah);
    emit(state.copyWith(revealedGlobals: updated));
  }

  /// Manually finishes the oral recitation session and builds the honest summary.
  Future<void> finishSession() async {
    if (isClosed || _isClosing || state.lifecycle.isCompleted) return;
    ++_captureOperation;
    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    _cancelSubscriptions();

    final summary = _buildSummary();

    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.completed,
        summary: summary,
      ),
    );

    try {
      await speechService.stopListening();
    } catch (_) {}
  }

  /// Commits verified session outcomes to [QuranMemorizationCubit] idempotently.
  Future<void> commitToMemorization() async {
    final summary = state.summary;
    final sessionId = state.sessionId;
    if (summary == null || sessionId == null || state.isMemorizationCommitted) {
      return;
    }

    emit(state.copyWith(isCommittingToMemorization: true, clearError: true));

    try {
      final evaluatedAyahs = <int>{
        for (final word in state.alignedWords)
          if (!word.status.isUpcoming) word.authoritativeWord.globalAyah,
      };
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
      }

      emit(
        state.copyWith(
          isCommittingToMemorization: false,
          isMemorizationCommitted: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isCommittingToMemorization: false,
          errorMessage: 'تعذّر تسجيل التقدم في سجل الحفظ: $e',
        ),
      );
    }
  }

  void _onSpeechResult(SpeechRecognitionResultData result) {
    if (isClosed || _isClosing || !state.lifecycle.isListening) return;

    final transcript = result.recognizedWords.trim();
    if (transcript.isEmpty) return;
    _busyRestartAttempts = 0;

    // Deduplicate identical repeated callbacks if transcript hasn't changed
    if (transcript == _lastProcessedTranscript && !result.isFinal) {
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
    );

    // Monotonic invariant: committed cursor can only advance forward
    if (alignResult.committedTargetIndex > _committedTargetIndex) {
      _committedTargetIndex = alignResult.committedTargetIndex;
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
        currentGlobalAyah: alignResult.currentGlobalAyah,
        currentWordIndex: alignResult.currentWordIndex,
        committedTargetIndex: _committedTargetIndex,
        progressPercentage: alignResult.progressPercentage,
        matchedWordsCount: alignResult.matchedWordsCount,
        omissionsCount: alignResult.omissionsCount,
        substitutionsCount: alignResult.substitutionsCount,
        uncertainCount: alignResult.uncertainCount,
        completedGlobalAyahs: alignResult.completedGlobalAyahs,
      ),
    );

    if (alignResult.isCompleted) {
      finishSession();
    }
  }

  void _onSpeechError(SpeechRecognitionFailure failure) {
    if (isClosed || _isClosing || !state.lifecycle.isListening) return;

    // Silence/no-match and a recognizer-busy race are normal boundaries of a
    // native speech session, especially on Android. Keep the UI listening and
    // start a clean recognition cycle instead of presenting a fatal error.
    final recoverable =
        failure.type == SpeechRecognitionFailureType.noMatch ||
        failure.type == SpeechRecognitionFailureType.timeout ||
        failure.type == SpeechRecognitionFailureType.busy;
    final exhaustedBusyRetries =
        failure.type == SpeechRecognitionFailureType.busy &&
        ++_busyRestartAttempts > 3;
    if (recoverable && !exhaustedBusyRetries) {
      _scheduleRecognitionRestart();
      return;
    }

    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    // End capture on every fatal error, including network/audio failures.
    unawaited(speechService.cancelListening().catchError((Object _) {}));
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
      // On pause / utterance end: commit current target progress if forward
      if (state.currentWordIndex > _committedTargetIndex) {
        _committedTargetIndex = state.currentWordIndex;
        if (state.alignedWords.isNotEmpty) {
          _committedAlignedWords = List.unmodifiable(state.alignedWords);
          _committedDiscrepancies = List.unmodifiable(state.discrepancies);
        }
      }
      _lastProcessedTranscript =
          ''; // Reset deduplication buffer for fresh utterance

      // `done` means all callbacks from the previous native cycle have been
      // delivered and it is safe to re-arm. Keep a short fallback for devices
      // that only emit `notListening`.
      if (!state.lifecycle.isPaused && !state.lifecycle.isCompleted) {
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
    final operation = _captureOperation;
    try {
      // Ensure the prior timed-out/error cycle releases the native recognizer
      // before the next listen call. This prevents Android's error_busy loop.
      try {
        await speechService.cancelListening();
      } catch (_) {}
      if (!_isCurrentOperation(operation) || !state.lifecycle.isListening) {
        return;
      }
      final restarted = await speechService.startListening(
        localeId: 'ar_SA',
        contextualPhrases: _recognitionHints(),
      );
      if (!_isCurrentOperation(operation) || !state.lifecycle.isListening) {
        try {
          await speechService.cancelListening();
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
    final matched = words.where((word) => word.status.isMatched).length;
    final omissions = words.where((word) => word.status.isOmission).length;
    final substitutions = words
        .where((word) => word.status.isSubstitution)
        .length;
    final score = matched / words.length * 100;
    if (score >= 95 && omissions == 0 && substitutions == 0) {
      return ReviewOutcome.easy;
    }
    if (score >= 85 && substitutions <= 1 && omissions <= 1) {
      return ReviewOutcome.good;
    }
    if (score >= 65) return ReviewOutcome.difficult;
    return ReviewOutcome.failed;
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

  OralRecitationSessionSummary _buildSummary() {
    final totalAyahs = (state.endGlobalAyah - state.startGlobalAyah + 1).clamp(
      1,
      6236,
    );
    final matchedAyahs = state.completedGlobalAyahs.length;

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
      accuracyPercentage: state.progressPercentage,
      durationSeconds: state.durationSeconds,
      discrepancies: state.discrepancies,
      completedAt: DateTime.now(),
    );
  }

  void _cancelSubscriptions() {
    _resultSubscription?.cancel();
    _errorSubscription?.cancel();
    _statusSubscription?.cancel();
    _resultSubscription = null;
    _errorSubscription = null;
    _statusSubscription = null;
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
        await speechService.stopListening();
      }
    } catch (_) {}
    return super.close();
  }
}
