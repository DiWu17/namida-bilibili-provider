import '../account/bilibili_cookies.dart';

/// A freshly generated Bilibili login QR code.
///
/// Both fields are single-use login tickets: [uri] is the content the user scans
/// and [qrcodeKey] is what the client polls with. Treat them as sensitive for the
/// short time they are valid, and never log them — [toString] is redacted.
class BilibiliQrLogin {
  const BilibiliQrLogin({required this.qrcodeKey, required this.uri});

  /// Polling key for this ticket. Never log it.
  final String qrcodeKey;

  /// Content to render as the QR image. Never log it.
  final Uri uri;

  @override
  String toString() => 'BilibiliQrLogin(<redacted>)';
}

/// Progress of a scanned login, mirroring the states the platform reports.
enum BilibiliQrLoginStage {
  /// The QR code was issued and is waiting to be scanned (`86101`).
  pending,

  /// The user scanned the code and still has to confirm on their device
  /// (`86090`).
  scanned,

  /// The user confirmed; the session cookies are available (`0`).
  confirmed,

  /// The ticket expired before it was confirmed (`86038`).
  expired,

  /// The platform reported a different state, or the response was unusable.
  failed,
}

/// One observation of a QR login attempt.
///
/// Carries no QR content or cookie values in [toString].
class BilibiliQrLoginStatus {
  const BilibiliQrLoginStatus({
    required this.stage,
    this.login,
    this.message,
    this.cookies,
    this.refreshToken,
  });

  final BilibiliQrLoginStage stage;

  /// The ticket this status belongs to, so a UI can render the QR image from the
  /// same value it displays progress from.
  ///
  /// Null only when a caller constructs a status by hand.
  final BilibiliQrLogin? login;

  /// Short platform message, or a fixed explanation when the platform reply was
  /// unusable. Never contains credential material.
  final String? message;

  /// Session cookies, present only for [BilibiliQrLoginStage.confirmed].
  final BilibiliCookies? cookies;

  /// Platform refresh token, when reported. Never log it.
  final String? refreshToken;

  bool get isConfirmed => stage == BilibiliQrLoginStage.confirmed;

  /// Whether the attempt cannot produce a session any more.
  bool get isTerminal =>
      stage == BilibiliQrLoginStage.confirmed ||
      stage == BilibiliQrLoginStage.expired ||
      stage == BilibiliQrLoginStage.failed;

  /// Returns this status with [login] attached.
  BilibiliQrLoginStatus withLogin(BilibiliQrLogin login) {
    return BilibiliQrLoginStatus(
      stage: stage,
      login: login,
      message: message,
      cookies: cookies,
      refreshToken: refreshToken,
    );
  }

  /// Redacted representation. Never contains cookies, the refresh token, or the
  /// QR ticket.
  @override
  String toString() {
    final parts = <String>[stage.name];

    final cookies = this.cookies;
    if (cookies != null) {
      parts.add(cookies.redactedSummary);
      if (!cookies.hasCsrfToken) {
        parts.add('no csrf token');
      }
    }

    final message = this.message;
    if (message != null) {
      parts.add('message: $message');
    }

    return 'BilibiliQrLoginStatus(${parts.join(', ')})';
  }
}
