import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppFormatters {
  const AppFormatters._();

  static const _weekdays = <String>[
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];
  static const _gregorianMonths = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  static const _hijriMonths = <String>[
    'محرم',
    'صفر',
    'ربيع الأول',
    'ربيع الآخر',
    'جمادى الأولى',
    'جمادى الآخرة',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذو القعدة',
    'ذو الحجة',
  ];

  static String time(DateTime? value) {
    if (value == null) return '—';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour < 12 ? 'ص' : 'م'}';
  }

  static String duration(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    final hours = safe.inHours.toString().padLeft(2, '0');
    final minutes = (safe.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String gregorianDate(DateTime date) =>
      '${date.day} ${_gregorianMonths[date.month - 1]} ${date.year}';

  static String hijriDate(DateTime source, {int offset = 0}) {
    final date = source.add(Duration(days: offset));
    final hijri = _toHijri(date);
    return '${_weekdays[date.weekday - 1]}، ${hijri.day} '
        '${_hijriMonths[hijri.month - 1]} ${hijri.year} هـ';
  }

  static String percent(double value) => '${(value * 100).round()}%';

  static String compactBytes(int bytes) {
    if (bytes < 1024) return '$bytes ب';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  static String normalizeArabic(String value) {
    return value
        .replaceAll(RegExp('[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
        .replaceAll('ـ', '')
        .replaceAll(
          RegExp('[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
          '',
        )
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ى', 'ي')
        .replaceAll('ی', 'ي')
        .replaceAll('ک', 'ك')
        .replaceAll('ة', 'ه')
        .replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
          final code = match[0]!.codeUnitAt(0);
          return '${code >= 0x06F0 ? code - 0x06F0 : code - 0x0660}';
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  static _HijriDate _toHijri(DateTime date) {
    var year = date.year;
    var month = date.month;
    if (month < 3) {
      year -= 1;
      month += 12;
    }
    final a = year ~/ 100;
    final b = 2 - a + a ~/ 4;
    final jd =
        (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        date.day +
        b -
        1524;
    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j =
        ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l =
        l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final hijriMonth = (24 * l) ~/ 709;
    final hijriDay = l - (709 * hijriMonth) ~/ 24;
    return _HijriDate(30 * n + j - 30, hijriMonth, hijriDay);
  }
}

class _HijriDate {
  const _HijriDate(this.year, this.month, this.day);
  final int year;
  final int month;
  final int day;
}

extension ContextMessages on BuildContext {
  void showMessage(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
