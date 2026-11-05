import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/core/services/radio_stream_url_resolver.dart';

class _Headers implements HttpHeaders {
  _Headers(this.location);
  final String? location;

  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response implements HttpClientResponse {
  _Response(this.statusCode, [String? location]) : headers = _Headers(location);

  @override
  final int statusCode;
  @override
  final HttpHeaders headers;

  // Deliberately provide no body stream: live bodies must never be drained.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() {
    expect(followRedirects, isFalse);
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.responses);
  final List<Future<HttpClientResponse>> responses;
  final List<Uri> requested = [];
  bool forceClosed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return _Request(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) => forceClosed = force;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final original = Uri.parse('https://stream.radiojar.com/station');

  test(
    'unrelated streams bypass resolution, including similar host names',
    () async {
      final resolver = RadioStreamUrlResolver(
        httpClientFactory: () => throw StateError('Must not create a client'),
      );
      for (final url in [
        'https://backup.qurango.net/radio/sakeenah',
        'https://example.com/live/playlist.m3u8',
        'https://radiojar.com.example.com/station',
        'https://notradiojar.com/station',
      ]) {
        expect(await resolver.resolve(Uri.parse(url)), Uri.parse(url));
      }
    },
  );

  test('upgrades node redirect and preserves signed path and query', () async {
    const destination =
        'http://n09.radiojar.com/station?rj-ttl=5&rj-tok=test%2Btoken%2F%3D';
    final client = _Client([
      Future.value(_Response(302, destination)),
      Future.value(_Response(200)),
    ]);
    final resolver = RadioStreamUrlResolver(httpClientFactory: () => client);
    final resolved = await resolver.resolve(original);

    expect(resolved.toString(), destination.replaceFirst('http:', 'https:'));
    expect(client.requested, [original, resolved]);
    expect(client.requested.every((uri) => uri.scheme == 'https'), isTrue);
    expect(client.forceClosed, isTrue);
  });

  test(
    'resolves relative redirects and upgrades initial Radiojar HTTP',
    () async {
      final client = _Client([
        Future.value(_Response(307, '/station?token=relative')),
        Future.value(_Response(200)),
      ]);
      final resolver = RadioStreamUrlResolver(httpClientFactory: () => client);
      expect(
        await resolver.resolve(Uri.parse('http://stream.radiojar.com/start')),
        Uri.parse('https://stream.radiojar.com/station?token=relative'),
      );
      expect(client.requested.first.scheme, 'https');
      expect(client.forceClosed, isTrue);
    },
  );

  for (final destination in [
    'http://radiojar.com.example.com/station',
    'https://example.com/station',
    'file:///station',
    'ftp://n09.radiojar.com/station',
    'https://user:password@n09.radiojar.com/station',
  ]) {
    test('rejects unsupported redirect $destination', () async {
      final client = _Client([Future.value(_Response(302, destination))]);
      final resolver = RadioStreamUrlResolver(httpClientFactory: () => client);
      await expectLater(
        resolver.resolve(original),
        throwsA(isA<HttpException>()),
      );
      expect(client.requested, [original]);
      expect(client.forceClosed, isTrue);
    });
  }

  for (final response in [_Response(500), _Response(302)]) {
    test(
      'fails on unavailable or invalid redirect response ${response.statusCode}',
      () async {
        final client = _Client([Future.value(response)]);
        final resolver = RadioStreamUrlResolver(
          httpClientFactory: () => client,
        );
        await expectLater(
          resolver.resolve(original),
          throwsA(isA<HttpException>()),
        );
        expect(client.forceClosed, isTrue);
      },
    );
  }

  test('stops redirect loops at the configured limit', () async {
    final client = _Client([
      for (var i = 0; i < 3; i++) Future.value(_Response(302, '/station')),
    ]);
    final resolver = RadioStreamUrlResolver(
      httpClientFactory: () => client,
      maxRedirects: 2,
    );
    await expectLater(
      resolver.resolve(original),
      throwsA(isA<HttpException>()),
    );
    expect(client.requested, hasLength(3));
    expect(client.forceClosed, isTrue);
  });

  test(
    'times out stalled response and closes its dedicated connection',
    () async {
      final client = _Client([Completer<HttpClientResponse>().future]);
      final resolver = RadioStreamUrlResolver(
        httpClientFactory: () => client,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        resolver.resolve(original),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.forceClosed, isTrue);
    },
  );

  test('closes client when a connection fails', () async {
    final client = _Client([
      Future.delayed(
        Duration.zero,
        () => throw const SocketException('Connection failed'),
      ),
    ]);
    final resolver = RadioStreamUrlResolver(httpClientFactory: () => client);
    await expectLater(
      resolver.resolve(original),
      throwsA(isA<SocketException>()),
    );
    expect(client.forceClosed, isTrue);
  });
}
