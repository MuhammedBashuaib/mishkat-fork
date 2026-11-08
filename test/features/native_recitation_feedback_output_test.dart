import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/quran/data/models/recitation_feedback_event.dart';
import 'package:mishkat_app/features/quran/presentation/services/recitation_feedback_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/mishkat_recitation_feedback');
  late List<MethodCall> calls;
  late NativeRecitationFeedbackOutput output;
  Future<Object?> Function(MethodCall)? response;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (response != null) return response!(call);
          return call.method == 'play' ? true : null;
        });
    output = NativeRecitationFeedbackOutput(channel: channel);
  });

  tearDown(() async {
    await output.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '${platform.name} refreshes preparation and plays all five cues with one owner',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        expect(await output.play(RecitationCue.ready), isFalse);
        expect(calls, isEmpty);

        await output.prepare();
        await output.prepare();
        for (final cue in RecitationCue.values) {
          expect(await output.play(cue), isTrue);
        }
        await output.stop();
        await output.dispose();

        expect(calls.map((call) => call.method), [
          'prepare',
          'prepare',
          ...List.filled(5, 'play'),
          'stop',
          'dispose',
        ]);
        expect(
          calls
              .where((call) => call.method == 'play')
              .map((call) => (call.arguments as Map)['cue']),
          ['ready', 'mistake', 'corrected', 'paused', 'complete'],
        );
        final owners = calls.map(
          (call) => (call.arguments as Map)['ownerId'] as String,
        );
        expect(owners.toSet(), hasLength(1));
        expect(owners.first, isNotEmpty);
      },
      skip: kIsWeb,
    );
  }

  for (final platform in [
    TargetPlatform.fuchsia,
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    test('${platform.name} never calls the native sound channel', () async {
      debugDefaultTargetPlatformOverride = platform;
      await output.prepare();
      expect(await output.play(RecitationCue.mistake), isFalse);
      await output.stop();
      await output.dispose();
      expect(calls, isEmpty);
    });
  }

  test(
    'web never calls the native sound channel even on a mobile platform',
    () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        final webOutput = NativeRecitationFeedbackOutput(channel: channel);
        await webOutput.prepare();
        expect(await webOutput.play(RecitationCue.mistake), isFalse);
        await webOutput.stop();
        await webOutput.dispose();
      }
      expect(calls, isEmpty);
    },
    skip: !kIsWeb,
  );

  group('native preparation lifecycle', () {
    test('concurrent prepares share loading and play does not queue', () async {
      final loading = Completer<void>();
      response = (call) async {
        if (call.method == 'prepare') {
          await loading.future;
          return null;
        }
        return call.method == 'play' ? true : null;
      };
      final first = output.prepare();
      final second = output.prepare();
      expect(await output.play(RecitationCue.mistake), isFalse);
      expect(calls.map((call) => call.method), ['prepare']);

      loading.complete();
      await Future.wait([first, second]);
      expect(calls.map((call) => call.method), ['prepare']);
      expect(await output.play(RecitationCue.corrected), isTrue);
      expect(calls.map((call) => call.method), ['prepare', 'play']);
    });

    test(
      'explicit prepare rearms feedback after a native interruption',
      () async {
        var armed = false;
        response = (call) async {
          switch (call.method) {
            case 'prepare':
              armed = true;
              return null;
            case 'play':
              return armed;
            case 'stop':
            case 'dispose':
              armed = false;
              return null;
          }
          throw StateError('Unexpected call ${call.method}');
        };
        await output.prepare();
        expect(await output.play(RecitationCue.ready), isTrue);
        // A phone call or route loss can stop native feedback while the same
        // Flutter page and output instance remain alive.
        armed = false;
        expect(await output.play(RecitationCue.mistake), isFalse);
        await output.prepare();
        expect(await output.play(RecitationCue.corrected), isTrue);
        expect(calls.where((call) => call.method == 'prepare'), hasLength(2));
      },
    );

    test('stop invalidates late loading and allows a fresh prepare', () async {
      final loading = Completer<void>();
      response = (call) async {
        if (call.method == 'prepare') {
          await loading.future;
          return null;
        }
        return call.method == 'play' ? true : null;
      };
      final startup = output.prepare();
      await output.stop();
      loading.complete();
      await startup;
      expect(await output.play(RecitationCue.mistake), isFalse);
      expect(calls.map((call) => call.method), ['prepare', 'stop']);

      response = null;
      await output.prepare();
      expect(await output.play(RecitationCue.ready), isTrue);
      expect(calls.map((call) => call.method), [
        'prepare',
        'stop',
        'prepare',
        'play',
      ]);
    });

    test('dispose invalidates late loading and is terminal', () async {
      final loading = Completer<void>();
      response = (call) async {
        if (call.method == 'prepare') {
          await loading.future;
          return null;
        }
        return call.method == 'play' ? true : null;
      };
      final startup = output.prepare();
      await output.dispose();
      loading.complete();
      await startup;
      await output.prepare();
      await output.stop();
      await output.dispose();
      expect(await output.play(RecitationCue.complete), isFalse);
      expect(calls.map((call) => call.method), ['prepare', 'dispose']);
    });

    for (final fails in [false, true]) {
      test(
        'old ${fails ? 'failed' : 'successful'} preparation cannot change a new one',
        () async {
          final oldLoading = Completer<void>();
          final newLoading = Completer<void>();
          var preparations = 0;
          response = (call) async {
            if (call.method == 'prepare') {
              preparations++;
              await (preparations == 1 ? oldLoading.future : newLoading.future);
              return null;
            }
            return call.method == 'play' ? true : null;
          };
          final oldStartup = output.prepare();
          await output.stop();
          final newStartup = output.prepare();
          if (fails) {
            oldLoading.completeError(PlatformException(code: 'cancelled'));
          } else {
            oldLoading.complete();
          }
          await oldStartup;
          expect(await output.play(RecitationCue.mistake), isFalse);

          newLoading.complete();
          await newStartup;
          expect(await output.play(RecitationCue.corrected), isTrue);
          expect(preparations, 2);
        },
      );
    }

    test('a failed prepare is safe and can be retried', () async {
      var preparations = 0;
      response = (call) async {
        if (call.method == 'prepare' && ++preparations == 1) {
          throw PlatformException(code: 'asset_unavailable');
        }
        return call.method == 'play' ? true : null;
      };
      await output.prepare();
      expect(await output.play(RecitationCue.ready), isFalse);
      await output.prepare();
      expect(await output.play(RecitationCue.ready), isTrue);
      expect(calls.map((call) => call.method), ['prepare', 'prepare', 'play']);
    });

    test('an unavailable platform plugin never fails recitation', () async {
      response = (_) async => throw MissingPluginException();
      await output.prepare();
      expect(await output.play(RecitationCue.mistake), isFalse);
      await output.stop();
      await output.dispose();
      expect(calls.map((call) => call.method), ['prepare', 'stop', 'dispose']);
    });

    test('native refusal or play error remains an optional effect', () async {
      await output.prepare();
      response = (_) async => false;
      expect(await output.play(RecitationCue.mistake), isFalse);
      response = (_) async => throw PlatformException(code: 'interrupted');
      expect(await output.play(RecitationCue.mistake), isFalse);
      response = null;
      expect(await output.play(RecitationCue.corrected), isTrue);
    });

    for (final dispose in [false, true]) {
      test(
        '${dispose ? 'dispose' : 'stop'} invalidates a late play response',
        () async {
          await output.prepare();
          final playback = Completer<bool>();
          response = (call) async {
            if (call.method == 'play') return playback.future;
            return null;
          };
          final playing = output.play(RecitationCue.mistake);
          if (dispose) {
            await output.dispose();
          } else {
            await output.stop();
          }
          playback.complete(true);
          expect(await playing, isFalse);
        },
      );
    }

    test('different output lifetimes always carry distinct owners', () async {
      final replacement = NativeRecitationFeedbackOutput(channel: channel);
      addTearDown(replacement.dispose);
      await output.prepare();
      final firstOwner = (calls.last.arguments as Map)['ownerId'];
      await replacement.prepare();
      final nextOwner = (calls.last.arguments as Map)['ownerId'];
      expect(firstOwner, isNot(nextOwner));
      await output.dispose();
      expect((calls.last.arguments as Map)['ownerId'], firstOwner);
      expect(await replacement.play(RecitationCue.ready), isTrue);
      expect((calls.last.arguments as Map)['ownerId'], nextOwner);
    });
  }, skip: kIsWeb);
}
