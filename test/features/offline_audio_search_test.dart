import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' show ChangeNotifierProvider;
import 'package:mishkat_app/core/constants/app_constants.dart';
import 'package:mishkat_app/core/services/offline_audio_download_controller.dart';
import 'package:mishkat_app/core/services/quran_audio_cache_service.dart';
import 'package:mishkat_app/core/theme/app_theme.dart';
import 'package:mishkat_app/features/quran/data/models/quran_models.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:mishkat_app/features/quran/presentation/cubit/quran_state.dart';
import 'package:mishkat_app/features/quran/presentation/pages/offline_audio_downloads_page.dart';

final _data = QuranData(
  chapters: const [
    QuranChapter(
      number: 1,
      name: 'الفاتحة',
      englishName: 'Al-Fatihah',
      revelationType: 'مكية',
      page: 1,
      ayahs: ['آية'],
      globalStart: 1,
    ),
    QuranChapter(
      number: 2,
      name: 'البقرة',
      englishName: 'Al-Baqarah',
      revelationType: 'مدنية',
      page: 2,
      ayahs: ['آية'],
      globalStart: 8,
    ),
  ],
  juz: const [],
  pages: const [],
);

class _Quran extends Cubit<QuranState> implements QuranCubit {
  _Quran() : super(QuranState(data: _data));
  @override
  String reciter = 'ar.alafasy';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads extends OfflineAudioDownloadController {
  _Downloads() : super(QuranAudioCacheService());
  int? requestedChapter;
  String? requestedReciter;
  @override
  Future<void> initialize() async {}
  @override
  int cachedCountNow({
    required String reciter,
    required int startAyah,
    required int endAyah,
  }) => 0;
  @override
  Future<void> downloadSurah({
    required ReciterInfo reciter,
    required QuranChapter chapter,
  }) async {
    requestedChapter = chapter.number;
    requestedReciter = reciter.id;
  }
}

void main() {
  testWidgets(
    'offline search filters names and Arabic numbers without changing the download target',
    (tester) async {
      final cubit = _Quran();
      final downloads = _Downloads();
      addTearDown(cubit.close);
      addTearDown(downloads.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<OfflineAudioDownloadController>.value(
          value: downloads,
          child: BlocProvider<QuranCubit>.value(
            value: cubit,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: OfflineAudioDownloadsPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      await tester.enterText(input, 'الْبَقَرَة');
      await tester.pumpAndSettle();
      expect(find.text('سورة البقرة'), findsOneWidget);
      expect(find.text('سورة الفاتحة'), findsNothing);
      await tester.tap(find.byTooltip('تنزيل السورة'));
      expect(downloads.requestedChapter, 2);
      expect(downloads.requestedReciter, 'ar.alafasy');
      await tester.enterText(input, '١');
      await tester.pumpAndSettle();
      expect(find.text('سورة الفاتحة'), findsOneWidget);
      expect(find.text('سورة البقرة'), findsNothing);
      await tester.enterText(input, 'غير موجود');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد سور مطابقة لبحثك'), findsOneWidget);
      await tester.tap(find.byTooltip('مسح البحث'));
      await tester.pumpAndSettle();
      expect(find.text('سورة الفاتحة'), findsOneWidget);
      expect(find.text('سورة البقرة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
