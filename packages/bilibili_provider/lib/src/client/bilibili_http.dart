import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../account/bilibili_cookies.dart';
import '../auth/bilibili_auth.dart';
import '../errors/bilibili_exception.dart';

/// One HTTP response, including the headers a login flow needs.
///
/// [setCookieHeaders] keeps every `Set-Cookie` value separately, because the
/// Bilibili login endpoint delivers the session there and naive comma splitting
/// would corrupt a cookie whose `Expires` attribute contains a comma.
class BilibiliHttpResult {
  const BilibiliHttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.setCookieHeaders = const <String>[],
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;

  /// Individual `Set-Cookie` header values, in response order.
  final List<String> setCookieHeaders;

  @override
  String toString() => 'BilibiliHttpResult($statusCode, ${body.length} bytes)';
}

/// Shared HTTP plumbing for Bilibili API and CDN requests.
///
/// This type owns the single place where cookies are attached to a request so
/// that every Bilibili client behaves consistently. It never logs, prints, or
/// embeds cookie values in exception messages:
///
/// - debug output contains only the method, host, path and status code;
/// - query strings and request bodies are never forwarded to the debug logger;
/// - response bodies are never included in failures.
class BilibiliHttpTransport {
  BilibiliHttpTransport({
    this.auth = const AnonymousBilibiliAuthProvider(),
    http.Client? httpClient,
    this.debug = false,
    this.requestTimeout = const Duration(seconds: 15),
    this.onDebugLog,
  }) : _httpClient = httpClient ?? http.Client();

  /// Source of request headers and the cookie header.
  final BilibiliAuthProvider auth;

  /// Whether [onDebugLog] receives diagnostics. Off by default.
  final bool debug;

  final Duration requestTimeout;

  /// Optional sanitized debug sink. Only invoked when [debug] is true.
  final void Function(String message)? onDebugLog;

  final http.Client _httpClient;

  /// The underlying HTTP client. Exposed for adapter-level reuse.
  http.Client get httpClient => _httpClient;

  /// Builds request headers for an API call.
  ///
  /// [cookiesOverride] replaces the auth provider's cookie header for a single
  /// request. It exists so a candidate cookie jar can be validated before it is
  /// adopted as the active session.
  Map<String, String> requestHeaders({
    String? contentType,
    BilibiliCookies? cookiesOverride,
  }) {
    final headers = <String, String>{
      ...auth.requestHeaders,
      'Accept': 'application/json, text/plain, */*',
    };

    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }

    final cookie = cookiesOverride?.cookieHeader ?? auth.cookieHeader;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /// Performs a JSON GET request and returns the decoded UTF-8 body.
  Future<String> getString(Uri uri, {BilibiliCookies? cookiesOverride}) async {
    return (await getResult(uri, cookiesOverride: cookiesOverride)).body;
  }

  /// Performs a GET request and keeps the status and headers.
  ///
  /// Needed by the QR login flow, which receives the session through
  /// `Set-Cookie` and also reports progress through the response body.
  Future<BilibiliHttpResult> getResult(
    Uri uri, {
    BilibiliCookies? cookiesOverride,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(uri, headers: requestHeaders(cookiesOverride: cookiesOverride))
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

    _debugLog('GET', uri, response.statusCode);

    if (response.statusCode != 200) {
      throwForHttpStatus(response.statusCode, headers: response.headers);
    }

    return BilibiliHttpResult(
      statusCode: response.statusCode,
      headers: response.headers,
      body: _decodeBody(response),
      setCookieHeaders:
          response.headersSplitValues['set-cookie'] ?? const <String>[],
    );
  }

  /// Performs a form-encoded POST request and returns the decoded UTF-8 body.
  ///
  /// Callers are responsible for including the `csrf` field; this transport
  /// never adds credentials on its own and never logs the body.
  Future<String> postForm(
    Uri uri,
    Map<String, String> body, {
    BilibiliCookies? cookiesOverride,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: requestHeaders(
              contentType: _formContentType,
              cookiesOverride: cookiesOverride,
            ),
            body: _encodeForm(body),
          )
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

    _debugLog('POST', uri, response.statusCode);

    if (response.statusCode != 200) {
      throwForHttpStatus(response.statusCode, headers: response.headers);
    }

    return _decodeBody(response);
  }

  /// Maps a non-2xx HTTP status to a structured exception.
  Never throwForHttpStatus(int statusCode, {Map<String, String>? headers}) {
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
        retryAfter: parseRetryAfter(headers),
      );
    }
    throw BilibiliNetworkException(
      'Bilibili request failed with HTTP $statusCode.',
      httpStatusCode: statusCode,
    );
  }

  /// Parses a `Retry-After` header value in seconds.
  Duration? parseRetryAfter(Map<String, String>? headers) {
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

  static const String _formContentType =
      'application/x-www-form-urlencoded; charset=UTF-8';

  String _encodeForm(Map<String, String> body) {
    return body.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  String _decodeBody(http.Response response) {
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

  /// Emits a sanitized diagnostics line. Never includes cookies, query strings,
  /// request bodies, or response bodies.
  void _debugLog(String method, Uri uri, int statusCode) {
    final sink = onDebugLog;
    if (!debug || sink == null) {
      return;
    }
    sink('$method ${uri.host}${uri.path} -> $statusCode');
  }

  @override
  String toString() => 'BilibiliHttpTransport(debug: $debug)';
}
