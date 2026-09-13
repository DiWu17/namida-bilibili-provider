import '../errors/bilibili_exception.dart';
import '../models/bilibili_media_ref.dart';

/// Parses supported Bilibili video URLs without performing network I/O.
///
/// Supported shapes:
/// - `https://www.bilibili.com/video/BV...`
/// - `https://www.bilibili.com/video/av...`
/// - `https://b23.tv/...`
///
/// A `?p=N` query parameter is captured as a 1-based [BilibiliMediaRef.page].
class BilibiliUrlParser {
  const BilibiliUrlParser();

  static final RegExp _bvidPattern = RegExp(r'^BV[0-9A-Za-z]{10}$');
  static final RegExp _avPattern = RegExp(
    r'^av([0-9]+)$',
    caseSensitive: false,
  );

  /// Returns true when [uri] is a supported canonical or short URL.
  bool canHandle(Uri uri) {
    try {
      parse(uri);
      return true;
    } on BilibiliException {
      return false;
    }
  }

  /// Parses a supported URL or throws a structured [BilibiliException].
  BilibiliMediaRef parse(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const BilibiliUnsupportedContentException(
        'Only http and https Bilibili URLs are supported.',
      );
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      throw const BilibiliUnsupportedContentException(
        'Bilibili URL must be absolute.',
      );
    }

    final page = _parsePage(uri);

    if (_isB23Host(host)) {
      return _parseShortLink(uri, page);
    }

    if (!_isBilibiliHost(host)) {
      throw const BilibiliUnsupportedContentException(
        'URL host is not a supported Bilibili host.',
      );
    }

    return _parseCanonical(uri, page);
  }

  BilibiliMediaRef _parseCanonical(Uri uri, int? page) {
    final segments = _nonEmptyPathSegments(uri);
    if (segments.length != 2 || segments.first.toLowerCase() != 'video') {
      throw const BilibiliUnsupportedContentException(
        'Only /video/<BVID|avID> Bilibili URLs are supported.',
      );
    }

    final rawId = segments[1];
    final bvidMatch = _bvidPattern.firstMatch(rawId);
    if (bvidMatch != null) {
      return BilibiliMediaRef(
        kind: BilibiliMediaIdKind.bvid,
        id: rawId,
        source: uri,
        page: page,
      );
    }

    final avMatch = _avPattern.firstMatch(rawId);
    if (avMatch != null) {
      return BilibiliMediaRef(
        kind: BilibiliMediaIdKind.aid,
        id: avMatch.group(1)!,
        source: uri,
        page: page,
      );
    }

    throw const BilibiliParseException(
      'Video path does not contain a valid BVID or av ID.',
    );
  }

  BilibiliMediaRef _parseShortLink(Uri uri, int? page) {
    final segments = _nonEmptyPathSegments(uri);
    if (segments.length != 1) {
      throw const BilibiliParseException(
        'b23.tv short link must contain exactly one token.',
      );
    }

    final token = segments.single;
    final bvidMatch = _bvidPattern.firstMatch(token);
    if (bvidMatch != null) {
      return BilibiliMediaRef(
        kind: BilibiliMediaIdKind.bvid,
        id: token,
        source: uri,
        page: page,
      );
    }

    final avMatch = _avPattern.firstMatch(token);
    if (avMatch != null) {
      return BilibiliMediaRef(
        kind: BilibiliMediaIdKind.aid,
        id: avMatch.group(1)!,
        source: uri,
        page: page,
      );
    }

    return BilibiliMediaRef(
      kind: BilibiliMediaIdKind.shortLink,
      id: token,
      source: uri,
      page: page,
    );
  }

  int? _parsePage(Uri uri) {
    final rawPage = uri.queryParameters['p'];
    if (rawPage == null || rawPage.isEmpty) {
      return null;
    }

    final parsed = int.tryParse(rawPage);
    if (parsed == null || parsed <= 0) {
      throw const BilibiliParseException(
        'The p query parameter must be a positive integer.',
      );
    }
    return parsed;
  }

  List<String> _nonEmptyPathSegments(Uri uri) {
    return uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  }

  bool _isBilibiliHost(String host) {
    return host == 'bilibili.com' || host.endsWith('.bilibili.com');
  }

  bool _isB23Host(String host) {
    return host == 'b23.tv' || host == 'www.b23.tv';
  }
}
