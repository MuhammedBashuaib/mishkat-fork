import 'package:equatable/equatable.dart';

class TasbihDhikr extends Equatable {
  const TasbihDhikr({
    required this.id,
    required this.text,
    required this.suggestedTarget,
  });

  final String id;
  final String text;
  final int suggestedTarget;

  @override
  List<Object?> get props => [id, text, suggestedTarget];
}

const tasbihDhikrOptions = <TasbihDhikr>[
  TasbihDhikr(id: 'subhan_allah', text: 'سبحان الله', suggestedTarget: 33),
  TasbihDhikr(id: 'alhamdulillah', text: 'الحمد لله', suggestedTarget: 33),
  TasbihDhikr(id: 'allahu_akbar', text: 'الله أكبر', suggestedTarget: 33),
  TasbihDhikr(id: 'tahlil', text: 'لا إله إلا الله', suggestedTarget: 100),
  TasbihDhikr(
    id: 'hawqalah',
    text: 'لا حول ولا قوة إلا بالله',
    suggestedTarget: 100,
  ),
  TasbihDhikr(
    id: 'subhan_bihamdih',
    text: 'سبحان الله وبحمده',
    suggestedTarget: 100,
  ),
  TasbihDhikr(
    id: 'salawat',
    text: 'اللهم صلِّ وسلم على نبينا محمد',
    suggestedTarget: 100,
  ),
  TasbihDhikr(id: 'istighfar', text: 'أستغفر الله', suggestedTarget: 100),
];

const tasbihCustomDhikrId = 'custom';

class TasbihState extends Equatable {
  const TasbihState({
    this.count = 0,
    this.total = 0,
    this.todayTotal = 0,
    this.target = 33,
    this.dhikrId = 'subhan_allah',
    this.hapticsEnabled = true,
    this.completionSoundEnabled = true,
    this.customDhikrs = const [],
    this.sessionDate = '',
  });

  final int count;
  final int total;
  final int todayTotal;
  final int target;
  final String dhikrId;
  final bool hapticsEnabled;
  final bool completionSoundEnabled;
  final List<TasbihDhikr> customDhikrs;
  final String sessionDate;

  TasbihDhikr get dhikr {
    final custom = customDhikrs.where((item) => item.id == dhikrId).firstOrNull;
    if (custom != null) return custom;
    return tasbihDhikrOptions.firstWhere(
      (item) => item.id == dhikrId,
      orElse: () => tasbihDhikrOptions.first,
    );
  }

  bool get completed => count >= target;
  int get remaining => (target - count).clamp(0, target);
  int get rounds => target == 0 ? 0 : count ~/ target;
  double get progress => target == 0 ? 0 : (count / target).clamp(0, 1);

  TasbihState copyWith({
    int? count,
    int? total,
    int? todayTotal,
    int? target,
    String? dhikrId,
    bool? hapticsEnabled,
    bool? completionSoundEnabled,
    List<TasbihDhikr>? customDhikrs,
    String? sessionDate,
  }) => TasbihState(
    count: count ?? this.count,
    total: total ?? this.total,
    todayTotal: todayTotal ?? this.todayTotal,
    target: target ?? this.target,
    dhikrId: dhikrId ?? this.dhikrId,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    completionSoundEnabled:
        completionSoundEnabled ?? this.completionSoundEnabled,
    customDhikrs: customDhikrs ?? this.customDhikrs,
    sessionDate: sessionDate ?? this.sessionDate,
  );

  @override
  List<Object?> get props => [
    count,
    total,
    todayTotal,
    target,
    dhikrId,
    hapticsEnabled,
    completionSoundEnabled,
    customDhikrs,
    sessionDate,
  ];
}
