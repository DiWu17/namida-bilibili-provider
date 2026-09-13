import '../auth/bilibili_auth.dart';
import 'bilibili_account_session.dart';

/// A [BilibiliAuthProvider] whose headers follow an active account session.
///
/// HTTP clients are usually constructed once and then reused across sign-in,
/// account switching and sign-out. Binding them to this provider means a single
/// [setSession] call updates every request they make afterwards.
///
/// Cookie values are never logged: [toString] is redacted, and the values are
/// only reachable through [cookieHeader] and [requestHeaders], which exist to be
/// handed to an HTTP client.
final class BilibiliAccountAuthProvider implements BilibiliAuthProvider {
  BilibiliAccountAuthProvider([BilibiliAccountSession? session])
    : _session = session ?? BilibiliAccountSession.anonymous;

  BilibiliAccountSession _session;

  /// The session this provider currently authorizes.
  BilibiliAccountSession get session => _session;

  /// Rebinds this provider to [session].
  ///
  /// Intended for the account layer; callers that mutate this directly must
  /// ensure cookies are never logged.
  void setSession(BilibiliAccountSession session) {
    _session = session;
  }

  @override
  Map<String, String> get requestHeaders => <String, String>{
    'Referer': 'https://www.bilibili.com/',
    'User-Agent': defaultBilibiliUserAgent,
  };

  @override
  String? get cookieHeader {
    final cookies = _session.cookies;
    if (cookies.isEmpty) {
      return null;
    }
    return cookies.cookieHeader;
  }

  /// Redacted representation. Never contains a cookie value.
  @override
  String toString() {
    return 'BilibiliAccountAuthProvider(accountId: ${_session.accountId}, '
        'anonymous: ${_session.isAnonymous})';
  }
}
