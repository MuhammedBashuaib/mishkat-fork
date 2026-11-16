import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy personal cards become separate duas without changing daily progress', () async {
    final storage = _MemoryStorage();
    await storage.writeMap('adhkar', {
      'schemaVersion': 3,
      'dailyDate': _today(),
      'custom': [
        {'title': 'للوالدين', 'text': 'رب اغفر لي ولوالدي', 'count': 3},
        {'title': '', 'text': 'اللهم اهدني', 'count': 2},
      ],
      'progress': {
        '0': {'0': 2, '1': 1},
        '1': {'1': 3, '2': 2, '19': 40},
        '133': {'3': 1},
        '27': {'0': 2},
      },
      'countTargets': {
        '1': {'19': 100},
      },
    });
    final cubit = AdhkarCubit(AdhkarRepository(), storage);
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.customDuas.map((dua) => dua.name), [
      'للوالدين',
      'دعاء 2',
    ]);
    expect(cubit.state.customDuas.map((dua) => dua.id), [-1, -2]);
    expect(cubit.state.customDuas.every((dua) => dua.custom), isTrue);
    expect(
      cubit.state.customDuas.every((dua) => dua.items.length == 1),
      isTrue,
    );
    expect(cubit.state.progress, {
      -1: {0: 2},
      -2: {0: 1},
      1: {1: 3, 2: 2, 19: 40},
      133: {3: 1},
      27: {0: 2},
    });
    expect(cubit.state.countTargets, {
      1: {19: 100},
    });
    expect(storage.readMap('adhkar').containsKey('custom'), isFalse);
    final beforeReload = cubit.state;
    await cubit.load();
    expect(cubit.state, beforeReload);
    cubit.select(-1);
    expect(cubit.state.selected!.name, 'للوالدين');
    expect(cubit.state.selected!.items.single.text, 'رب اغفر لي ولوالدي');
  });

  test('cards, edits, resets and deletion stay within their own dua', () async {
    final storage = _MemoryStorage();
    final cubit = AdhkarCubit(AdhkarRepository(), storage);
    addTearDown(cubit.close);
    await cubit.load();
    final first = await cubit.saveCustom(
      title: 'الأول',
      text: 'الحمد لله',
      count: 3,
    );
    final second = await cubit.saveCustom(
      title: 'الثاني',
      text: 'سبحان الله',
      count: 2,
    );
    await cubit.saveCustom(
      duaId: first,
      title: 'بطاقة ثانية',
      text: 'الله أكبر',
      count: 3,
    );
    await cubit.increment(first, 0);
    await cubit.increment(first, 1);
    await cubit.increment(first, 1);
    await cubit.increment(second, 0);
    await cubit.increment(1, 0);
    await cubit.renameCustomDua(first, 'ورد خاص');
    expect(cubit.state.categoryById(first)!.name, 'ورد خاص');
    expect(cubit.countFor(first, 0), 1);
    cubit.search('ورد خاص');
    expect(cubit.filteredCategories().map((category) => category.id), [0]);

    await cubit.saveCustom(
      duaId: first,
      index: 0,
      title: 'عنوان جديد',
      text: 'الحمد لله',
      count: 5,
    );
    expect(cubit.countFor(first, 0), 1);
    cubit.search('عنوان جديد');
    expect(cubit.filteredCategories().map((category) => category.id), [0]);
    await cubit.saveCustom(
      duaId: first,
      index: 0,
      title: 'دعاء',
      text: 'اللهم اغفر لي',
      count: 3,
    );
    expect(cubit.countFor(first, 0), 0);
    expect(cubit.countFor(first, 1), 2);
    expect(cubit.countFor(second, 0), 1);
    expect(cubit.countFor(1, 0), 1);

    await cubit.deleteCustom(0, duaId: first);
    expect(cubit.state.categoryById(first)!.items.single.text, 'الله أكبر');
    expect(cubit.countFor(first, 0), 2);
    expect(cubit.state.progress[first]!.containsKey(1), isFalse);
    await cubit.resetCategory(first);
    expect(cubit.countFor(first, 0), 0);
    expect(cubit.countFor(second, 0), 1);
    expect(cubit.countFor(1, 0), 1);
    await cubit.deleteCustom(0, duaId: first);
    expect(cubit.state.categoryById(first)!.items, isEmpty);
    await cubit.saveCustom(
      duaId: first,
      title: '',
      text: 'بطاقة جديدة',
      count: 3,
    );
    expect(cubit.countFor(first, 0), 0);
    final beforeReload = cubit.state;
    await cubit.load();
    expect(cubit.state, beforeReload);
  });

  test('deleted dua IDs are never reused, including after reload', () async {
    final storage = _MemoryStorage();
    final cubit = AdhkarCubit(AdhkarRepository(), storage);
    addTearDown(cubit.close);
    await cubit.load();
    final ids = await Future.wait([
      cubit.saveCustom(title: 'الأول', text: 'الأول', count: 3),
      cubit.saveCustom(title: 'الثاني', text: 'الثاني', count: 3),
    ]);
    expect(ids.toSet(), hasLength(2));
    await cubit.increment(ids.last, 0);
    cubit.select(ids.last);
    await cubit.deleteCustomDua(ids.last);
    expect(cubit.state.selectedId, 0);
    expect(cubit.state.progress.containsKey(ids.last), isFalse);
    await cubit.load();
    final next = await cubit.saveCustom(title: 'جديد', text: 'جديد', count: 3);
    expect(next, lessThan(ids.last));
    expect(cubit.countFor(next, 0), 0);
    expect(cubit.state.categoryById(ids.first)!.items.single.text, 'الأول');
  });

  test('a daily reset preserves personal cards and their counters', () async {
    final storage = _MemoryStorage();
    final cubit = AdhkarCubit(AdhkarRepository(), storage);
    addTearDown(cubit.close);
    await cubit.load();
    final id = await cubit.saveCustom(
      title: 'دعائي',
      text: 'اللهم اهدني',
      count: 3,
    );
    await cubit.increment(id, 0);
    await cubit.increment(1, 0);
    await cubit.increment(133, 0);
    final oldDay = storage.readMap('adhkar')..['dailyDate'] = '2000-01-01';
    await storage.writeMap('adhkar', oldDay);
    await cubit.load();
    expect(cubit.countFor(id, 0), 1);
    expect(cubit.state.categoryById(id)!.name, 'دعائي');
    expect(cubit.countFor(1, 0), 0);
    expect(cubit.countFor(133, 0), 0);
  });

  test(
    'failed custom writes preserve live and stored data and allow retry',
    () async {
      final storage = _MemoryStorage();
      final cubit = AdhkarCubit(AdhkarRepository(), storage);
      addTearDown(cubit.close);
      await cubit.load();
      final id = await cubit.saveCustom(
        title: 'دعائي',
        text: 'اللهم اهدني',
        count: 3,
      );
      await cubit.increment(id, 0);
      final before = cubit.state;
      final savedBefore = storage.readMap('adhkar');
      storage.failWrites = true;
      await expectLater(
        cubit.renameCustomDua(id, 'عنوان لم يحفظ'),
        throwsStateError,
      );
      await expectLater(cubit.deleteCustomDua(id), throwsStateError);
      await expectLater(
        cubit.saveCustom(title: 'دعاء لم يحفظ', text: 'نص', count: 3),
        throwsStateError,
      );
      expect(cubit.state, before);
      expect(storage.readMap('adhkar'), savedBefore);
      storage.failWrites = false;
      await cubit.renameCustomDua(id, 'عنوان محفوظ');
      expect(cubit.state.categoryById(id)!.name, 'عنوان محفوظ');
    },
  );

  test('counting during a delayed custom save preserves both live and stored changes', () async {
    final storage = _MemoryStorage();
    final cubit = AdhkarCubit(AdhkarRepository(), storage);
    addTearDown(cubit.close);
    await cubit.load();
    final existing = await cubit.saveCustom(
      title: 'دعاء موجود',
      text: 'اللهم اهدني',
      count: 3,
    );
    await cubit.increment(133, 0);
    storage.pauseWriteReturn = Completer<void>();
    storage.writeStarted = Completer<void>();
    final saving = cubit.saveCustom(
      title: 'دعاء جديد',
      text: 'رب اغفر لي ولوالدي',
      count: 3,
    );
    await storage.writeStarted!.future;
    final counting = cubit.increment(1, 0);
    final personalCounting = cubit.increment(existing, 0);
    final resetting = cubit.resetCategory(133);
    final targeting = cubit.setCountTarget(1, 19, 100);
    cubit.select(1);
    cubit.search('الوالدين');
    expect(cubit.countFor(1, 0), 1);
    expect(cubit.countFor(existing, 0), 1);
    storage.pauseWriteReturn!.complete();
    final created = await saving;
    await Future.wait([counting, personalCounting, resetting, targeting]);
    expect(cubit.state.categoryById(created)!.name, 'دعاء جديد');
    expect(cubit.countFor(1, 0), 1);
    expect(cubit.countFor(existing, 0), 1);
    expect(cubit.countFor(133, 0), 0);
    expect(cubit.state.selectedId, 1);
    expect(cubit.state.query, 'الوالدين');
    expect(cubit.state.selected!.items[19].count, 100);
    final beforeReload = cubit.state;
    await cubit.load();
    expect(cubit.state, beforeReload);
  });

  test('a delayed custom save cannot restore state after data reset', () async {
    final storage = _MemoryStorage();
    final cubit = AdhkarCubit(AdhkarRepository(), storage);
    addTearDown(cubit.close);
    await cubit.load();
    storage.pauseWriteReturn = Completer<void>();
    storage.writeStarted = Completer<void>();
    final saving = cubit.saveCustom(
      title: 'دعاء قديم',
      text: 'اللهم اهدني',
      count: 3,
    );
    await storage.writeStarted!.future;
    cubit.invalidatePendingOperations();
    await storage.clear();
    cubit.resetLocalData();
    storage.pauseWriteReturn!.complete();
    await saving;
    expect(cubit.state.customDuas, isEmpty);
    expect(storage.readMap('adhkar'), isEmpty);
  });
}

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

class _MemoryStorage extends LocalStorageService {
  final _maps = <String, Map<String, dynamic>>{};
  bool failWrites = false;
  Completer<void>? pauseWriteReturn;
  Completer<void>? writeStarted;

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_maps[key] ?? const {});

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    if (failWrites) throw StateError('disk unavailable');
    _maps[key] = value;
    if (writeStarted?.isCompleted == false) writeStarted!.complete();
    await pauseWriteReturn?.future;
  }

  @override
  Future<void> clear() async => _maps.clear();
}
