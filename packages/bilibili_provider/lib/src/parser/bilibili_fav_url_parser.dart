import '../errors/bilibili_exception.dart';

/// Kind of favorite list addressed by a `favlist` link.
enum BilibiliFavListType {
  /// A folder the user created (`ftype=create`, the Bilibili default).
  created('create'),

  /// A folder the user collected from somebody else (`ftype=collect`).
  collected('collect');

  const BilibiliFavListType(this.platformValue);

  /// Value of the `ftype` query parameter.
  final String platformValue;

  static BilibiliFavListType? fromPlatformValue(String? raw) {
    if (raw == null || raw.isEmpty) {
      return created;
    }
    final normalized = raw.trim().toLowerCase();
    for (final type in BilibiliFavListType.values) {
      if (type.platformValue == normalized) {
        return type;
      }
    }
    return null;
  }
}

/// Parsed `space.bilibili.com` favorite-list link.
///
/// This is not a video reference: a favorite list is a container, so it is kept
/// out of [BilibiliUrlParser] and `BilibiliProvider.canHandle` on purpose.
class BilibiliFavListRef {
  const BilibiliFavListRef({
    required this.mid,
    required this.mediaId,
    required this.type,
    required this.source,
  }) : assert(mid > 0),
       assert(mediaId > 0);

  /// Owner mid from the URL path.
  final int mid;

  /// Folder id from the `fid` query parameter, used as `media_id` by the API.
  final int mediaId;

  final BilibiliFavListType type;

  /// Original URI this reference was parsed from.
  final Uri source;

  @override
  bool operator ==(Object other) {
    return other is BilibiliFavListRef &&
        other.mid == mid &&
        other.mediaId == mediaId &&
        other.type == type &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(mid, mediaId, type, source);

  @override
  String toString() =>
      'BilibiliFavListRef(mid: $mid, mediaId: $mediaId, type: ${type.name})';
}

/// Parses Bilibili favorite-list links without performing network I/O.
///
/// Supported shapes:
///
/// - `https://space.bilibili.com/<mid>/favlist?fid=<id>&ftype=create`
/// - `https://space.bilibili.com/<mid>/favlist?fid=<id>` (`ftype` defaults to
///   [BilibiliFavListType.created])
/// - the same paths with a legacy `#/...` fragment that carries the query.
class BilibiliFavListUrlParser {
  const BilibiliFavListUrlParser();

  /// Path segment that identifies a favorite-list link.
  static const String pathSegment = 'favlist';

  /// Returns true when [uri] is a supported favorite-list link.
  bool canHandle(Uri uri) {
    try {
      parse(uri);
      return true;
    } on BilibiliException {
      return false;
    }
  }

  /// Parses a favorite-list link or throws a structured [BilibiliException].
  BilibiliFavListRef parse(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const BilibiliUnsupportedContentException(
        'Only http and https Bilibili favorite-list URLs are supported.',
      );
    }

    final host = uri.host.toLowerCase();
    if (host != 'bilibili.com' && !host.endsWith('.bilibili.com')) {
      throw const BilibiliUnsupportedContentException(
        'URL host is not a supported Bilibili host.',
      );
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length != 2 || segments[1].toLowerCase() != pathSegment) {
      throw const BilibiliUnsupportedContentException(
        'Only /<mid>/favlist Bilibili favorite-list URLs are supported.',
      );
    }

    final mid = int.tryParse(segments[0]);
    if (mid == null || mid <= 0) {
      throw const BilibiliParseException(
        'Bilibili favorite-list URL must contain a numeric mid.',
      );
    }

    final query = mergedQueryParameters(uri);
    final rawFid = query['fid'];
    final mediaId = rawFid == null ? null : int.tryParse(rawFid.trim());
    if (mediaId == null || mediaId <= 0) {
      throw const BilibiliParseException(
        'Bilibili favorite-list URL must contain a positive fid.',
      );
    }

    final type = BilibiliFavListType.fromPlatformValue(query['ftype']);
    if (type == null) {
      throw BilibiliUnsupportedContentException(
        'Unsupported Bilibili favorite-list ftype '
        '"${query['ftype']}".',
      );
    }

    return BilibiliFavListRef(
      mid: mid,
      mediaId: mediaId,
      type: type,
      source: uri,
    );
  }

  /// Builds a canonical `favlist` URI for [ref].
  Uri buildUri(BilibiliFavListRef ref) {
    return Uri.https('space.bilibili.com', '/${ref.mid}/$pathSegment', {
      'fid': '${ref.mediaId}',
      'ftype': ref.type.platformValue,
    });
  }

  /// Merges real query parameters with a legacy `#/...?a=b` fragment query.
  static Map<String, String> mergedQueryParameters(Uri uri) {
    final parameters = <String, String>{...uri.queryParameters};

    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      return parameters;
    }

    final queryIndex = fragment.indexOf('?');
    final candidate = queryIndex >= 0
        ? fragment.substring(queryIndex + 1)
        : (fragment.contains('=') ? fragment : '');
    if (candidate.isEmpty) {
      return parameters;
    }

    try {
      for (final entry in Uri.splitQueryString(candidate).entries) {
        parameters.putIfAbsent(entry.key, () => entry.value);
      }
    } on FormatException {
      // A malformed legacy fragment is ignored; real query parameters still win.
    }
    return parameters;
  }
}
