import 'online_stream.dart';

/// A provider-neutral audio-only stream.
class OnlineAudioStream implements OnlineStream {
  OnlineAudioStream({
    required this.id,
    required this.url,
    List<Uri> backupUrls = const <Uri>[],
    Map<String, String> headers = const <String, String>{},
    required this.mimeType,
    this.qualityId,
    this.qualityLabel,
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
  String toString() {
    return 'OnlineAudioStream($id, label=$qualityLabel, codec=$codec)';
  }
}
