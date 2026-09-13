import 'online_stream.dart';

/// A provider-neutral video-only stream.
class OnlineVideoStream implements OnlineStream {
  OnlineVideoStream({
    required this.id,
    required this.url,
    List<Uri> backupUrls = const <Uri>[],
    Map<String, String> headers = const <String, String>{},
    required this.mimeType,
    this.qualityId,
    this.qualityLabel,
    this.width,
    this.height,
    this.fps,
    this.codec,
    this.bitrate,
    this.sizeInBytes,
    this.duration,
    this.expiresAt,
  }) : backupUrls = List<Uri>.unmodifiable(backupUrls),
       headers = Map<String, String>.unmodifiable(headers);

  final String id;
  final int? qualityId;
  final String? qualityLabel;
  final int? width;
  final int? height;
  final double? fps;

  @override
  final Uri url;

  @override
  final List<Uri> backupUrls;

  @override
  final Map<String, String> headers;

  @override
  final String mimeType;

  @override
  final String? codec;

  @override
  String? get rawCodec => codec;

  @override
  OnlineCodecFamily get codecFamily => OnlineCodecFamily.fromCodec(codec);

  @override
  final int? bitrate;

  @override
  final int? sizeInBytes;

  @override
  final Duration? duration;

  @override
  final DateTime? expiresAt;

  @override
  String toString() {
    return 'OnlineVideoStream($id, label=$qualityLabel, '
        '${width}x$height, codec=$codec)';
  }
}
