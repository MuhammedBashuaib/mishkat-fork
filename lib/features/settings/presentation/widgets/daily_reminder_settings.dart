import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_formatters.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/reminder_preferences.dart';
import '../cubit/settings_cubit.dart';

class DailyReminderSettings extends StatelessWidget {
  const DailyReminderSettings({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final preferences = settings.reminders;
    void update(ReminderPreferences Function(ReminderPreferences) change) {
      final cubit = context.read<SettingsCubit>();
      cubit.setReminders(change(cubit.state.settings.reminders));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!settings.notificationsEnabled)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('اختر تذكيراتك، ثم فعّل «نظام التنبيهات» لتصلك.'),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('أذكار الصباح والمساء والنوم'),
          subtitle: const Text(
            'بحسب مواقيت مدينتك، أو أوقات يومية عند عدم تحديد الموقع',
          ),
          value: settings.adhkarNotifications,
          onChanged: context.read<SettingsCubit>().setAdhkarNotifications,
        ),
        if (settings.adhkarNotifications)
          _ReminderTimeTile(
            title: 'تذكير أذكار النوم',
            minute: preferences.sleepMinute,
            bedtime: true,
            onChanged: (value) => update((p) => p.copyWith(sleepMinute: value)),
          ),
        const Divider(),
        SwitchListTile(
          key: const ValueKey('friday-reminders-toggle'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.wb_sunny_outlined),
          title: const Text('تذكيرات يوم الجمعة'),
          subtitle: const Text(
            'الكهف صباحًا وظهرًا وبعد المغرب، و٣ تذكيرات للصلاة على النبي ﷺ، و٣ للدعاء قبل الغروب',
          ),
          value: preferences.fridayEnabled,
          onChanged: (value) => update((p) => p.copyWith(fridayEnabled: value)),
        ),
        if (preferences.fridayEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              settings.hasLocation
                  ? 'تذكير الدعاء بعد العصر، وآخر قبل أذان المغرب بنصف ساعة بحسب مواقيت مدينتك. تُحدّث المواعيد عند فتح التطبيق.'
                  : 'حدّد مدينتك لربط التذكيرات بالعصر والمغرب. حتى ذلك الحين تصلك تذكيرات الجمعة في أوقات عامة، دون تقدير وقت الغروب.',
            ),
          ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.volunteer_activism_outlined),
          title: const Text('التذكير بالصدقة'),
          subtitle: const Text('رسالتان لطيفتان يوميًا، صباحًا ومساءً'),
          value: preferences.charityEnabled,
          onChanged: (value) =>
              update((p) => p.copyWith(charityEnabled: value)),
        ),
        if (preferences.charityEnabled) ...[
          _ReminderTimeTile(
            title: 'موعد الصدقة صباحًا',
            minute: preferences.charityMorningMinute,
            onChanged: (value) =>
                update((p) => p.copyWith(charityMorningMinute: value)),
          ),
          _ReminderTimeTile(
            title: 'موعد الصدقة مساءً',
            minute: preferences.charityEveningMinute,
            onChanged: (value) =>
                update((p) => p.copyWith(charityEveningMinute: value)),
          ),
        ],
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: const Text('ذكر الله خلال اليوم'),
          subtitle: const Text(
            'تسبيح واستغفار وصلاة على النبي؛ افتح الإشعار لتبدأ الذكر في المسبحة',
          ),
          value: preferences.dhikrEnabled,
          onChanged: (value) => update((p) => p.copyWith(dhikrEnabled: value)),
        ),
        if (preferences.dhikrEnabled)
          DropdownButtonFormField<int>(
            isExpanded: true,
            key: ValueKey('dhikr-frequency-${preferences.dhikrPerDay}'),
            initialValue: preferences.dhikrPerDay,
            decoration: const InputDecoration(labelText: 'عدد تذكيرات الذكر'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('خفيف — مرة يوميًا')),
              DropdownMenuItem(value: 3, child: Text('متوازن — 3 مرات يوميًا')),
              DropdownMenuItem(value: 5, child: Text('متكرر — 5 مرات يوميًا')),
            ],
            onChanged: (value) {
              if (value != null) update((p) => p.copyWith(dhikrPerDay: value));
            },
          ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.menu_book_outlined),
          title: const Text('التذكير بالورد اليومي'),
          subtitle: const Text(
            'يفتح موضع تلاوتك. إذا حددت تذكيرًا لختمتك يُستخدم موعدها',
          ),
          value: preferences.dailyWirdEnabled,
          onChanged: (value) =>
              update((p) => p.copyWith(dailyWirdEnabled: value)),
        ),
        if (preferences.dailyWirdEnabled)
          _ReminderTimeTile(
            title: 'موعد الورد اليومي',
            minute: preferences.dailyWirdMinute,
            onChanged: (value) =>
                update((p) => p.copyWith(dailyWirdMinute: value)),
          ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('صوت تذكيرات الخير والأذكار'),
          subtitle: const Text(
            'التذكيرات هادئة افتراضيًا؛ صوت الأذان له إعداداته المستقلة',
          ),
          value: preferences.sound,
          onChanged: (value) => update((p) => p.copyWith(sound: value)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'نباعد تذكيرات الصدقة والذكر والورد عن الصلاة وعن بعضها، وقد تتحرك قليلًا عن موعدك المختار. '
            'تصل بين ٨ صباحًا و١٠ ليلًا. أذكار الصباح والنوم والأذان تحتفظ بأوقاتها الخاصة.',
          ),
        ),
      ],
    );
  }
}

class _ReminderTimeTile extends StatelessWidget {
  const _ReminderTimeTile({
    required this.title,
    required this.minute,
    required this.onChanged,
    this.bedtime = false,
  });
  final String title;
  final int minute;
  final ValueChanged<int> onChanged;
  final bool bedtime;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.schedule_outlined, size: 20),
      ],
    ),
    onTap: () async {
      final selected = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        helpText: title,
      );
      if (selected == null || !context.mounted) return;
      final value = selected.hour * 60 + selected.minute;
      if (!bedtime && (value < 8 * 60 || value >= 22 * 60)) {
        context.showMessage('اختر وقتًا بين ٨ صباحًا وقبل ١٠ ليلًا.');
        return;
      }
      onChanged(value);
    },
  );
}
