import 'dart:async';
import 'dart:io';

/// Keeps Radiojar's load-balanced stream redirects on HTTPS for AVPlayer.
///
/// Radiojar's public HTTPS endpoint currently redirects to an HTTP node even
/// though that same node accepts HTTPS. Resolve its short-lived redirect for
/// each playback request instead of hardcoding a node or relaxing iOS ATS.
class RadioStreamUrlResolver {
  RadioStreamUrlResolver({
    HttpClient Function()? httpClientFactory,
    this.timeout = const Duration(seconds: 10),
    this.maxRedirects = 5,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;
  final Duration timeout;
  final int maxRedirects;

  Future<Uri> resolve(Uri url) async {
    if (!_isRadiojar(url)) return url;

    final client = _httpClientFactory();
    try {
      return await _resolve(client, url).timeout(timeout);
    } finally {
      // A successful response is a continuous live stream. Draining its body
      // would never finish; close this dedicated connection immediately.
      client.close(force: true);
    }
  }

  Future<Uri> _resolve(HttpClient client, Uri url) async {
    var current = _secureRadiojarUrl(url);
    for (var redirects = 0; ; redirects++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return current;
      }
      if (!_isRedirect(response.statusCode)) {
        throw HttpException('Radio stream returned ${response.statusCode}.');
      }
      if (redirects >= maxRedirects) {
        throw const HttpException('Too many radio stream redirects.');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw const HttpException('Radio stream redirect has no location.');
      }
      current = _secureRadiojarUrl(current.resolve(location));
    }
  }

  static bool _isRadiojar(Uri uri) =>
      uri.host == 'radiojar.com' || uri.host.endsWith('.radiojar.com');

  static Uri _secureRadiojarUrl(Uri uri) {
    if (!_isRadiojar(uri) ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty) {
      throw const HttpException('Unsupported radio stream redirect.');
    }
    // Uri.replace preserves the path and signed query exactly. The token must
    // remain private and must not be persisted as a permanent station URL.
    return uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;
  }

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;
}
