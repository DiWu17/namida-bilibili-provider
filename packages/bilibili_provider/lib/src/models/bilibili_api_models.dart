import 'bilibili_part.dart';

/// Internal Bilibili owner/uploader model.
class BilibiliOwner {
  const BilibiliOwner({required this.mid, required this.name, this.avatar});

  final int? mid;
  final String? name;
  final Uri? avatar;

  @override
  String toString() => 'BilibiliOwner($mid, $name)';
}

/// Internal model for the Bilibili `x/web-interface/view` response.
///
/// This type must stay inside the Bilibili package; callers only receive
/// provider-neutral `OnlineMedia` values.
class BilibiliVideoInfo {
  const BilibiliVideoInfo({
    required this.aid,
    required this.bvid,
    required this.title,
    this.description,
    this.thumbnail,
    this.duration,
    this.owner,
    this.parts = const <BilibiliPart>[],
  });

  final int aid;
  final String bvid;
  final String title;
  final String? description;
  final Uri? thumbnail;
  final Duration? duration;
  final BilibiliOwner? owner;
  final List<BilibiliPart> parts;

  @override
  String toString() => 'BilibiliVideoInfo($bvid, $title)';
}

/// Internal placeholder for the Bilibili DASH playback response.
///
/// Stage 3 replaces this with parseable DASH models while keeping the same
/// internal boundary.
class BilibiliPlaybackResponse {
  const BilibiliPlaybackResponse();
}
