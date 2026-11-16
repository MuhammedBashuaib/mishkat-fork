import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/local_storage_service.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/adhkar/presentation/cubit/adhkar_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'splitting saved surahs preserves independent daily progress on reload',
    () async {
      final storage = _MemoryStorage();
      await storage.writeMap('adhkar', {
        'schemaVersion': 2,
        'dailyDate': _today(),
        'progress': {
          '1': {'0': 1, '1': 2, '2': 1, '17': 6, '21': 1},
          '133': {'1': 1, '2': 1, '17': 3, '20': 2},
          '2': {'1': 2},
        },
        'countTargets': {
          '1': {'17': 100},
          '133': {'17': 10},
        },
      });
      final cubit = AdhkarCubit(AdhkarRepository(), storage);
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.progress, {
        1: {0: 1, 1: 2, 2: 2, 3: 2, 4: 1, 19: 6, 23: 1},
        133: {1: 1, 2: 1, 3: 1, 4: 1, 19: 3, 22: 2},
        2: {1: 2},
      });
      expect(cubit.state.countTargets, {
        1: {19: 100},
        133: {19: 10},
      });
      expect(storage.readMap('adhkar')['schemaVersion'], 3);

      await cubit.increment(1, 2);
      await cubit.reset(133, 3);
      expect([for (var i = 1; i <= 3; i++) cubit.countFor(1, i)], [2, 3, 2]);
      expect([for (var i = 1; i <= 3; i++) cubit.countFor(133, i)], [1, 1, 0]);

      final progressBeforeReload = cubit.state.progress;
      final targetsBeforeReload = cubit.state.countTargets;
      await cubit.load();
      expect(cubit.state.progress, progressBeforeReload);
      expect(cubit.state.countTargets, targetsBeforeReload);
    },
  );

  test(
    'daily reset keeps migrated count targets and other categories',
    () async {
      final storage = _MemoryStorage();
      await storage.writeMap('adhkar', {
        'schemaVersion': 2,
        'dailyDate': '2000-01-01',
        'progress': {
          '1': {'1': 2, '17': 45},
          '133': {'1': 3, '17': 7},
          '2': {'1': 2},
        },
        'countTargets': {
          '1': {'17': 100},
          '133': {'17': 10},
        },
      });
      final cubit = AdhkarCubit(AdhkarRepository(), storage);
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.progress, {
        2: {1: 2},
      });
      cubit.select(1);
      expect(cubit.state.selected!.items[19].count, 100);
      cubit.select(133);
      expect(cubit.state.selected!.items[19].count, 10);
      expect(storage.readMap('adhkar')['countTargets'], {
        '1': {'19': 100},
        '133': {'19': 10},
      });
    },
  );

  test(
    'completed combined surahs stay completed in both daily wirds',
    () async {
      final storage = _MemoryStorage();
      await storage.writeMap('adhkar', {
        'schemaVersion': 2,
        'dailyDate': _today(),
        'progress': {
          '1': {'1': 3},
          '133': {'1': 3},
        },
      });
      final cubit = AdhkarCubit(AdhkarRepository(), storage);
      addTearDown(cubit.close);
      await cubit.load();

      for (final categoryId in [1, 133]) {
        cubit.select(categoryId);
        for (var index = 1; index <= 3; index++) {
          expect(cubit.state.selected!.items[index].count, 3);
          expect(cubit.countFor(categoryId, index), 3);
          await cubit.increment(categoryId, index);
          expect(cubit.countFor(categoryId, index), 3);
        }
        expect(cubit.countFor(categoryId, 4), 0);
      }
    },
  );
}

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

class _MemoryStorage extends LocalStorageService {
  final _maps = <String, Map<String, dynamic>>{};

  @override
  Map<String, dynamic> readMap(String key) =>
      Map<String, dynamic>.from(_maps[key] ?? const {});

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _maps[key] = value;
  }
}
