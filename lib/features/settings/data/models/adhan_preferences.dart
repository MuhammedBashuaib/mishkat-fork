import 'package:equatable/equatable.dart';

enum AdhanPlaybackMode { full, short }

class AdhanVoice extends Equatable {
  const AdhanVoice({
    required this.id,
    required this.muezzin,
    required this.description,
  });

  final String id;
  final String muezzin;
  final String description;

  String soundName(AdhanPlaybackMode mode) =>
      mode == AdhanPlaybackMode.short ? '${id}_short' : id;

  static const voices = <AdhanVoice>[
    AdhanVoice(
      id: 'adhan1',
      muezzin: 'أحمد النفيس',
      description: 'أداء عربي هادئ وواضح',
    ),
    AdhanVoice(
      id: 'adhan2',
      muezzin: 'الحافظ مصطفى أوزجان',
      description: 'الأذان التركي التقليدي',
    ),
    AdhanVoice(
      id: 'adhan4',
      muezzin: 'مشاري راشد العفاسي',
      description: 'أذان دبي — قناة دبي ون',
    ),
  ];

  static AdhanVoice byId(String? id) =>
      voices.firstWhere((voice) => voice.id == id, orElse: () => voices.first);

  @override
  List<Object?> get props => [id, muezzin, description];
}
