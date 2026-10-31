import '../../../tasbih/presentation/cubit/tasbih_state.dart';

/// Recommendations use the device's local time. Each has one explicit destination.
enum HomeDhikrMoment {
  morning(categoryId: 1),
  evening(categoryId: 133),
  sleep(categoryId: 2),
  tasbih(dhikrId: 'subhan_allah'),
  salawat(dhikrId: 'salawat'),
  istighfar(dhikrId: 'istighfar');

  const HomeDhikrMoment({this.categoryId, this.dhikrId});

  final int? categoryId;
  final String? dhikrId;

  static HomeDhikrMoment forTime(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 12) return morning;
    if (hour >= 16 && hour < 22) return evening;
    if (hour >= 22 || hour < 5) return sleep;
    return switch ((hour - 12) % 3) {
      0 => tasbih,
      1 => salawat,
      _ => istighfar,
    };
  }

  TasbihDhikr? get dhikr =>
      tasbihDhikrOptions.where((item) => item.id == dhikrId).firstOrNull;

  String get title => switch (this) {
    morning => 'أذكار الصباح',
    evening => 'أذكار المساء',
    sleep => 'أذكار النوم',
    _ => dhikr!.text,
  };

  String get subtitle => switch (this) {
    morning => 'ابدأ يومك بذكر هادئ',
    evening => 'اختم يومك بالسكينة',
    sleep => 'حصّن ليلتك قبل النوم',
    _ => 'اضغط لذكر الله في المسبحة',
  };
}
