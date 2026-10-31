# ودجت الشاشة الرئيسية

يحتوي مشكاة على خمس إضافات أصلية تعمل على Android وiOS:

- **مواقيت الصلاة:** الصلاة التالية ووقتها وثلاثة مواعيد قريبة.
- **بوصلة القبلة:** اتجاه القبلة الثابت من الشمال والمسافة إلى الكعبة، وتفتح البوصلة الحية عند الضغط.
- **الورد اليومي:** يعرض صفحات ورد الختمة وموضع القراءة المحفوظ ونسبة الختمة، ويفتح القارئ مباشرة. عند غياب خطة أو توقفها أو إتمامها يفتح قسم الختمة.
- **المسبحة:** يعرض الذكر الحالي والعدّاد والهدف وإجمالي اليوم، ويفتح جلسة المسبحة الحالية. العدّ يتم داخل التطبيق؛ لا يغيّر الضغط على الإضافة العدّاد.
- **ذِكر اليوم:** ينتقل تلقائيًا بين أذكار الصباح والنهار والمساء والنوم.

تحسب Flutter بيانات يومين مقدمًا وتحفظها محليًا. يستخدم Android إنذارات النظام، ويستخدم iOS خطًا زمنيًا من WidgetKit، لذلك تتغير الصلاة والأذكار والتطبيق مغلق ومن دون إنترنت.

تتحدّث إضافتا الورد والمسبحة مع التقدّم في التطبيق وعند انتقاله إلى الخلفية أو عودته إليها. يتصفّر إجمالي تسبيح اليوم عند منتصف الليل عبر الخط الزمني مع الاحتفاظ بعدّاد الجلسة.

يتضمن معرض الإضافات تصفية حسب القرآن والذكر والصلاة والقبلة، وتبديل مظهر المعاينات، وإرشادات إضافة مخصصة لكل إضافة على الأجهزة التي لا تدعم التثبيت المباشر.

## إعداد iOS للإصدار الموقّع

أضيفت Entitlements وأهداف WidgetKit إلى المشروع. قبل بناء نسخة متجر موقعة يجب تسجيل App Group التالي في حساب Apple Developer وتفعيله لمعرّف التطبيق وامتدادات الودجت:

```text
group.com.dakomn.mishkatapp.widgets
```

الأهداف التي تستخدم المجموعة:

- `Runner`
- `PrayerTimesWidgetHomeWidget`
- `QiblaWidgetHomeWidget`
- `AdhkarWidgetHomeWidget`
- `WirdWidgetHomeWidget`
- `TasbihWidgetHomeWidget`

## تعديل تصميم الودجت

مصدر التصميم المشترك موجود في `home_widget/`. بعد أي تعديل شغّل:

```bash
dart run home_widget_cli:home_widget generate
```

هذا يحدّث كود Glance وWidgetKit ومساعدات Dart المولّدة. لا تعدّل الملفات المعلّمة بأنها Generated يدويًا.

## التحقق

```bash
flutter test test/core/home_widget_content_test.dart test/core/home_widget_service_test.dart test/features/home_widgets_page_test.dart
```

لحفظ صور المعرض بالمظهرين مع خط القاهرة وأيقونات Material:

```bash
flutter test --dart-define=CAPTURE_WIDGET_GALLERY=true test/features/home_widgets_page_test.dart
```

تُحفظ الصور في `screenshots/home_widgets_light.png` و`screenshots/home_widgets_dark.png`.
