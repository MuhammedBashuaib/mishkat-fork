import 'package:home_widget_generator/home_widget_generator.dart';

const _background = HWThemedColor(
  light: HWFixedColor(0xFFF3F8F5),
  dark: HWFixedColor(0xFF10211B),
);
const _primary = HWThemedColor(
  light: HWFixedColor(0xFF276C5D),
  dark: HWFixedColor(0xFF91DDC0),
);
const _secondary = HWThemedColor(
  light: HWFixedColor(0xFF60716B),
  dark: HWFixedColor(0xFFADBBB5),
);
const _muted = HWThemedColor(
  light: HWFixedColor(0xFFDDEDE7),
  dark: HWFixedColor(0xFF1D3930),
);
const _text = HWThemedColor(
  light: HWFixedColor(0xFF17362F),
  dark: HWFixedColor(0xFFF3F8F5),
);

const _captionStyle = HWTextStyle(
  fontSize: 11,
  fontWeight: HWFontWeight.w600,
  color: _secondary,
);
const _labelStyle = HWTextStyle(
  fontSize: 12,
  fontWeight: HWFontWeight.w700,
  color: _primary,
);
const _titleStyle = HWTextStyle(
  fontSize: 22,
  fontWeight: HWFontWeight.w800,
  color: _text,
);

@HomeWidget(
  name: 'مواقيت الصلاة',
  description: 'الصلاة القادمة ومواقيت اليوم من مشكاة',
  widgetUrl: 'mishkat://prayer',
  android: HomeWidgetAndroidConfiguration(
    minWidth: 250,
    minHeight: 110,
    minResizeWidth: 180,
    minResizeHeight: 90,
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
        HWRow(
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWText(
              HWString(
                'prayerCity',
                defaultValue: 'حدّد موقعك في مشكاة',
                previewValue: 'مكة المكرمة',
              ),
              style: _captionStyle,
              textAlign: HWTextAlign.end,
            ),
            HWDecoratedBox(
              decoration: HWBoxDecoration(
                color: _muted,
                borderRadius: HWBorderRadius.circular(999),
              ),
              child: HWPadding(
                padding: HWEdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: HWText.fixed(
                  'مِشكاة • الصلاة',
                  style: _labelStyle,
                  textAlign: HWTextAlign.end,
                ),
              ),
            ),
          ],
        ),
        HWRow(
          crossAxisAlignment: HWCrossAxisAlignment.center,
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWDecoratedBox(
                  decoration: HWBoxDecoration(
                    color: _muted,
                    borderRadius: HWBorderRadius.circular(12),
                  ),
                  child: HWPadding(
                    padding: HWEdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: HWText(
                      HWTimedData(
                        HWString(
                          'prayerRemaining',
                          defaultValue: 'افتح مشكاة لتحديث المواقيت',
                          previewValue: 'متبقي نحو ساعتين',
                        ),
                      ),
                      style: _captionStyle,
                      textAlign: HWTextAlign.end,
                    ),
                  ),
                ),
              ],
            ),
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.end,
              children: [
                HWText.fixed(
                  'الصلاة القادمة',
                  style: _captionStyle,
                  textAlign: HWTextAlign.end,
                ),
                HWText(
                  HWTimedData(
                    HWString(
                      'prayerNextName',
                      defaultValue: '—',
                      previewValue: 'المغرب',
                    ),
                  ),
                  style: _titleStyle,
                  textAlign: HWTextAlign.end,
                ),
                HWText(
                  HWTimedData(
                    HWString(
                      'prayerNextTime',
                      defaultValue: '—',
                      previewValue: '٥:٤٢ م',
                    ),
                  ),
                  style: _labelStyle,
                  textAlign: HWTextAlign.end,
                ),
              ],
            ),
          ],
        ),
        HWDecoratedBox(
          decoration: HWBoxDecoration(
            color: _muted,
            borderRadius: HWBorderRadius.circular(10),
          ),
          child: HWPadding(
            padding: HWEdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: HWText(
              HWTimedData(
                HWString(
                  'prayerUpcoming',
                  defaultValue: 'تظهر المواقيت بعد تحديد الموقع',
                  previewValue: 'العصر ٣:٢١  •  المغرب ٥:٤٢  •  العشاء ٧:١٢',
                ),
              ),
              style: _captionStyle,
              textAlign: HWTextAlign.end,
            ),
          ),
        ),
      ],
    ),
  ),
)
class PrayerTimesWidget {}
