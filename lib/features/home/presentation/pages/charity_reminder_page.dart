import 'package:flutter/material.dart';

import '../../../../core/widgets/mishkat_widgets.dart';

class CharityReminderPage extends StatelessWidget {
  const CharityReminderPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('باب خير اليوم')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Icon(Icons.volunteer_activism_outlined, size: 56),
        SizedBox(height: 20),
        Text(
          'هل تصدّقت اليوم؟',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 12),
        Text(
          'اجعل لك نصيبًا من العطاء بما تستطيع. قد تكون خطوة صغيرة منك سببًا في إسعاد إنسان.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, height: 1.8),
        ),
        SizedBox(height: 24),
        MishkatCard(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.favorite_outline),
                title: Text('صدقة لمن يحتاجها'),
                subtitle: Text('تفقّد قريبًا أو جارًا أو أسرة تعرف حاجتها.'),
              ),
              ListTile(
                leading: Icon(Icons.restaurant_outlined),
                title: Text('إطعام وسقيا'),
                subtitle: Text('وجبة لمحتاج أو ماء لعابر سبيل.'),
              ),
              ListTile(
                leading: Icon(Icons.handshake_outlined),
                title: Text('عون وكلمة طيبة'),
                subtitle: Text('ساعد أحدًا بوقتك، أو أدخل السرور عليه بكلمة.'),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        Text(
          'اختر ما يتيسّر لك، واستحضر نية الخير.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
