import '../auth/bilibili_auth.dart';
import '../errors/bilibili_exception.dart';
import '../models/bilibili_api_models.dart';

/// HTTP/API boundary for Bilibili.
///
/// The provider maps these platform models into provider-neutral DTOs. Keeping
/// HTTP code here lets future Bilibili API changes stay contained in this file
/// and its parser siblings.
class BilibiliClient {
  const BilibiliClient({
    this.auth = const AnonymousBilibiliAuthProvider(),
    this.debug = false,
  });

  final BilibiliAuthProvider auth;
  final bool debug;

  /// Fetches video metadata and part data for a BVID or `av` id.
  Future<BilibiliVideoInfo> getVideoInfo({required String id}) {
    throw const BilibiliUnsupportedContentException(
      'BilibiliClient.getVideoInfo is implemented in Stage 2.',
    );
  }

  /// Fetches the DASH playback response for a BVID and CID.
  Future<BilibiliPlaybackResponse> getPlayback({
    required String bvid,
    required String cid,
  }) {
    throw const BilibiliUnsupportedContentException(
      'BilibiliClient.getPlayback is implemented in Stage 3.',
    );
  }

  /// Resolves a b23.tv short URL while enforcing redirect limits.
  Future<Uri> resolveShortUrl(Uri shortUri) {
    throw const BilibiliUnsupportedContentException(
      'BilibiliClient.resolveShortUrl is implemented in Stage 2.',
    );
  }
}
