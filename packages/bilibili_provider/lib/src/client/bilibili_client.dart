import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/bilibili_auth.dart';
import '../errors/bilibili_exception.dart';
import '../models/bilibili_api_models.dart';
import '../parser/bilibili_metadata_parser.dart';
import '../parser/bilibili_url_parser.dart';

/// HTTP/API boundary for Bilibili.
///
/// The provider maps these platform models into provider-neutral DTOs. Keeping
/// HTTP code here lets future Bilibili API changes stay contained in this file
/// and its parser siblings.
class BilibiliClient {
  BilibiliClient({
    this.auth = const AnonymousBilibiliAuthProvider(),
    BilibiliMetadataParser? metadataParser,
    BilibiliUrlParser? urlParser,
    http.Client? httpClient,
    this.debug = false,
    this.requestTimeout = const Duration(seconds: 15),
    this.maxShortLinkRedirects = 5,
  }) : _metadataParser = metadataParser ?? const BilibiliMetadataParser(),
       _urlParser = urlParser ?? const BilibiliUrlParser(),
       _httpClient = httpClient ?? http.Client(),
       assert(maxShortLinkRedirects > 0);

  final BilibiliAuthProvider auth;
  final bool debug;
  final Duration requestTimeout;
  final int maxShortLinkRedirects;

  final BilibiliMetadataParser _metadataParser;
  final BilibiliUrlParser _urlParser;
  final http.Client _httpClient;

  static final RegExp _bvidPattern = RegExp(r'^BV[0-9A-Za-z]{10}$');
  static final Set<int> _redirectStatusCodes = <int>{301, 302, 303, 307, 308};

  /// Fetches video metadata and part data for a BVID or `av` id.
  Future<BilibiliVideoInfo> getVideoInfo({required String id}) async {
    final query = <String, String>{};
    final normalizedId = id.trim();
    final lowerId = normalizedId.toLowerCase();

    if (lowerId.startsWith('av')) {
      final aidString = normalizedId.substring(2);
      final aid = int.tryParse(aidString);
      if (aid == null || aid <= 0) {
        throw const BilibiliParseException(
          'Video id must be a valid BVID or av id.',
        );
      }
      query['aid'] = aid.toString();
    } else if (_bvidPattern.hasMatch(normalizedId)) {
      query['bvid'] = normalizedId;
    } else {
      throw const BilibiliParseException(
        'Video id must be a valid BVID or av id.',
      );
    }

    final uri = Uri.https('api.bilibili.com', '/x/web-interface/view', query);
    final body = await _getString(uri);
    return _metadataParser.parseVideoInfoResponse(body);
  }

  /// Fetches the DASH playback response for a BVID and CID.
  Future<BilibiliPlaybackResponse> getPlayback({
    required String bvid,
    required String cid,
  }) {
    throw const BilibiliUnsupportedContentException(
      'BilibiliClient.getPlayback is implemented in Stage 3.',
    );
  }

  /// Resolves a b23.tv short URL while enforcing redirect limits.
  Future<Uri> resolveShortUrl(Uri shortUri) async {
    var current = shortUri;

    for (var hop = 0; hop <= maxShortLinkRedirects; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(_requestHeaders());

      final http.StreamedResponse response;
      try {
        response = await _httpClient.send(request).timeout(requestTimeout);
      } on TimeoutException catch (error, stackTrace) {
        throw BilibiliNetworkException(
          'Bilibili short-link request timed out.',
          cause: error,
          stackTrace: stackTrace,
        );
      } catch (error, stackTrace) {
        throw BilibiliNetworkException(
          'Bilibili short-link request failed.',
          cause: error,
          stackTrace: stackTrace,
        );
      }

      final statusCode = response.statusCode;
      final location = response.headers['location'];
      await _drainResponse(response);

      if (_redirectStatusCodes.contains(statusCode)) {
        if (location == null || location.isEmpty) {
          throw const BilibiliParseException(
            'Bilibili short-link response contained no Location header.',
          );
        }

        final next = current.resolve(location);
        if (!_urlParser.canHandle(next)) {
          throw const BilibiliUnsupportedContentException(
            'Bilibili short-link redirected to an unsupported URL.',
          );
        }
        current = next;
        continue;
      }

      if (statusCode >= 200 && statusCode < 300) {
        final parsed = _urlParser.parse(current);
        if (parsed.isShortLink) {
          throw const BilibiliParseException(
            'Bilibili short-link did not redirect to a supported video URL.',
          );
        }
        return current;
      }

      _throwForHttpStatus(statusCode, headers: response.headers);
    }

    throw BilibiliNetworkException(
      'Bilibili short-link exceeded the maximum redirect count '
      '($maxShortLinkRedirects).',
    );
  }

  Future<String> _getString(Uri uri) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(uri, headers: _requestHeaders())
          .timeout(requestTimeout);
    } on TimeoutException catch (error, stackTrace) {
      throw BilibiliNetworkException(
        'Bilibili request timed out.',
        cause: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw BilibiliNetworkException(
        'Bilibili request failed before receiving a response.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (response.statusCode != 200) {
      _throwForHttpStatus(response.statusCode, headers: response.headers);
    }

    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException catch (error, stackTrace) {
      throw BilibiliParseException(
        'Bilibili response was not valid UTF-8.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Map<String, String> _requestHeaders() {
    final headers = <String, String>{
      ...auth.requestHeaders,
      'Accept': 'application/json, text/plain, */*',
    };

    final cookie = auth.cookieHeader;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  Future<void> _drainResponse(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>().timeout(requestTimeout);
    } catch (_) {
      // The redirect body is irrelevant. Response-body errors are re-checked
      // by the next hop or by the final response handling path.
    }
  }

  Never _throwForHttpStatus(int statusCode, {Map<String, String>? headers}) {
    if (statusCode == 401 || statusCode == 403) {
      throw BilibiliAccessDeniedException(
        'Bilibili request was denied with HTTP $statusCode.',
        httpStatusCode: statusCode,
      );
    }
    if (statusCode == 404) {
      throw BilibiliNotFoundException(
        'Bilibili content was not found.',
        httpStatusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      throw BilibiliRateLimitException(
        'Bilibili rate limit was reached.',
        httpStatusCode: statusCode,
        retryAfter: _parseRetryAfter(headers),
      );
    }
    throw BilibiliNetworkException(
      'Bilibili request failed with HTTP $statusCode.',
      httpStatusCode: statusCode,
    );
  }

  Duration? _parseRetryAfter(Map<String, String>? headers) {
    final raw = headers?['retry-after'];
    if (raw == null) {
      return null;
    }
    final seconds = int.tryParse(raw);
    if (seconds == null || seconds < 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }
}
