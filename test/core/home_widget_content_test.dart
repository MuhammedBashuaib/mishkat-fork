import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/home_widget_content.dart';
import 'package:mishkat_app/features/khatma/data/models/khatma_plan.dart';
import 'package:mishkat_app/features/tasbih/presentation/cubit/tasbih_state.dart';

KhatmaPlan plan({
  KhatmaStatus status = KhatmaStatus.active,
  int progress = 41,
  int resume = 45,
}) => KhatmaPlan(
  id: 'plan',
  name: 'ختمتي',
  durationDays: 30,
  dailyPages: 21,
  startDate: DateTime(2026, 10, 1),
  startPage: 1,
  progressPage: progress,
  lastReadPage: resume,
  currentWardEndPage: 62,
  status: status,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  test(
    'wird starts from the saved reading position within the current ward',
    () {
      final content = WirdWidgetContent(plan());
      expect(content.pages, 'صفحة ٤٥ – ٦٢');
      expect(content.detail, '١٨ صفحة في وردك الحالي');
      expect(content.progressLabel, '٧٪ من الختمة');
      expect(content.action, 'اضغط لمتابعة القراءة');
      expect(WirdWidgetContent(plan(resume: 90)).pages, 'صفحة ٦٢ – ٦٢');
    },
  );

  test('empty, paused and completed plans have useful actions', () {
    expect(WirdWidgetContent(null).action, 'اضغط لإنشاء خطة');
    expect(
      WirdWidgetContent(plan(status: KhatmaStatus.paused)).action,
      'اضغط لاستئناف الخطة',
    );
    final completed = WirdWidgetContent(
      plan(status: KhatmaStatus.completed, progress: 604),
    );
    expect(completed.pages, 'أتممت الختمة');
    expect(completed.progressLabel, '١٠٠٪ من الختمة');
  });

  test('tasbih preserves the session while daily total resets at midnight', () {
    const state = TasbihState(
      count: 40,
      target: 33,
      todayTotal: 90,
      sessionDate: '2026-10-31',
      dhikrId: 'alhamdulillah',
    );
    final today = TasbihWidgetContent(
      state,
      now: DateTime(2026, 10, 31, 23, 59),
    );
    final tomorrow = TasbihWidgetContent(state, now: DateTime(2026, 11, 1));
    expect(today.count, '٤٠');
    expect(today.dhikr, 'الحمد لله');
    expect(today.today, 'اليوم ٩٠ تسبيحة');
    expect(today.action, 'أتممت هدفك · اضغط للمتابعة');
    expect(tomorrow.count, today.count);
    expect(tomorrow.today, 'اليوم ٠ تسبيحة');
  });
}
