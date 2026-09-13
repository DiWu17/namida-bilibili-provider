/// Platform kind represented by a parsed Bilibili URL.
enum BilibiliMediaIdKind {
  /// A BVID such as `BV1xx411c7mD`.
  bvid,

  /// A numeric AV id, stored without the `av` prefix.
  aid,

  /// A short URL token such as `https://b23.tv/abc123`.
  shortLink,
}

/// Internal representation produced by [BilibiliUrlParser].
///
/// This is a platform-specific model and must not leak through the public
/// provider-neutral API as a replacement for `OnlineMediaId`.
class BilibiliMediaRef {
  const BilibiliMediaRef({
    required this.kind,
    required this.id,
    required this.source,
    this.page,
  }) : assert(id != '');

  final BilibiliMediaIdKind kind;

  /// BVID, numeric aid (without `av`), or short-link token.
  final String id;

  /// Original URI used to create this reference.
  final Uri source;

  /// Optional 1-based page (`p` query parameter) from the original URL.
  final int? page;

  bool get isShortLink => kind == BilibiliMediaIdKind.shortLink;

  /// Returns `av<id>` for AV references and [id] otherwise.
  String get platformVideoId {
    return kind == BilibiliMediaIdKind.aid ? 'av$id' : id;
  }

  @override
  bool operator ==(Object other) {
    return other is BilibiliMediaRef &&
        other.kind == kind &&
        other.id == id &&
        other.source == source &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(kind, id, source, page);

  @override
  String toString() => 'BilibiliMediaRef($kind:$id, page=$page)';
}
