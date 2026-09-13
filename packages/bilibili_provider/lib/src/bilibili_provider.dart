import 'package:online_media_provider/online_media_provider.dart';

import 'auth/bilibili_auth.dart';
import 'client/bilibili_client.dart';
import 'errors/bilibili_exception.dart';
import 'parser/bilibili_metadata_parser.dart';
import 'parser/bilibili_url_parser.dart';

/// Public Bilibili online media provider.
///
/// This class is intentionally independent from Namida and YoutiPie. It exposes
/// only the provider-neutral [OnlineMediaProvider] contract.
class BilibiliProvider implements OnlineMediaProvider {
  BilibiliProvider({
    BilibiliClient? client,
    BilibiliUrlParser? urlParser,
    BilibiliMetadataParser? metadataParser,
    BilibiliAuthProvider? auth,
    bool debug = false,
  }) : _client =
           client ??
           BilibiliClient(
             auth: auth ?? const AnonymousBilibiliAuthProvider(),
             debug: debug,
           ),
       _urlParser = urlParser ?? const BilibiliUrlParser(),
       _metadataParser = metadataParser ?? const BilibiliMetadataParser(),
       debug = debug;

  /// Explicit anonymous constructor mirroring the public provider contract.
  BilibiliProvider.anonymous({
    BilibiliClient? client,
    BilibiliUrlParser? urlParser,
    BilibiliMetadataParser? metadataParser,
    bool debug = false,
  }) : this(
         client: client,
         urlParser: urlParser,
         metadataParser: metadataParser,
         auth: const AnonymousBilibiliAuthProvider(),
         debug: debug,
       );

  final BilibiliClient _client;
  final BilibiliUrlParser _urlParser;
  final BilibiliMetadataParser _metadataParser;

  /// Enables debug logging in future stages. It must never log credentials.
  final bool debug;

  /// The HTTP/API client used by this provider.
  ///
  /// Exposed to keep the boundary inspectable/testable. Callers should normally
  /// use the provider-neutral methods instead.
  BilibiliClient get client => _client;

  @override
  String get providerId => 'bilibili';

  @override
  bool canHandle(Uri uri) => _urlParser.canHandle(uri);

  @override
  Future<OnlineMedia> resolve(
    Uri uri, {
    OnlineMediaResolveOptions options = const OnlineMediaResolveOptions(),
  }) async {
    var ref = _urlParser.parse(uri);

    if (ref.isShortLink) {
      final resolvedUri = await _client.resolveShortUrl(uri);
      ref = _urlParser.parse(resolvedUri);
      if (ref.isShortLink) {
        throw const BilibiliParseException(
          'Short-link resolution did not produce a canonical Bilibili URL.',
        );
      }
    }

    final preferredPartIndex = options.preferredPartIndex;
    if (preferredPartIndex != null && preferredPartIndex < 0) {
      throw const BilibiliParseException(
        'preferredPartIndex must not be negative.',
      );
    }

    final info = await _client.getVideoInfo(id: ref.platformVideoId);
    final selectedPage =
        ref.page ??
        (preferredPartIndex == null ? null : preferredPartIndex + 1);

    return _metadataParser.toOnlineMedia(info, selectedPage: selectedPage);
  }

  @override
  Future<OnlinePlaybackData> getPlayback(
    OnlineMediaId mediaId, {
    OnlinePlaybackOptions options = const OnlinePlaybackOptions(),
  }) {
    throw const BilibiliUnsupportedContentException(
      'Bilibili DASH playback resolution is implemented in Stage 3.',
    );
  }
}
