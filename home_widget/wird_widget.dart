import 'package:home_widget_generator/home_widget_generator.dart';

// Design seed only: native layouts are maintained separately.
// Read docs/HOME_WIDGETS.md before running the generator.

const _background = HWThemedColor(
  light: HWFixedColor(0xFFF2F7F3),
  dark: HWFixedColor(0xFF152923),
);
const _accent = HWThemedColor(
  light: HWFixedColor(0xFF486B65),
  dark: HWFixedColor(0xFFA9D9CC),
);
const _text = HWThemedColor(
  light: HWFixedColor(0xFF263B35),
  dark: HWFixedColor(0xFFF6F4F1),
);

@HomeWidget(
  name: 'الورد اليومي',
  description: 'ورد ختمتك وموضع القراءة المحفوظ',
  widgetUrl: 'mishkat://wird',
  android: HomeWidgetAndroidConfiguration(
    minWidth: 250,
    minHeight: 130,
    minResizeWidth: 220,
    minResizeHeight: 130,
    targetCellWidth: 4,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontalAndVertical,
    widgetCategory: HWAndroidWidgetCategory.homeScreen,
    updatePeriodMillis: 1800000,
    backgroundColor: _background,
  ),
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.com.dakomn.mishkatapp.widgets',
    supportedFamilies: [HWWidgetFamily.systemMedium],
    backgroundColor: _background,
  ),
  widget: HWSizedBox.expand(
    child: HWColumn(
      crossAxisAlignment: HWCrossAxisAlignment.end,
      mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
      children: [
        HWText.fixed(
          'مِشكاة • الورد اليومي',
          style: HWTextStyle(
            fontSize: 11,
            fontWeight: HWFontWeight.w700,
            color: _accent,
          ),
        ),
        HWDecoratedBox(
          decoration: HWBoxDecoration(
            color: HWThemedColor(
              light: HWFixedColor(0xFFE2EEE7),
              dark: HWFixedColor(0xFF233E33),
            ),
            borderRadius: HWBorderRadius.circular(18),
          ),
          child: HWPadding(
            padding: HWEdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.end,
              children: [
                HWText(
                  HWString(
                    'wirdName',
                    defaultValue: 'رحلتك مع القرآن',
                    previewValue: 'ختمتي',
                  ),
                  style: HWTextStyle(
                    fontSize: 11,
                    fontWeight: HWFontWeight.w600,
                    color: _accent,
                  ),
                  textAlign: HWTextAlign.end,
                ),
                HWText(
                  HWString(
                    'wirdPages',
                    defaultValue: 'ابدأ ختمتك الأولى',
                    previewValue: 'صفحة ٤٢ – ٦٢',
                  ),
                  style: HWTextStyle(
                    fontSize: 23,
                    fontWeight: HWFontWeight.w800,
                    color: _text,
                  ),
                  textAlign: HWTextAlign.end,
                ),
                HWText(
                  HWString(
                    'wirdDetail',
                    defaultValue: 'حدّد خطتك ليظهر وردك هنا',
                    previewValue: '٢١ صفحة في وردك الحالي',
                  ),
                  style: HWTextStyle(
                    fontSize: 12,
                    fontWeight: HWFontWeight.w600,
                    color: _accent,
                  ),
                  textAlign: HWTextAlign.end,
                ),
                HWText(
                  HWString(
                    'wirdProgress',
                    defaultValue: 'خطوة صغيرة كل يوم',
                    previewValue: '٧٪ من الختمة',
                  ),
                  style: HWTextStyle(
                    fontSize: 12,
                    fontWeight: HWFontWeight.w600,
                    color: _accent,
                  ),
                  textAlign: HWTextAlign.end,
                ),
              ],
            ),
          ),
        ),
        HWText(
          HWString(
            'wirdAction',
            defaultValue: 'اضغط لإنشاء خطة',
            previewValue: 'اضغط لمتابعة القراءة',
          ),
          style: HWTextStyle(
            fontSize: 10,
            fontWeight: HWFontWeight.w600,
            color: _accent,
          ),
          textAlign: HWTextAlign.end,
        ),
      ],
    ),
  ),
)
class WirdWidget {}
