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
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<String>? _statusSubscription;
  Timer? _durationTimer;
  Timer? _recognitionRestartTimer;
  QuranData? _quranData;
  bool _isProcessingPermission = false;
  bool _isRestartingRecognition = false;

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
    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    _cancelSubscriptions();
    try {
      await speechService.cancelListening();
    } catch (_) {}
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
      var lifecycle = OralRecitationLifecycle.permissionDenied;
      String? errorMessage;
      if (hasPerm) {
        final available = await speechService.initialize();
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
    if (_isProcessingPermission || isClosed) return;
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

      // 3. If not yet granted, invoke native permission request
      if (!hasPerm) {
        hasPerm = await speechService.requestPermission();
      }

      if (isClosed) return;

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
      if (isClosed) return;

      if (!isAvailable) {
        final stillHasPerm = await speechService.hasPermission();
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
      if (isClosed) return;
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

  /// Re-evaluates permission status and engine availability (e.g. after returning from Settings).
  Future<void> checkAndRefreshPermission() async {
    if (isClosed || state.lifecycle.isListening) return;
    final shouldRemainPaused = state.lifecycle.isPaused;

    final hasPerm = await speechService.hasPermission();
    if (!hasPerm) {
      if (state.lifecycle ==
          OralRecitationLifecycle.permissionPermanentlyDenied) {
        return;
      }
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
    if (isClosed) return;

    if (isAvailable) {
      emit(
        state.copyWith(
          lifecycle: shouldRemainPaused
              ? OralRecitationLifecycle.paused
              : OralRecitationLifecycle.ready,
          clearError: true,
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
  }

  /// Begins real microphone capture and speech alignment.
  Future<void> startRecitation() async {
    if (state.targetWords.isEmpty) return;
    if (state.lifecycle.isListening) return;

    // 1. Audio policy: Stop any background Quran recitation playback
    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }

    // 2. Ensure permission & engine readiness before starting
    if (!state.lifecycle.isReady) {
      await requestPermissionAndInitialize();
      if (!state.lifecycle.isReady) return;
    }

    // 3. Setup listeners
    _cancelSubscriptions();

    _resultSubscription = speechService.resultsStream.listen(_onSpeechResult);
    _errorSubscription = speechService.errorStream.listen(_onSpeechError);
    _statusSubscription = speechService.statusStream.listen(_onSpeechStatus);

    // 4. Enter listening before awaiting the native callback. Some engines
    // emit their first status/result synchronously with the listen request;
    // those events must not be discarded while the state is still `ready`.
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
    if (!ok) {
      _cancelSubscriptions();
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.error,
          errorMessage: 'تعذر تشغيل الميكروفون وبدء الاستماع. حاول مرة أخرى.',
        ),
      );
      return;
    }

    if (state.lifecycle.isListening) {
      _startDurationTimer();
    }
  }

  /// Pauses microphone capture and pauses the timer.
  Future<void> pauseRecitation() async {
    if (!state.lifecycle.isListening) return;

    _durationTimer?.cancel();
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    emit(state.copyWith(lifecycle: OralRecitationLifecycle.paused));
    await speechService.stopListening();
  }

  /// Resumes microphone capture from a paused state.
  Future<void> resumeRecitation() async {
    if (!state.lifecycle.isPaused) return;

    if (audioService != null) {
      try {
        await audioService!.stop();
      } catch (_) {}
    }

    // As with the initial start, do not leave a window where native callbacks
    // arrive while the Cubit still reports `paused`.
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
    if (ok && state.lifecycle.isListening) {
      _startDurationTimer();
    } else if (!ok) {
      emit(
        state.copyWith(
          lifecycle: OralRecitationLifecycle.paused,
          errorMessage: 'تعذّر استئناف الاستماع. تأكد من جاهزية الميكروفون وحزمة اللغة العربية.',
        ),
      );
    }
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
    if (isClosed || !state.hasActiveSession) return;

    final transcript = result.recognizedWords.trim();
    if (transcript.isEmpty) return;

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

  void _onSpeechError(String error) {
    if (isClosed) return;

    // Silence/no-match and a recognizer-busy race are normal boundaries of a
    // native speech session, especially on Android. Keep the UI listening and
    // start a clean recognition cycle instead of presenting a fatal error.
    final recoverable =
        error.startsWith('لم أتمكن من تمييز الكلام') ||
        error.startsWith('لم يُسمع صوت لفترة') ||
        error.startsWith('محرك التعرف الصوتي مشغول مؤقتًا');
    if (recoverable && state.lifecycle.isListening) {
      _scheduleRecognitionRestart();
      return;
    }

    _durationTimer?.cancel();
    _durationTimer = null;
    _recognitionRestartTimer?.cancel();
    _recognitionRestartTimer = null;
    emit(
      state.copyWith(
        lifecycle: OralRecitationLifecycle.paused,
        errorMessage: error,
      ),
    );
  }

  void _onSpeechStatus(String status) {
    if (isClosed) return;
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
    if (_isRestartingRecognition || isClosed || !state.lifecycle.isListening) {
      return;
    }
    _isRestartingRecognition = true;
    try {
      // Ensure the prior timed-out/error cycle releases the native recognizer
      // before the next listen call. This prevents Android's error_busy loop.
      try {
        await speechService.cancelListening();
      } catch (_) {}
      if (isClosed || !state.lifecycle.isListening) return;
      final restarted = await speechService.startListening(
        localeId: 'ar_SA',
        contextualPhrases: _recognitionHints(),
      );
      if (!restarted && !isClosed && state.lifecycle.isListening) {
        _durationTimer?.cancel();
        _durationTimer = null;
        emit(
          state.copyWith(
            lifecycle: OralRecitationLifecycle.paused,
            errorMessage: 'توقف الاستماع. اضغط متابعة، وتأكد من جاهزية حزمة اللغة العربية على الجهاز.',
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
