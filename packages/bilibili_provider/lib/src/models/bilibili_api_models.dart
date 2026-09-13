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

/// Internal Bilibili DASH video stream.
class BilibiliDashVideoStream {
  const BilibiliDashVideoStream({
    required this.url,
    required this.backupUrls,
    required this.mimeType,
    this.qualityId,
    this.qualityLabel,
    this.width,
    this.height,
    this.fps,
    this.codec,
    this.bitrate,
    this.sizeInBytes,
    this.expiresAt,
  });

  final Uri url;
  final List<Uri> backupUrls;
  final String mimeType;
  final int? qualityId;
  final String? qualityLabel;
  final int? width;
  final int? height;
  final double? fps;
  final String? codec;
  final int? bitrate;
  final int? sizeInBytes;
  final DateTime? expiresAt;
}

/// Internal Bilibili DASH audio stream.
class BilibiliDashAudioStream {
  const BilibiliDashAudioStream({
    required this.url,
    required this.backupUrls,
    required this.mimeType,
    this.qualityId,
    this.qualityLabel,
    this.sampleRate,
    this.channels,
    this.codec,
    this.bitrate,
    this.sizeInBytes,
    this.expiresAt,
  });

  final Uri url;
  final List<Uri> backupUrls;
  final String mimeType;
  final int? qualityId;
  final String? qualityLabel;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final int? bitrate;
  final int? sizeInBytes;
  final DateTime? expiresAt;
}

/// Internal Bilibili muxed fallback stream.
class BilibiliMuxedStream {
  const BilibiliMuxedStream({
    required this.url,
    required this.backupUrls,
    required this.mimeType,
    this.qualityId,
    this.qualityLabel,
    this.width,
    this.height,
    this.fps,
    this.sampleRate,
    this.channels,
    this.codec,
    this.bitrate,
    this.sizeInBytes,
    this.duration,
    this.expiresAt,
  });

  final Uri url;
  final List<Uri> backupUrls;
  final String mimeType;
  final int? qualityId;
  final String? qualityLabel;
  final int? width;
  final int? height;
  final double? fps;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final int? bitrate;
  final int? sizeInBytes;
  final Duration? duration;
  final DateTime? expiresAt;
}

/// Internal model for the Bilibili `x/player/playurl` response.
///
/// Stage 3 parses this into Bilibili-specific stream models. The provider then
/// maps those models to `OnlinePlaybackData`.
class BilibiliPlaybackResponse {
  const BilibiliPlaybackResponse({
    this.headers = const <String, String>{},
    this.videoStreams = const <BilibiliDashVideoStream>[],
    this.audioStreams = const <BilibiliDashAudioStream>[],
    this.muxedStreams = const <BilibiliMuxedStream>[],
    this.duration,
    this.expiresAt,
  });

  final Map<String, String> headers;
  final List<BilibiliDashVideoStream> videoStreams;
  final List<BilibiliDashAudioStream> audioStreams;
  final List<BilibiliMuxedStream> muxedStreams;
  final Duration? duration;
  final DateTime? expiresAt;

  bool get hasStreams =>
      videoStreams.isNotEmpty ||
      audioStreams.isNotEmpty ||
      muxedStreams.isNotEmpty;
}
