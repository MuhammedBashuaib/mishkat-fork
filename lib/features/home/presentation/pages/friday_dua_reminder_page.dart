import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/mishkat_widgets.dart';

class FridayDuaReminderPage extends StatelessWidget {
  const FridayDuaReminderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mishkat;
    return Scaffold(
      appBar: AppBar(title: const Text('دعاء يوم الجمعة')),
      body: ListView(
        padding: MishkatSpacing.page,
        children: [
          Icon(Icons.wb_twilight_rounded, size: 56, color: colors.primary),
          const SizedBox(height: MishkatSpacing.lg),
          Text(
            'ساعة تُرجى فيها الإجابة',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: MishkatSpacing.md),
          const Text(
            'اغتنم آخر ساعة قبل الغروب بالدعاء، فهي ساعة تُرجى فيها الإجابة. '
            'اجعل لك فيها وقتًا هادئًا تسأل الله فيه من خير الدنيا والآخرة.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, height: 1.8),
          ),
          const SizedBox(height: MishkatSpacing.xl),
          const MishkatCard(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.favorite_outline),
                  title: Text('أقبل على الله بقلب حاضر'),
                  subtitle: Text('احمد الله وأثنِ عليه، وصلِّ على النبي ﷺ.'),
                ),
                ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('ادعُ لنفسك ولمن تحب'),
                  subtitle: Text(
                    'اسأل الله العفو والعافية والهداية، واذكر والديك وأهلك والمسلمين بدعوة.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.spa_outlined),
                  title: Text('ادعُ برجاء وحسن ظن'),
                  subtitle: Text(
                    'ألحّ في الدعاء بما تحتاج، ولا تستعجل الإجابة.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MishkatSpacing.xl),
          Text(
            'والدعاء باب خير في كل وقت.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
