import 'online_audio_stream.dart';
import 'online_media.dart';
import 'online_muxed_stream.dart';
import 'online_video_stream.dart';

/// The complete playback result consumed by a player adapter.
class OnlinePlaybackData {
  OnlinePlaybackData({
    required this.media,
    List<OnlineAudioStream> audioStreams = const <OnlineAudioStream>[],
    List<OnlineVideoStream> videoStreams = const <OnlineVideoStream>[],
    List<OnlineMuxedStream> muxedStreams = const <OnlineMuxedStream>[],
    this.expiresAt,
  }) : audioStreams = List<OnlineAudioStream>.unmodifiable(audioStreams),
       videoStreams = List<OnlineVideoStream>.unmodifiable(videoStreams),
       muxedStreams = List<OnlineMuxedStream>.unmodifiable(muxedStreams);

  final OnlineMedia media;
  final List<OnlineAudioStream> audioStreams;
  final List<OnlineVideoStream> videoStreams;
  final List<OnlineMuxedStream> muxedStreams;

  /// Earliest known playback expiry for this result, if the provider can
  /// determine one. This supplements per-stream [OnlineStream.expiresAt].
  final DateTime? expiresAt;

  bool get hasStreams =>
      audioStreams.isNotEmpty ||
      videoStreams.isNotEmpty ||
      muxedStreams.isNotEmpty;

  @override
  String toString() {
    return 'OnlinePlaybackData(media=${media.id}, '
        'audio=${audioStreams.length}, video=${videoStreams.length}, '
        'muxed=${muxedStreams.length})';
  }
}
