/// Platform-specific description of one Bilibili page/part.
class BilibiliPart {
  const BilibiliPart({
    required this.cid,
    required this.page,
    required this.title,
    this.duration,
  });

  /// Bilibili CID (content id) for this part.
  final String cid;

  /// 1-based page number as shown by Bilibili.
  final int page;

  final String title;

  final Duration? duration;

  @override
  String toString() => 'BilibiliPart(page=$page, cid=$cid, title=$title)';
}
