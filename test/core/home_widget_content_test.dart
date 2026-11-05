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
      expect(content.completedPages, 41);
      expect(content.remainingPages, 563);
      expect(content.completedLabel, 'أنجزت ٤١ صفحة');
      expect(content.remainingLabel, 'باقي ٥٦٣ صفحة');
      // The saved reading position is a bookmark, not completed pages.
      expect(content.progress, closeTo(41 / 604, 0.0001));
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
    expect(completed.progress, 1);
    expect(completed.remainingPages, 0);
    expect(WirdWidgetContent(null).progress, 0);
    expect(WirdWidgetContent(null).completedPages, 0);
    expect(WirdWidgetContent(null).remainingPages, 0);
  });

  test('a plan starting later uses only the pages in that plan', () {
    final partial = KhatmaPlan(
      id: 'partial',
      name: 'ختمة',
      durationDays: 10,
      dailyPages: 10,
      startDate: DateTime(2026),
      startPage: 505,
      progressPage: 554,
      status: KhatmaStatus.paused,
      createdAt: DateTime(2026),
    );
    final content = WirdWidgetContent(partial);
    expect(content.completedPages, 50);
    expect(content.remainingPages, 50);
    expect(content.progress, 0.5);
    expect(content.detail, 'الخطة متوقفة مؤقتًا');
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
