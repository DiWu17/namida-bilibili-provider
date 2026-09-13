import 'online_stream.dart';

/// A muxed audio+video stream returned by providers that expose one.
///
/// Bilibili DASH support should prefer separate [OnlineAudioStream] and
/// [OnlineVideoStream] values. This type is deliberately not required for the
/// MVP and must never replace the split DASH model.
class OnlineMuxedStream implements OnlineStream {
  OnlineMuxedStream({
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
    this.sampleRate,
    this.channels,
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
  final int? sampleRate;
  final int? channels;

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
  String toString() => 'OnlineMuxedStream($id, label=$qualityLabel)';
}
