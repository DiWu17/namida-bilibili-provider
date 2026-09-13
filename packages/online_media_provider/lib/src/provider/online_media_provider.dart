import '../models/online_media.dart';
import '../models/online_media_id.dart';
import '../models/online_options.dart';
import '../models/online_playback_data.dart';

/// Minimal contract a player adapter needs in order to consume an online media
/// provider without knowing platform-specific API types.
abstract interface class OnlineMediaProvider {
  /// Stable provider identifier, for example `bilibili`.
  String get providerId;

  /// Whether this provider recognizes [uri].
  bool canHandle(Uri uri);

  /// Resolves provider metadata, parts and part identifiers.
  Future<OnlineMedia> resolve(
    Uri uri, {
    OnlineMediaResolveOptions options = const OnlineMediaResolveOptions(),
  });

  /// Resolves playable audio/video stream URLs for [mediaId].
  ///
  /// A provider should re-resolve stream URLs on each call because CDN URLs are
  /// frequently time-limited.
  Future<OnlinePlaybackData> getPlayback(
    OnlineMediaId mediaId, {
    OnlinePlaybackOptions options = const OnlinePlaybackOptions(),
  });
}
