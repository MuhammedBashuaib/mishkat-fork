import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mishkat_app/core/services/audio_service.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/data/repositories/mushaf_layout_repository.dart';
import 'package:mishkat_app/features/quran/data/repositories/quran_repository.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/mushaf_interaction_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/widgets/mushaf_ayah_overlay.dart';

class InMemoryLocalStorageService implements LocalStorageService {
  final Map<String, dynamic> _store = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, dynamic> readMap(String key) {
    final val = _store[key];
    return val is Map ? Map<String, dynamic>.from(val) : <String, dynamic>{};
  }

  @override
  List<dynamic> readList(String key) {
    final val = _store[key];
    return val is List ? List<dynamic>.from(val) : <dynamic>[];
  }

  @override
  int readInt(String key, [int fallback = 0]) {
    final val = _store[key];
    return val is num ? val.toInt() : fallback;
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _store[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeList(String key, List<dynamic> value) async {
    _store[key] = List<dynamic>.from(value);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

class DummyAudioService implements QuranAudioService {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();

  @override
  bool get isPlaying => false;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Duration? get duration => null;

  @override
  Future<void> playAyah({
    required String reciter,
    required int globalAyah,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranData quranData;
  late MushafLayoutRepository layoutRepo;

  setUpAll(() async {
    quranData = await QuranRepository().load();
    layoutRepo = MushafLayoutRepository();
    final jsonStr = await File('assets/data/mushaf-layout.json').readAsString();
    layoutRepo.loadFromJsonString(jsonStr);
  });

  group('A. Bookmark CRUD & State Management Tests', () {
    late InMemoryLocalStorageService storage;
    late QuranCubit cubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      cubit = QuranCubit(
        storage: storage,
        repository: QuranRepository(),
        audio: DummyAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await cubit.load();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('Initial state has no bookmarks', () {
      expect(cubit.state.bookmarks, isEmpty);
      expect(cubit.state.isAyahBookmarked(1), isFalse);
    });

    test('toggleAyahBookmark adds a new Ayah bookmark', () async {
      // Bookmark Ayat al-Kursi (2:255, global: 262, page: 42)
      await cubit.toggleAyahBookmark(262, label: 'آية الكرسي');

      expect(cubit.state.bookmarks.length, 1);
      expect(cubit.state.isAyahBookmarked(262), isTrue);

      final bookmark = cubit.state.getBookmarkForAyah(262);
      expect(bookmark, isNotNull);
      expect(bookmark!.point.global, 262);
      expect(bookmark.point.surah, 2);
      expect(bookmark.point.ayah, 255);
      expect(bookmark.page, 42);
      expect(bookmark.label, 'آية الكرسي');
    });

    test('toggleAyahBookmark removes an existing Ayah bookmark', () async {
      await cubit.toggleAyahBookmark(262);
      expect(cubit.state.isAyahBookmarked(262), isTrue);

      // Toggle again to remove
      await cubit.toggleAyahBookmark(262);
      expect(cubit.state.bookmarks, isEmpty);
      expect(cubit.state.isAyahBookmarked(262), isFalse);
      expect(cubit.state.getBookmarkForAyah(262), isNull);
    });

    test('removeBookmark removes by globalAyah', () async {
      await cubit.toggleAyahBookmark(1);
      await cubit.toggleAyahBookmark(262);
      expect(cubit.state.bookmarks.length, 2);

      await cubit.removeBookmark(1);
      expect(cubit.state.bookmarks.length, 1);
      expect(cubit.state.isAyahBookmarked(1), isFalse);
      expect(cubit.state.isAyahBookmarked(262), isTrue);
    });

    test('clearAllBookmarks empties all bookmarks', () async {
      await cubit.toggleAyahBookmark(1);
      await cubit.toggleAyahBookmark(2);
      await cubit.toggleAyahBookmark(3);
      expect(cubit.state.bookmarks.length, 3);

      await cubit.clearAllBookmarks();
      expect(cubit.state.bookmarks, isEmpty);
    });

    test(
      'Bookmarks persist to storage and restore accurately on reload',
      () async {
        await cubit.toggleAyahBookmark(262, label: 'حفظ ورد');
        await cubit.toggleAyahBookmark(1);

        // Create new Cubit instance with same storage
        final newCubit = QuranCubit(
          storage: storage,
          repository: QuranRepository(),
          audio: DummyAudioService(),
          reciter: 'ar.alafasy',
          fontSize: 22.0,
        );
        await newCubit.load();

        expect(newCubit.state.bookmarks.length, 2);
        expect(newCubit.state.isAyahBookmarked(262), isTrue);
        expect(newCubit.state.isAyahBookmarked(1), isTrue);
        expect(newCubit.state.getBookmarkForAyah(262)?.label, 'حفظ ورد');

        await newCubit.close();
      },
    );
  });

  group('B. Ayah-Level vs Page-Level Bookmarking Coexistence', () {
    late InMemoryLocalStorageService storage;
    late QuranCubit cubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      cubit = QuranCubit(
        storage: storage,
        repository: QuranRepository(),
        audio: DummyAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await cubit.load();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('Multiple Ayahs on the same page can be bookmarked simultaneously without overwriting', () async {
      // Page 1 contains Surah Al-Fatiha (Ayahs 1 to 7, globals: 1 to 7)
      await cubit.toggleAyahBookmark(1); // 1:1
      await cubit.toggleAyahBookmark(2); // 1:2
      await cubit.toggleAyahBookmark(7); // 1:7

      expect(cubit.state.bookmarks.length, 3);

      final page1Bookmarks = cubit.state.getBookmarksForPage(1);
      expect(page1Bookmarks.length, 3);
      expect(page1Bookmarks.map((b) => b.point.global).toSet(), {1, 2, 7});

      // Toggling one does not delete others on same page
      await cubit.toggleAyahBookmark(2);
      expect(cubit.state.getBookmarksForPage(1).length, 2);
      expect(cubit.state.isAyahBookmarked(1), isTrue);
      expect(cubit.state.isAyahBookmarked(2), isFalse);
      expect(cubit.state.isAyahBookmarked(7), isTrue);
    });

    test('Legacy toggleBookmark on current page works gracefully', () async {
      await cubit.openPage(1);
      // Calls page-level toggle
      cubit.toggleBookmark();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.bookmarks.length, 1);
      expect(cubit.state.bookmarks.first.page, 1);
      expect(cubit.state.bookmarks.first.point.global, 1);

      // Second page toggle removes it
      cubit.toggleBookmark();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.bookmarks, isEmpty);
    });
  });

  group('C. Corrupted JSON & Out-of-Range Recovery', () {
    test(
      'Recovers gracefully from corrupted, null, and out-of-range storage data',
      () async {
        final storage = InMemoryLocalStorageService();

        // Seed storage with invalid entries:
        // 1. null element
        // 2. non-map element
        // 3. missing point
        // 4. out-of-range global (0, -1, 6237, 99999)
        // 5. valid bookmark (global 262)
        // 6. duplicate valid bookmark
        await storage.writeMap('quran', {
          'page': 1,
          'bookmarks': [
            null,
            'invalid string entry',
            42,
            {'page': 1}, // missing point
            {
              'page': 1,
              'point': {'s': 1, 'a': 1, 'g': 0},
            }, // out of range
            {
              'page': 1,
              'point': {'s': 1, 'a': 1, 'g': 6237},
            }, // out of range
            {
              'page': 1,
              'point': {'s': 1, 'a': 1, 'g': -10},
            }, // negative
            {
              'page': 42,
              'point': {'s': 2, 'a': 255, 'g': 262},
              'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            }, // VALID
            {
              'page': 42,
              'point': {'s': 2, 'a': 255, 'g': 262}, // DUPLICATE OF 262
              'createdAt': DateTime(2026, 1, 2).toIso8601String(),
            },
          ],
          'lastRead': {'s': 1, 'a': 1, 'g': 99999}, // corrupted out of range
        });

        final cubit = QuranCubit(
          storage: storage,
          repository: QuranRepository(),
          audio: DummyAudioService(),
          reciter: 'ar.alafasy',
          fontSize: 22.0,
        );

        // Loading must not throw or crash
        await cubit.load();

        // Exactly 1 valid, deduplicated bookmark preserved
        expect(cubit.state.bookmarks.length, 1);
        expect(cubit.state.bookmarks.first.point.global, 262);

        // Corrupted lastRead was ignored safely (defaults to null or page fallback)
        expect(cubit.state.lastRead, isNull);

        await cubit.close();
      },
    );
  });

  group('D. Reading Continuity & Last Read Engine', () {
    late InMemoryLocalStorageService storage;
    late QuranCubit cubit;

    setUp(() async {
      storage = InMemoryLocalStorageService();
      cubit = QuranCubit(
        storage: storage,
        repository: QuranRepository(),
        audio: DummyAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await cubit.load();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('setLastRead updates state.lastRead deterministically', () async {
      // Set Surat Al-Kahf (18:1, global: 2141, page: 293)
      await cubit.setLastRead(2141);

      expect(cubit.state.lastRead, isNotNull);
      expect(cubit.state.lastRead!.global, 2141);
      expect(cubit.state.lastRead!.surah, 18);
      expect(cubit.state.lastRead!.ayah, 1);
      expect(cubit.state.currentPage, 293);
    });

    test('openPage updates lastRead and currentPage', () async {
      await cubit.openPage(
        100,
        point: const QuranPoint(surah: 4, ayah: 141, global: 634),
      );

      expect(cubit.state.currentPage, 100);
      expect(cubit.state.lastRead?.global, 634);
    });

    test('Last read position persists and restores across reboots', () async {
      await cubit.setLastRead(262);

      final restartedCubit = QuranCubit(
        storage: storage,
        repository: QuranRepository(),
        audio: DummyAudioService(),
        reciter: 'ar.alafasy',
        fontSize: 22.0,
      );
      await restartedCubit.load();

      expect(restartedCubit.state.lastRead, isNotNull);
      expect(restartedCubit.state.lastRead!.global, 262);
      expect(restartedCubit.state.currentPage, 42);

      await restartedCubit.close();
    });
  });

  group('E. State Isolation: Selected, Playing, and Bookmarked', () {
    test('selectedAyah, playingAyah, and bookmarkedAyahs remain strictly independent', () {
      final ayah1 = layoutRepo.getAyah(1)!;
      final ayah2 = layoutRepo.getAyah(2)!;
      final ayah3 = layoutRepo.getAyah(3)!;

      // 1. Interaction cubit holds selectedAyah
      final interactionCubit = MushafInteractionCubit(
        layoutRepository: layoutRepo,
      );
      interactionCubit.selectAyah(ayah1);
      expect(interactionCubit.state.selectedAyah, ayah1);
      expect(interactionCubit.state.playingAyah, isNull);

      // 2. Audio playback updates playingAyah independently
      interactionCubit.setPlayingAyah(ayah2.globalAyah);
      expect(interactionCubit.state.selectedAyah, ayah1);
      expect(interactionCubit.state.playingAyah, ayah2.globalAyah);

      // 3. Bookmark overlay receives bookmarkedAyahs list independently
      const overlay = MushafAyahOverlay(
        viewBox: Rect.fromLTWH(0, 0, 345, 550),
        selectedAyah: null,
        playingAyah: null,
        bookmarkedAyahs: [],
      );
      expect(overlay.bookmarkedAyahs, isEmpty);

      final populatedOverlay = MushafAyahOverlay(
        viewBox: const Rect.fromLTWH(0, 0, 345, 550),
        selectedAyah: ayah1,
        playingAyah: ayah2,
        bookmarkedAyahs: [ayah3],
      );
      expect(populatedOverlay.selectedAyah, ayah1);
      expect(populatedOverlay.playingAyah, ayah2);
      expect(populatedOverlay.bookmarkedAyahs, [ayah3]);

      interactionCubit.close();
    });
  });

  group('F. Full Quran 6,236 Ayah Completeness Verification', () {
    test('All 6,236 Ayahs resolve deterministically to page, surah, ayah, and layout bounds', () {
      for (var global = 1; global <= 6236; global++) {
        final point = quranData.pointForGlobal(global);
        expect(point.global, global);
        expect(point.surah, inInclusiveRange(1, 114));

        final chapter = quranData.chapter(point.surah);
        expect(point.ayah, inInclusiveRange(1, chapter.ayahs.length));

        final page = quranData.pageForGlobal(global);
        expect(page, inInclusiveRange(1, 604));

        final layoutAyah = layoutRepo.getAyah(global);
        expect(
          layoutAyah,
          isNotNull,
          reason: 'Ayah $global must exist in layout data',
        );
        expect(layoutAyah!.page, page, reason: 'Ayah $global page mismatch');
        expect(layoutAyah.surah, point.surah);
        expect(layoutAyah.ayah, point.ayah);
      }
    });

    test(
      'Creating QuranBookmark for any valid global Ayah produces coherent JSON',
      () {
        final point = quranData.pointForGlobal(6236); // An-Nas: 6
        final page = quranData.pageForGlobal(6236);

        final bookmark = QuranBookmark(
          page: page,
          point: point,
          createdAt: DateTime.now(),
          label: 'آخر آية',
        );

        final json = bookmark.toJson();
        expect(json['page'], 604);
        expect(json['label'], 'آخر آية');
        expect(json['point']['g'], 6236);

        final restored = QuranBookmark.fromJson(json);
        expect(restored.point.global, 6236);
        expect(restored.page, 604);
        expect(restored.label, 'آخر آية');
      },
    );
  });
}
