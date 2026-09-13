import 'dart:async';

import 'package:http/http.dart' as http;

import '../auth/bilibili_auth.dart';
import '../errors/bilibili_exception.dart';
import '../models/bilibili_api_models.dart';
import '../parser/bilibili_dash_parser.dart';
import '../parser/bilibili_metadata_parser.dart';
import '../parser/bilibili_url_parser.dart';
import 'bilibili_http.dart';

/// HTTP/API boundary for Bilibili video playback.
///
/// The provider maps these platform models into provider-neutral DTOs. Keeping
/// HTTP code here lets future Bilibili API changes stay contained in this file
/// and its parser siblings.
///
/// Request plumbing is shared with the account layer through
/// [BilibiliHttpTransport], which is the single place cookies are attached and
/// the single place that guarantees credentials are never logged.
class BilibiliClient {
  BilibiliClient({
    this.auth = const AnonymousBilibiliAuthProvider(),
    BilibiliMetadataParser? metadataParser,
    BilibiliDashParser? playbackParser,
    BilibiliUrlParser? urlParser,
    http.Client? httpClient,
    this.debug = false,
    this.requestTimeout = const Duration(seconds: 15),
    this.maxShortLinkRedirects = 5,
    void Function(String message)? onDebugLog,
  }) : _metadataParser = metadataParser ?? const BilibiliMetadataParser(),
       _playbackParser = playbackParser ?? const BilibiliDashParser(),
       _urlParser = urlParser ?? const BilibiliUrlParser(),
       _http = BilibiliHttpTransport(
         auth: auth,
         httpClient: httpClient,
         debug: debug,
         requestTimeout: requestTimeout,
         onDebugLog: onDebugLog,
       ),
       assert(maxShortLinkRedirects > 0);

  final BilibiliAuthProvider auth;
  final bool debug;
  final Duration requestTimeout;
  final int maxShortLinkRedirects;

  final BilibiliMetadataParser _metadataParser;
  final BilibiliDashParser _playbackParser;
  final BilibiliUrlParser _urlParser;
  final BilibiliHttpTransport _http;

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
    final body = await _http.getString(uri);
    return _metadataParser.parseVideoInfoResponse(body);
  }

  /// Fetches the DASH playback response for a BVID and CID.
  ///
  /// [qn] is an optional Bilibili quality preference. DASH responses normally
  /// contain multiple qualities, so callers should still expose all returned
  /// streams to the user.
  Future<BilibiliPlaybackResponse> getPlayback({
    required String bvid,
    required String cid,
    int? qn,
  }) async {
    if (!_bvidPattern.hasMatch(bvid)) {
      throw const BilibiliParseException('Playback requires a valid BVID.');
    }

    final parsedCid = int.tryParse(cid);
    if (parsedCid == null || parsedCid <= 0) {
      throw const BilibiliParseException(
        'Playback requires a positive numeric CID.',
      );
    }

    final query = <String, String>{
      'bvid': bvid,
      'cid': parsedCid.toString(),
      'qn': (qn ?? 127).toString(),
      'fnval': '4048',
      'fnver': '0',
      'fourk': '1',
      'platform': 'pc',
      'otype': 'json',
    };

    final uri = Uri.https('api.bilibili.com', '/x/player/playurl', query);
    final body = await _http.getString(uri);
    return _playbackParser.parsePlaybackResponse(
      body,
      headers: _http.requestHeaders(),
    );
  }

  /// Resolves a b23.tv short URL while enforcing redirect limits.
  Future<Uri> resolveShortUrl(Uri shortUri) async {
    var current = shortUri;

    for (var hop = 0; hop <= maxShortLinkRedirects; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(_http.requestHeaders());

      final http.StreamedResponse response;
      try {
        response = await _http.httpClient.send(request).timeout(requestTimeout);
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

      _http.throwForHttpStatus(statusCode, headers: response.headers);
    }

    throw BilibiliNetworkException(
      'Bilibili short-link exceeded the maximum redirect count '
      '($maxShortLinkRedirects).',
    );
  }

  Future<void> _drainResponse(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>().timeout(requestTimeout);
    } catch (_) {
      // The redirect body is irrelevant. Response-body errors are re-checked
      // by the next hop or by the final response handling path.
    }
  }
}
