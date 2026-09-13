import 'bilibili_cookies.dart';

/// Result of validating the active cookie jar against Bilibili.
enum BilibiliSessionState {
  /// No cookies were provided, so requests run anonymously.
  anonymous,

  /// The server accepted the cookies and reports a signed-in account.
  authenticated,

  /// Cookies were provided but the server reports "not signed in". The jar
  /// should be replaced through a new explicit sign-in.
  expired,

  /// The server rejected the csrf token, so write requests cannot proceed.
  csrfInvalid,

  /// Not checked yet, or the check could not reach a verdict.
  unknown,
}

/// Outcome of a cookie validity check.
///
/// Carries no cookie material, so it is safe to log, store in UI state, or
/// include in a report.
class BilibiliCookieValidity {
  const BilibiliCookieValidity({
    required this.state,
    this.checkedAt,
    this.platformErrorCode,
    this.message,
  });

  /// Anonymous state for a jar that was never checked.
  static const BilibiliCookieValidity unchecked = BilibiliCookieValidity(
    state: BilibiliSessionState.unknown,
  );

  final BilibiliSessionState state;

  /// When the verdict was produced, when known.
  final DateTime? checkedAt;

  /// Bilibili platform code that produced the verdict, when known.
  final int? platformErrorCode;

  /// Short platform/transport message. Never contains cookie material.
  final String? message;

  bool get isAuthenticated => state == BilibiliSessionState.authenticated;

  bool get isAnonymous => state == BilibiliSessionState.anonymous;

  /// Whether a new explicit sign-in is required before authenticated APIs work.
  bool get requiresSignIn {
    return state == BilibiliSessionState.expired ||
        state == BilibiliSessionState.csrfInvalid;
  }

  @override
  String toString() {
    return 'BilibiliCookieValidity(${state.name}'
        '${platformErrorCode == null ? '' : ', code: $platformErrorCode'})';
  }
}

/// One Bilibili account known to the account layer.
///
/// A session is a cookie jar plus the profile fields the account layer has
/// already learned about it. Cookies are only ever obtainable from the caller
/// or from an explicit sign-in, and [toString] is redacted.
class BilibiliAccountSession {
  const BilibiliAccountSession({
    required this.accountId,
    required this.cookies,
    this.name,
    this.avatar,
    this.isAnonymous = false,
  });

  /// The anonymous session used when no account is active.
  static final BilibiliAccountSession anonymous = BilibiliAccountSession(
    accountId: anonymousAccountId,
    cookies: BilibiliCookies.empty,
    isAnonymous: true,
  );

  /// Identifier used by the anonymous session.
  static const String anonymousAccountId = 'anonymous';

  /// Stable identifier: the numeric mid for signed-in accounts.
  final String accountId;

  final BilibiliCookies cookies;

  /// Display name, when the account layer has fetched it.
  final String? name;

  /// Avatar URI, when the account layer has fetched it.
  final Uri? avatar;

  /// Whether this session represents anonymous access.
  final bool isAnonymous;

  /// Numeric mid, or null for the anonymous session.
  int? get mid {
    if (isAnonymous) {
      return null;
    }
    final raw = cookies.userId;
    if (raw != null) {
      return raw;
    }
    return int.tryParse(accountId);
  }

  /// Whether a session token is present. Does not prove the token is accepted.
  bool get hasSessionToken => !isAnonymous && cookies.hasSessionToken;

  BilibiliAccountSession copyWith({
    String? accountId,
    BilibiliCookies? cookies,
    String? name,
    Uri? avatar,
  }) {
    return BilibiliAccountSession(
      accountId: accountId ?? this.accountId,
      cookies: cookies ?? this.cookies,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      isAnonymous: isAnonymous,
    );
  }

  /// Redacted representation. Never contains a cookie value.
  @override
  String toString() {
    return 'BilibiliAccountSession(accountId: $accountId, '
        'name: $name, anonymous: $isAnonymous, '
        'cookies: ${cookies.redactedSummary})';
  }
}
