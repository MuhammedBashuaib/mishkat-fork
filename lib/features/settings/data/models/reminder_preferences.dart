import 'package:equatable/equatable.dart';

/// Optional good-deed reminders, independent of prayer and adhan preferences.
class ReminderPreferences extends Equatable {
  const ReminderPreferences({
    this.charityEnabled = true,
    this.dhikrEnabled = true,
    this.dailyWirdEnabled = true,
    this.fridayEnabled = true,
    this.dhikrPerDay = 3,
    this.sound = false,
    this.charityMorningMinute = 9 * 60,
    this.charityEveningMinute = 18 * 60 + 30,
    this.dailyWirdMinute = 20 * 60 + 30,
    this.sleepMinute = 22 * 60,
  });

  final bool charityEnabled;
  final bool dhikrEnabled;
  final bool dailyWirdEnabled;
  final bool fridayEnabled;
  final int dhikrPerDay;
  final bool sound;
  final int charityMorningMinute;
  final int charityEveningMinute;
  final int dailyWirdMinute;
  final int sleepMinute;

  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    int minute(String key, int fallback, {bool bedtime = false}) {
      final raw = json[key];
      final value = raw is num ? raw.toInt() : null;
      final lower = bedtime ? 0 : 8 * 60;
      final upper = bedtime ? 1439 : 22 * 60 - 1;
      return value != null && value >= lower && value <= upper
          ? value
          : fallback;
    }

    final rawFrequency = json['dhikrPerDay'];
    final frequency = rawFrequency is num ? rawFrequency.toInt() : null;
    return ReminderPreferences(
      charityEnabled: json['charityEnabled'] != false,
      dhikrEnabled: json['dhikrEnabled'] != false,
      dailyWirdEnabled: json['dailyWirdEnabled'] != false,
      fridayEnabled: json['fridayEnabled'] != false,
      dhikrPerDay: [1, 3, 5].contains(frequency) ? frequency! : 3,
      sound: json['sound'] == true,
      charityMorningMinute: minute('charityMorningMinute', 9 * 60),
      charityEveningMinute: minute('charityEveningMinute', 18 * 60 + 30),
      dailyWirdMinute: minute('dailyWirdMinute', 20 * 60 + 30),
      sleepMinute: minute('sleepMinute', 22 * 60, bedtime: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'charityEnabled': charityEnabled,
    'dhikrEnabled': dhikrEnabled,
    'dailyWirdEnabled': dailyWirdEnabled,
    'fridayEnabled': fridayEnabled,
    'dhikrPerDay': dhikrPerDay,
    'sound': sound,
    'charityMorningMinute': charityMorningMinute,
    'charityEveningMinute': charityEveningMinute,
    'dailyWirdMinute': dailyWirdMinute,
    'sleepMinute': sleepMinute,
  };

  ReminderPreferences copyWith({
    bool? charityEnabled,
    bool? dhikrEnabled,
    bool? dailyWirdEnabled,
    bool? fridayEnabled,
    int? dhikrPerDay,
    bool? sound,
    int? charityMorningMinute,
    int? charityEveningMinute,
    int? dailyWirdMinute,
    int? sleepMinute,
  }) => ReminderPreferences.fromJson({
    'charityEnabled': charityEnabled ?? this.charityEnabled,
    'dhikrEnabled': dhikrEnabled ?? this.dhikrEnabled,
    'dailyWirdEnabled': dailyWirdEnabled ?? this.dailyWirdEnabled,
    'fridayEnabled': fridayEnabled ?? this.fridayEnabled,
    'dhikrPerDay': dhikrPerDay ?? this.dhikrPerDay,
    'sound': sound ?? this.sound,
    'charityMorningMinute': charityMorningMinute ?? this.charityMorningMinute,
    'charityEveningMinute': charityEveningMinute ?? this.charityEveningMinute,
    'dailyWirdMinute': dailyWirdMinute ?? this.dailyWirdMinute,
    'sleepMinute': sleepMinute ?? this.sleepMinute,
  });

  @override
  List<Object?> get props => [
    charityEnabled,
    dhikrEnabled,
    dailyWirdEnabled,
    fridayEnabled,
    dhikrPerDay,
    sound,
    charityMorningMinute,
    charityEveningMinute,
    dailyWirdMinute,
    sleepMinute,
  ];
}
