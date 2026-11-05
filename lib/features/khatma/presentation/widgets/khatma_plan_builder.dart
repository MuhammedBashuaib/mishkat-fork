import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/mishkat_widgets.dart';
import '../../data/models/khatma_plan.dart';
import '../../data/models/khatma_schedule.dart';

class KhatmaPlanDraft {
  const KhatmaPlanDraft({
    required this.name,
    required this.startPage,
    required this.schedule,
    required this.planningMode,
    this.reminderPrayer,
    this.reminderTime,
  });

  final String name;
  final int startPage;
  final KhatmaSchedule schedule;
  final KhatmaPlanningMode planningMode;
  final String? reminderPrayer;
  final String? reminderTime;
}

enum _DurationUnit {
  days('أيام', 1),
  weeks('أسابيع', 7),
  months('أشهر', 30);

  const _DurationUnit(this.label, this.multiplier);
  final String label;
  final int multiplier;
}

class KhatmaPlanBuilder extends StatefulWidget {
  const KhatmaPlanBuilder({
    super.key,
    required this.suggestedPage,
    this.initialDuration = 30,
  });

  final int suggestedPage;
  final int initialDuration;

  @override
  State<KhatmaPlanBuilder> createState() => _KhatmaPlanBuilderState();
}

class _KhatmaPlanBuilderState extends State<KhatmaPlanBuilder> {
  static const _presets = [
    (days: 7, label: 'أسبوع'),
    (days: 15, label: '15 يومًا'),
    (days: 30, label: 'شهر'),
    (days: 60, label: 'شهران'),
    (days: 90, label: '3 أشهر'),
  ];
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'ختمتي');
  final _dailyPages = TextEditingController(text: '5');
  late final TextEditingController _startPage;
  late final TextEditingController _customDuration;
  late int _presetDays;
  late bool _custom;
  var _mode = KhatmaPlanningMode.duration;
  var _unit = _DurationUnit.days;
  var _reminder = 'fajr';
  var _reminderTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    final page = widget.suggestedPage.clamp(1, 604);
    _startPage = TextEditingController(text: '$page');
    _presetDays = widget.initialDuration.clamp(1, 605 - page);
    _custom = !_presets.any((option) => option.days == _presetDays);
    _customDuration = TextEditingController(text: '$_presetDays');
  }

  @override
  void dispose() {
    _name.dispose();
    _startPage.dispose();
    _customDuration.dispose();
    _dailyPages.dispose();
    super.dispose();
  }

  int? _number(String? value) =>
      int.tryParse(AppFormatters.normalizeArabic(value ?? ''));

  int? get _durationDays => !_custom
      ? _presetDays
      : switch (_number(_customDuration.text)) {
          final int value => value * _unit.multiplier,
          null => null,
        };

  int get _remainingPages =>
      605 - (_number(_startPage.text) ?? 1).clamp(1, 604);

  String? _pageError(String? value) {
    final page = _number(value);
    return page == null || page < 1 || page > 604
        ? 'أدخل رقم صفحة من 1 إلى 604.'
        : null;
  }

  String? _durationError([String? _]) {
    final days = _durationDays;
    if (days == null || days < 1) return 'أدخل مدة أكبر من صفر.';
    if (days > _remainingPages) {
      return 'الحد الأقصى $_remainingPages يومًا، لقراءة صفحة واحدة على الأقل يوميًا.';
    }
    return null;
  }

  String? _dailyError(String? value) {
    final pages = _number(value);
    return pages == null || pages < 1 || pages > 604
        ? 'أدخل عددًا من 1 إلى 604 صفحة يوميًا.'
        : null;
  }

  KhatmaSchedule? get _schedule {
    if (_pageError(_startPage.text) != null) return null;
    final page = _number(_startPage.text)!;
    if (_mode == KhatmaPlanningMode.pages) {
      if (_dailyError(_dailyPages.text) != null) return null;
      return KhatmaSchedule.fromDailyPages(
        startPage: page,
        dailyPages: _number(_dailyPages.text)!,
      );
    }
    if (_durationError() != null) return null;
    return KhatmaSchedule.fromDuration(
      startPage: page,
      durationDays: _durationDays!,
    );
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final schedule = _schedule;
    if (schedule == null) return;
    Navigator.pop(
      context,
      KhatmaPlanDraft(
        name: _name.text.trim(),
        startPage: _number(_startPage.text)!,
        schedule: schedule,
        planningMode: _mode,
        reminderPrayer: _reminder == 'none' || _reminder == 'custom'
            ? null
            : _reminder,
        reminderTime: _reminder == 'custom'
            ? '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}'
            : null,
      ),
    );
  }

  InputDecoration _numberDecoration(String label, {String? helper}) =>
      InputDecoration(labelText: label, helperText: helper, errorMaxLines: 3);

  List<TextInputFormatter> get _numberFormatters => [
    FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
    LengthLimitingTextInputFormatter(4),
  ];

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    final colors = context.mishkat;
    return DefaultTabController(
      length: 2,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          MishkatSpacing.lg,
          MishkatSpacing.md,
          MishkatSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + MishkatSpacing.xl,
        ),
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(MishkatRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: MishkatSpacing.lg),
              Text(
                'أنشئ خطة ختمتك',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'حدد مدة الختمة أو صفحاتك اليومية، وسنرتّب لك الورد.',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: MishkatSpacing.base),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'اسم الختمة'),
              ),
              const SizedBox(height: MishkatSpacing.md),
              TextFormField(
                key: const ValueKey('khatma-start-page'),
                controller: _startPage,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: _numberFormatters,
                validator: _pageError,
                onChanged: (_) => setState(() {}),
                decoration: _numberDecoration('ابدأ من الصفحة'),
              ),
              const SizedBox(height: MishkatSpacing.lg),
              Text(
                'مدة الختمة',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: MishkatSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: MishkatRadius.brMd,
                ),
                child: TabBar(
                  onTap: (index) => setState(() {
                    _mode = index == 0
                        ? KhatmaPlanningMode.duration
                        : KhatmaPlanningMode.pages;
                  }),
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  indicator: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: MishkatRadius.brMd,
                    border: Border.all(color: colors.primary),
                  ),
                  labelColor: colors.primary,
                  unselectedLabelColor: colors.textSecondary,
                  tabs: const [
                    Tab(text: 'بالمدة'),
                    Tab(text: 'بالصفحات'),
                  ],
                ),
              ),
              const SizedBox(height: MishkatSpacing.base),
              if (_mode == KhatmaPlanningMode.duration) ...[
                Wrap(
                  spacing: MishkatSpacing.sm,
                  runSpacing: MishkatSpacing.sm,
                  children: [
                    for (final option in _presets)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: !_custom && _presetDays == option.days,
                        labelStyle: TextStyle(
                          color: !_custom && _presetDays == option.days
                              ? colors.primary
                              : colors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                        selectedColor: colors.primarySoft,
                        backgroundColor: colors.surface,
                        checkmarkColor: colors.primary,
                        onSelected: (_) => setState(() {
                          _custom = false;
                          _presetDays = option.days;
                        }),
                      ),
                    ChoiceChip(
                      label: const Text('مخصص'),
                      selected: _custom,
                      labelStyle: TextStyle(
                        color: _custom ? colors.primary : colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                      selectedColor: colors.primarySoft,
                      backgroundColor: colors.surface,
                      checkmarkColor: colors.primary,
                      onSelected: (_) => setState(() => _custom = true),
                    ),
                  ],
                ),
                if (_custom) ...[
                  const SizedBox(height: MishkatSpacing.base),
                  TextFormField(
                    key: const ValueKey('khatma-custom-duration'),
                    controller: _customDuration,
                    keyboardType: TextInputType.number,
                    inputFormatters: _numberFormatters,
                    validator: _durationError,
                    onChanged: (_) => setState(() {}),
                    decoration: _numberDecoration('المدة التي تناسبك'),
                  ),
                  const SizedBox(height: MishkatSpacing.md),
                  DropdownButtonFormField<_DurationUnit>(
                    key: const ValueKey('khatma-duration-unit'),
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'وحدة المدة'),
                    items: [
                      for (final unit in _DurationUnit.values)
                        DropdownMenuItem(value: unit, child: Text(unit.label)),
                    ],
                    onChanged: (unit) => setState(() => _unit = unit!),
                  ),
                ],
                if (!_custom && _durationError() != null)
                  Padding(
                    padding: const EdgeInsets.only(top: MishkatSpacing.sm),
                    child: Text(
                      _durationError()!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if ((!_custom && _presetDays >= 30) ||
                    (_custom && _unit == _DurationUnit.months))
                  const _Hint('يُحسب الشهر 30 يومًا لتوزيع الورد بوضوح.'),
              ] else ...[
                TextFormField(
                  key: const ValueKey('khatma-daily-pages'),
                  controller: _dailyPages,
                  keyboardType: TextInputType.number,
                  inputFormatters: _numberFormatters,
                  validator: _dailyError,
                  onChanged: (_) => setState(() {}),
                  decoration: _numberDecoration('عدد الصفحات يوميًا'),
                ),
                const _Hint(
                  'سنحسب مدة الختمة من الصفحات المتبقية، وقد يكون الورد الأخير أقل.',
                ),
              ],
              const SizedBox(height: MishkatSpacing.base),
              Container(
                key: const ValueKey('khatma-preview'),
                padding: const EdgeInsets.all(MishkatSpacing.base),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: MishkatRadius.brMd,
                  border: Border.all(color: colors.border),
                ),
                child: schedule == null
                    ? Text(
                        'أكمل القيم الصحيحة لعرض وردك وموعد الختمة.',
                        style: TextStyle(color: colors.textSecondary),
                      )
                    : Text(
                        'وردك: ${_wardLabel(schedule)}\n'
                        'مدة الختمة: ${schedule.durationDays} يومًا\n'
                        'موعد الإتمام المتوقع: ${AppFormatters.gregorianDate(schedule.targetDate(DateTime.now()))}',
                        style: TextStyle(
                          height: 1.7,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                        ),
                      ),
              ),
              const SizedBox(height: MishkatSpacing.lg),
              DropdownButtonFormField<String>(
                key: const ValueKey('khatma-reminder'),
                initialValue: _reminder,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'تذكير الورد'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('دون تذكير')),
                  DropdownMenuItem(value: 'custom', child: Text('وقت محدد')),
                  DropdownMenuItem(value: 'fajr', child: Text('بعد الفجر')),
                  DropdownMenuItem(value: 'dhuhr', child: Text('بعد الظهر')),
                  DropdownMenuItem(value: 'asr', child: Text('بعد العصر')),
                  DropdownMenuItem(value: 'maghrib', child: Text('بعد المغرب')),
                  DropdownMenuItem(value: 'isha', child: Text('بعد العشاء')),
                ],
                onChanged: (value) => setState(() => _reminder = value!),
              ),
              if (_reminder == 'custom') ...[
                const SizedBox(height: MishkatSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('khatma-reminder-time'),
                  icon: const Icon(Icons.access_time_rounded),
                  label: Text('وقت التذكير: ${_reminderTime.format(context)}'),
                  onPressed: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _reminderTime,
                      helpText: 'وقت تذكير الورد',
                    );
                    if (time != null && mounted) {
                      setState(() => _reminderTime = time);
                    }
                  },
                ),
                const _Hint('تذكير يومي في الوقت الذي تختاره حسب توقيت جهازك.'),
              ] else if (_reminder != 'none')
                const _Hint(
                  'بعد الصلاة بـ15 دقيقة حسب موقعك. دون موقع، يُستخدم وقت الورد في الإعدادات.',
                ),
              const SizedBox(height: MishkatSpacing.lg),
              MishkatPrimaryButton(
                key: const ValueKey('khatma-submit'),
                onPressed: _submit,
                label: 'ابدأ الختمة',
                icon: const Icon(Icons.check_rounded),
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _wardLabel(KhatmaSchedule schedule) {
    if (_mode == KhatmaPlanningMode.pages) {
      return '${_number(_dailyPages.text)} صفحة يوميًا';
    }
    if (schedule.minDailyPages == schedule.maxDailyPages) {
      return '${schedule.maxDailyPages} صفحة يوميًا';
    }
    return 'من ${schedule.minDailyPages} إلى ${schedule.maxDailyPages} صفحة يوميًا';
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: MishkatSpacing.sm),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.6,
        color: context.mishkat.textSecondary,
      ),
    ),
  );
}
