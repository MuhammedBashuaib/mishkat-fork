import '../constants/app_constants.dart';

/// Complete recordings, separate from the reader's verse-by-verse sources.
///
/// Hafs recordings verified against https://mp3quran.net/api/v3/reciters
/// and https://cdn.islamic.network/quran/info/by-surah/info.json.
class QuranSurahAudioUrlBuilder {
  const QuranSurahAudioUrlBuilder._();

  static const _mp3Quran = 'https://cdn.mp3quran.net/audio/';
  static const _paths = <String, String>{
    'ar.alafasy': 'mishary-alafasy/r1',
    'ar.abdulbasitmurattal': 'abdulbasit-abdulsamad/r3',
    'ar.abdurrahmaansudais': 'abdulrahman-sudais/r1',
    'ar.mahermuaiqly': 'maher-muaiqly/r1',
    'ar.husary': 'mahmoud-husary/r1',
    'ar.minshawi': 'muhammad-minshawi/r1',
    'ar.saoodshuraym': 'saud-shuraim/r1',
    'ar.hudhaify': 'ali-hudhaifi/r1',
    'ar.ahmedajamy': 'ahmad-ajmi/r1',
    'ar.muhammadayyoub': 'muhammad-ayyub/r1',
    'ar.shaatree': 'abubakr-shatri/r1',
    'ar.hanirifai': 'hani-rifai/r1',
    'everyayah.abdullah-juhany': 'abdullah-juhani/r1',
    'everyayah.nasser-alqatami': 'nasser-qatami/r1',
    'everyayah.yasser-aldosari': 'yasser-dosari/r1',
    'qul.bandar-baleela': 'bandar-baleela/r1',
    'ar.abdullahbasfar': 'abdullah-basfar/r1',
    'ar.abdulsamad': 'abdulbasit-abdulsamad/r1',
    'ar.husarymujawwad': 'mahmoud-husary/r2',
    'ar.ibrahimakhbar': 'ibrahim-akhdar/r1',
    'ar.muhammadjibreel': 'muhammad-jibreel/r1',
    'everyayah.saad-alghamdi': 'saad-ghamdi/r1',
    'everyayah.fares-abbad': 'fares-abbad/r1',
    'everyayah.abdullah-matroud': 'abdullah-matrood/r1',
    'everyayah.salah-albudair': 'salah-budair/r1',
    'everyayah.salah-bukhatir': 'salah-bukhatir/r1',
  };

  static String buildUrl({required String reciter, required int surah}) {
    RangeError.checkValueInInterval(surah, 1, 114, 'surah');
    final id = AppConstants.findReciter(reciter).id;
    final number = surah.toString().padLeft(3, '0');
    if (id == 'ar.aymanswoaid') {
      return 'https://server15.mp3quran.net/a-rushdi/'
          'Almusshaf-Al-Mo-lim/$number.mp3';
    }
    if (id == 'ar.parhizgar') {
      return 'https://cdn.islamic.network/quran/audio-surah/'
          '128/ar.shahriarparhizgar/$surah.mp3';
    }
    final path = _paths[id];
    if (path == null) {
      throw StateError('No complete Surah recording is configured for $id.');
    }
    return '$_mp3Quran$path/$number.mp3';
  }
}

/// Quran.com's educational pronunciation audio, independent of the reciter.
/// https://api-docs.quran.com/docs/sdk/javascript/verses/#word-audio-paths
class QuranWordAudioUrlBuilder {
  const QuranWordAudioUrlBuilder._();

  static String buildUrl({
    required int surah,
    required int ayah,
    required int word,
  }) {
    RangeError.checkValueInInterval(surah, 1, 114, 'surah');
    RangeError.checkValueInInterval(
      ayah,
      1,
      QuranAyahIndex.ayahsPerSurah[surah - 1],
      'ayah',
    );
    RangeError.checkValueInInterval(word, 1, 999, 'word');
    final address = [
      surah,
      ayah,
      word,
    ].map((value) => value.toString().padLeft(3, '0')).join('_');
    return 'https://audio.qurancdn.com/wbw/$address.mp3';
  }
}
