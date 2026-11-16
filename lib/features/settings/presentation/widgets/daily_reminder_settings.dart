import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/reminder_preferences.dart';
import '../cubit/settings_cubit.dart';

class DailyReminderSettings extends StatefulWidget {
  const DailyReminderSettings({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<DailyReminderSettings> createState() => _DailyReminderSettingsState();
}

class _DailyReminderSettingsState extends State<DailyReminderSettings> {
  String? _expanded;

  void _update(ReminderPreferences Function(ReminderPreferences) change) {
    final cubit = context.read<SettingsCubit>();
    cubit.setReminders(change(cubit.state.settings.reminders));
  }

  String _time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final preferences = settings.reminders;
    final colors = context.mishkat;
    final text = Theme.of(context).textTheme;
    final frequency = switch (preferences.dhikrPerDay) {
      1 => 'مرة يوميًا',
      5 => '٥ مرات يوميًا',
      _ => '٣ مرات يوميًا',
    };

    Widget section({
      required String id,
      required IconData icon,
      required String title,
      required String summary,
      required bool enabled,
      required ValueChanged<bool> onChanged,
      required List<Widget> details,
      Key? toggleKey,
    }) => _ReminderSection(
      id: id,
      icon: icon,
      title: title,
      summary: summary,
      enabled: enabled,
      expanded: _expanded == id,
      onTap: () => setState(() => _expanded = _expanded == id ? null : id),
      children: [
        SwitchListTile(
          key: toggleKey ?? ValueKey('$id-reminders-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('تفعيل التذكير'),
          value: enabled,
          onChanged: onChanged,
        ),
        if (enabled) ...details,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!settings.notificationsEnabled) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: MishkatRadius.brMd,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'اختر تذكيراتك، ثم فعّل «نظام التنبيهات» لتصلك.',
                    style: text.bodySmall?.copyWith(
                      color: colors.primary,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        MishkatCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              section(
                id: 'adhkar',
                icon: Icons.wb_twilight_rounded,
                title: 'أذكار اليوم والليلة',
                summary: 'الصباح والمساء والنوم',
                enabled: settings.adhkarNotifications,
                onChanged: context.read<SettingsCubit>().setAdhkarNotifications,
                details: [
                  const _ReminderNote(
                    'بحسب مواقيت مدينتك، أو أوقات يومية عند عدم تحديد الموقع.',
                  ),
                  _ReminderTimeTile(
                    title: 'تذكير أذكار النوم',
                    minute: preferences.sleepMinute,
                    bedtime: true,
                    onChanged: (value) =>
                        _update((p) => p.copyWith(sleepMinute: value)),
                  ),
                ],
              ),
              section(
                id: 'friday',
                icon: Icons.wb_sunny_outlined,
                title: 'تذكيرات الجمعة',
                summary: 'الكهف والصلاة على النبي والدعاء',
                enabled: preferences.fridayEnabled,
                onChanged: (value) =>
                    _update((p) => p.copyWith(fridayEnabled: value)),
                details: [
                  const _ReminderNote(
                    'الكهف صباحًا وظهرًا وبعد المغرب، و٣ تذكيرات للصلاة على النبي ﷺ، و٣ للدعاء قبل الغروب.',
                  ),
                  const SizedBox(height: 8),
                  _ReminderNote(
                    settings.hasLocation
                        ? 'تذكير الدعاء بعد العصر، وآخر قبل أذان المغرب بنصف ساعة بحسب مواقيت مدينتك. تُحدّث المواعيد عند فتح التطبيق.'
                        : 'حدّد مدينتك لربط التذكيرات بالعصر والمغرب. حتى ذلك الحين تصلك تذكيرات الجمعة في أوقات عامة، دون تقدير وقت الغروب.',
                  ),
                ],
              ),
              section(
                id: 'charity',
                icon: Icons.volunteer_activism_outlined,
                title: 'التذكير بالصدقة',
                summary: 'مرتان يوميًا · صباحًا ومساءً',
                enabled: preferences.charityEnabled,
                onChanged: (value) =>
                    _update((p) => p.copyWith(charityEnabled: value)),
                details: [
                  _ReminderTimeTile(
                    title: 'موعد الصدقة صباحًا',
                    minute: preferences.charityMorningMinute,
                    onChanged: (value) =>
                        _update((p) => p.copyWith(charityMorningMinute: value)),
                  ),
                  _ReminderTimeTile(
                    title: 'موعد الصدقة مساءً',
                    minute: preferences.charityEveningMinute,
                    onChanged: (value) =>
                        _update((p) => p.copyWith(charityEveningMinute: value)),
                  ),
                ],
              ),
              section(
                id: 'dhikr',
                icon: Icons.spa_outlined,
                title: 'ذكر الله خلال اليوم',
                summary: frequency,
                enabled: preferences.dhikrEnabled,
                onChanged: (value) =>
                    _update((p) => p.copyWith(dhikrEnabled: value)),
                details: [
                  const _ReminderNote(
                    'تسبيح واستغفار وصلاة على النبي؛ افتح الإشعار لتبدأ الذكر في المسبحة.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    key: ValueKey('dhikr-frequency-${preferences.dhikrPerDay}'),
                    initialValue: preferences.dhikrPerDay,
                    decoration: const InputDecoration(
                      labelText: 'عدد تذكيرات الذكر',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('مرة يوميًا')),
                      DropdownMenuItem(value: 3, child: Text('٣ مرات يوميًا')),
                      DropdownMenuItem(value: 5, child: Text('٥ مرات يوميًا')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _update((p) => p.copyWith(dhikrPerDay: value));
                      }
                    },
                  ),
                ],
              ),
              section(
                id: 'wird',
                icon: Icons.menu_book_outlined,
                title: 'الورد اليومي',
                summary: _time(preferences.dailyWirdMinute),
                enabled: preferences.dailyWirdEnabled,
                onChanged: (value) =>
                    _update((p) => p.copyWith(dailyWirdEnabled: value)),
                details: [
                  const _ReminderNote(
                    'يفتح موضع تلاوتك. إذا حددت تذكيرًا لختمتك يُستخدم موعدها.',
                  ),
                  _ReminderTimeTile(
                    title: 'موعد الورد اليومي',
                    minute: preferences.dailyWirdMinute,
                    onChanged: (value) =>
                        _update((p) => p.copyWith(dailyWirdMinute: value)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        MishkatCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            key: const ValueKey('reminder-sound-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('صوت التذكيرات'),
            subtitle: Text('مستقل عن صوت الأذان', style: text.bodySmall),
            value: preferences.sound,
            onChanged: (value) => _update((p) => p.copyWith(sound: value)),
          ),
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const PageStorageKey('reminder-timing-info'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 12),
            title: Text(
              'كيف تُنظّم مواعيد التذكير؟',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            children: const [
              _ReminderNote(
                'نباعد تذكيرات الصدقة والذكر والورد عن الصلاة وعن بعضها، وقد تتحرك قليلًا عن موعدك المختار. '
                'تصل بين ٨ صباحًا و١٠ ليلًا. أذكار الصباح والنوم والأذان تحتفظ بأوقاتها الخاصة.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReminderSection extends StatelessWidget {
  const _ReminderSection({
    required this.id,
    required this.icon,
    required this.title,
    required this.summary,
    required this.enabled,
    required this.expanded,
    required this.onTap,
    required this.children,
  });

  final String id;
  final IconData icon;
  final String title, summary;
  final bool enabled, expanded;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (id != 'adhkar')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: colors.borderSubtle),
          ),
        Semantics(
          expanded: expanded,
          child: ListTile(
            key: ValueKey('reminder-$id'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 7,
            ),
            horizontalTitleGap: 12,
            minLeadingWidth: 24,
            leading: Icon(icon, color: colors.primary, size: 23),
            title: Text(
              title,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                enabled ? summary : 'متوقف',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
            trailing: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: colors.textMuted,
              size: 22,
            ),
            onTap: onTap,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ReminderNote extends StatelessWidget {
  const _ReminderNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.mishkat.textSecondary, height: 1.8),
  );
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
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    subtitle: Text(
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context),
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: context.mishkat.primary),
    ),
    trailing: Icon(
      Icons.schedule_outlined,
      size: 20,
      color: context.mishkat.primary,
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
