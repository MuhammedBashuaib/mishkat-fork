import '../../features/khatma/data/models/khatma_plan.dart';
import '../../features/tasbih/presentation/cubit/tasbih_state.dart';

String widgetDigits(Object value) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return value.toString().replaceAllMapped(
    RegExp('[0-9]'),
    (match) => digits[int.parse(match[0]!)],
  );
}

/// Shared copy for the gallery and the native Home Screen widgets.
class WirdWidgetContent {
  WirdWidgetContent(KhatmaPlan? plan)
    : name = plan == null ? 'رحلتك مع القرآن' : _compact(plan.name),
      pages = switch (plan?.status) {
        null => 'ابدأ ختمتك الأولى',
        KhatmaStatus.completed => 'أتممت الختمة',
        _ =>
          'صفحة ${widgetDigits(plan!.resumePage.clamp(plan.nextPage, plan.todayEnd))} – ${widgetDigits(plan.todayEnd)}',
      },
      detail = switch (plan?.status) {
        null => 'حدّد خطتك ليظهر وردك هنا',
        KhatmaStatus.paused => 'الخطة متوقفة مؤقتًا',
        KhatmaStatus.completed => 'تقبّل الله قراءتك',
        _ =>
          '${widgetDigits(plan!.todayEnd - plan.resumePage.clamp(plan.nextPage, plan.todayEnd) + 1)} صفحة في وردك الحالي',
      },
      progress = plan?.progress ?? 0,
      completedPages = plan?.completedPages.clamp(0, plan.totalPages) ?? 0,
      remainingPages = plan?.remainingPages.clamp(0, plan.totalPages) ?? 0,
      progressLabel = plan == null
          ? 'خطوة صغيرة كل يوم'
          : '${widgetDigits((plan.progress * 100).round())}٪ من الختمة',
      action = switch (plan?.status) {
        null => 'اضغط لإنشاء خطة',
        KhatmaStatus.paused => 'اضغط لاستئناف الخطة',
        KhatmaStatus.completed => 'اضغط لرحلة جديدة',
        _ => 'اضغط لمتابعة القراءة',
      };

  final String name;
  final String pages;
  final String detail;
  final double progress;
  final int completedPages;
  final int remainingPages;
  String get completedLabel => 'أنجزت ${widgetDigits(completedPages)} صفحة';
  String get remainingLabel => 'باقي ${widgetDigits(remainingPages)} صفحة';
  final String progressLabel;
  final String action;

  static String _compact(String value) =>
      value.length > 32 ? '${value.substring(0, 31)}…' : value;
}

class TasbihWidgetContent {
  TasbihWidgetContent(TasbihState state, {DateTime? now})
    : dhikr = state.dhikr.text.length > 38
          ? '${state.dhikr.text.substring(0, 37).trimRight()}…'
          : state.dhikr.text,
      count = widgetDigits(state.count),
      target = 'الهدف ${widgetDigits(state.target)}',
      today =
          'اليوم ${widgetDigits(_todayCount(state, now ?? DateTime.now()))} تسبيحة',
      progress = state.progress,
      action = state.completed
          ? 'أتممت هدفك · اضغط للمتابعة'
          : 'اضغط لفتح المسبحة';

  final String dhikr;
  final String count;
  final String target;
  final String today;
  final double progress;
  final String action;

  static int _todayCount(TasbihState state, DateTime now) {
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return state.sessionDate == date ? state.todayTotal : 0;
  }
}
