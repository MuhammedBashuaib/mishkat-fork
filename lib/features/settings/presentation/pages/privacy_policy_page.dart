import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/navigation_icons.dart';

/// Available offline; describes this Flutter release rather than the old web app.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'رجوع',
        icon: const Icon(MishkatNavigationIcons.back),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('سياسة الخصوصية'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: const [PrivacyPolicyContent()],
      ),
    ),
  );
}

/// Shared offline copy for the settings dialog and the standalone route.
class PrivacyPolicyContent extends StatelessWidget {
  const PrivacyPolicyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'خصوصيتك في مشكاة',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'آخر تحديث: 8 نوفمبر 2026',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 28),
        for (final section in const [
          (
            'البيانات المحفوظة على جهازك',
            'لا يتطلب مشكاة إنشاء حساب. تُحفظ الإعدادات وموضع القراءة والعلامات وخطط الختمة والحفظ ونتائج المراجعة والأذكار المخصصة والعدادات والتلاوات المنزّلة محليًا. لا يضيف مشكاة نفسه إعلانات أو أدوات لتحليل استخدامك؛ للمحتوى الخارجي سياسات مستقلة كما هو موضح أدناه.',
          ),
          (
            'الموقع والقبلة',
            'يُطلب إذن الموقع عند اختيار استخدام موقعك لتحديد مواقيت الصلاة واتجاه القبلة. تُحفظ الإحداثيات المختارة في إعدادات التطبيق على جهازك وتُحسب المواقيت والقبلة محليًا. يمكنك اختيار مدينة يدويًا دون منح إذن الموقع. تستخدم البوصلة مستشعرات الجهاز عند فتح صفحة القبلة.',
          ),
          (
            'الميكروفون والتسميع',
            'يُطلب إذن الميكروفون عند بدء التسميع. في نسختي Android وiPhone يعالج نموذج التسميع المضمّن الصوت على الجهاز، ولا يرسله إلى خادم تابع لمشكاة. تُحفظ نتائج التدريب والتقدم، ولا تُحفظ جلسة التسميع كتسجيل صوتي دائم. لا يتطلب تشغيل النموذج تنزيل حزمة لغة أو اتصالًا بالإنترنت.',
          ),
          (
            'الاتصال وخدمات التلاوة',
            'المصحف والأذكار والمكتبة المرفقة تعمل دون إنترنت. الاستماع إلى تلاوة غير محفوظة أو إذاعة، وجلب نطق الكلمات، يتطلب الاتصال بمزوّد المحتوى، مثل Islamic Network وMP3Quran وQuran.com أو مصدر القارئ المحدد. يتلقى المزوّد عنوان الاتصال وطلب المحتوى اللازم لتقديمه، وتخضع خدمته لسياسة خصوصيته. لا يرسل مشكاة إليه خططك أو علاماتك أو إحداثياتك ضمن طلب التلاوة. عند فتح بث الحرمين المرئي يُحمّل محتوى YouTube، وقد يُفتح رابط قناته؛ يخضع ذلك لسياسات YouTube وقد يتضمن قياسًا للاستخدام أو إعلانات من المزوّد.',
          ),
          (
            'التنبيهات والودجت',
            'تُجدول التذكيرات محليًا بعد منح الإذن. تُشارك بيانات العرض اللازمة، مثل المدينة ومواقيت الصلاة والورد والعداد، مع إضافات مشكاة على الشاشة الرئيسية داخل مساحة التطبيق المشتركة على جهازك. قد يظهر هذا المحتوى على شاشة القفل وفق إعدادات جهازك.',
          ),
          (
            'الاحتفاظ والحذف',
            'تبقى البيانات المحلية حتى تحذفها. يمكنك حذف التلاوات من إدارة التنزيلات، أو اختيار «الإعدادات ← التنزيل والبيانات ← مسح جميع البيانات» لحذف البيانات والتلاوات المحفوظة وإعادة ضبط تقدم الميزات. قد تنسخ خدمات النسخ الاحتياطي التابعة لنظام التشغيل بيانات التطبيق بحسب إعداداتك؛ إدارة تلك النسخ تخضع لإعدادات الخدمة.',
          ),
          (
            'الأذونات والتواصل',
            'يمكنك سحب إذن الموقع أو الميكروفون أو الإشعارات من إعدادات الجهاز. ستظل الميزات التي لا تحتاج الإذن متاحة. للاستفسار عن الخصوصية: developer@dakomn.com.',
          ),
        ]) ...[
          Semantics(
            header: true,
            child: Text(
              section.$1,
              style: text.titleSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            section.$2,
            style: text.bodyMedium?.copyWith(height: 1.85),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
