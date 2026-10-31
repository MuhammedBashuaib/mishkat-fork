import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/adhkar/data/repositories/adhkar_repository.dart';
import 'package:mishkat_app/features/home/presentation/models/home_dhikr_moment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recommendations switch at the local time boundaries', () {
    const cases = [
      (0, 0, HomeDhikrMoment.sleep),
      (4, 59, HomeDhikrMoment.sleep),
      (5, 0, HomeDhikrMoment.morning),
      (11, 59, HomeDhikrMoment.morning),
      (12, 0, HomeDhikrMoment.tasbih),
      (12, 59, HomeDhikrMoment.tasbih),
      (13, 0, HomeDhikrMoment.salawat),
      (14, 0, HomeDhikrMoment.istighfar),
      (15, 0, HomeDhikrMoment.tasbih),
      (15, 59, HomeDhikrMoment.tasbih),
      (16, 0, HomeDhikrMoment.evening),
      (21, 59, HomeDhikrMoment.evening),
      (22, 0, HomeDhikrMoment.sleep),
      (23, 59, HomeDhikrMoment.sleep),
    ];
    for (final (hour, minute, expected) in cases) {
      final now = DateTime(2026, 10, 31, hour, minute);
      expect(HomeDhikrMoment.forTime(now), expected, reason: '$now');
    }
  });

  test('every recommendation has exactly one valid destination', () {
    for (final moment in HomeDhikrMoment.values) {
      expect(moment.categoryId != null, moment.dhikrId == null);
      if (moment.dhikrId != null) {
        expect(moment.dhikr, isNotNull);
        expect(moment.title, moment.dhikr!.text);
      }
    }
  });

  test('timed recommendations match the actual bundled chapters', () async {
    final categories = await AdhkarRepository().load();
    for (final moment in [
      HomeDhikrMoment.morning,
      HomeDhikrMoment.evening,
      HomeDhikrMoment.sleep,
    ]) {
      final category = categories.singleWhere(
        (category) => category.id == moment.categoryId,
      );
      expect(category.name, moment.title);
      expect(category.items, isNotEmpty);
    }
  });
}
