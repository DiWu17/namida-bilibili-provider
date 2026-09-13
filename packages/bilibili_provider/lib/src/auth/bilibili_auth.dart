/// Optional explicit authentication/session hooks for Bilibili requests.
///
/// MVP playback must work anonymously. No credential extraction, QR login, or
/// password flow is implemented in the provider core.
abstract interface class BilibiliAuthProvider {
  /// Extra request headers that are safe to attach to API/CDN requests.
  ///
  /// Implementations must not log or expose cookie values.
  Map<String, String> get requestHeaders;

  /// Raw `Cookie` header value, or null for anonymous access.
  String? get cookieHeader;
}

/// Anonymous auth provider used by `BilibiliProvider.anonymous()`.
final class AnonymousBilibiliAuthProvider implements BilibiliAuthProvider {
  const AnonymousBilibiliAuthProvider();

  @override
  Map<String, String> get requestHeaders => const <String, String>{
    'Referer': 'https://www.bilibili.com/',
    'User-Agent': defaultBilibiliUserAgent,
  };

  @override
  String? get cookieHeader => null;
}

/// A caller-provided session for future authenticated access.
///
/// This type is intentionally simple for MVP; user-provided cookies are never
/// persisted or inspected by the package.
class BilibiliSession {
  const BilibiliSession({
    this.cookie,
    this.userAgent = defaultBilibiliUserAgent,
  });

  final String? cookie;
  final String userAgent;

  Map<String, String> get requestHeaders => <String, String>{
    'Referer': 'https://www.bilibili.com/',
    'User-Agent': userAgent,
  };

  String? get cookieHeader => cookie;
}

/// Auth provider backed by an explicit caller-created [BilibiliSession].
final class SessionBilibiliAuthProvider implements BilibiliAuthProvider {
  const SessionBilibiliAuthProvider(this.session);

  final BilibiliSession session;

  @override
  Map<String, String> get requestHeaders => session.requestHeaders;

  @override
  String? get cookieHeader => session.cookieHeader;
}

/// Browser-like user agent used for public/anonymous Bilibili requests.
const String defaultBilibiliUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Safari/537.36';
