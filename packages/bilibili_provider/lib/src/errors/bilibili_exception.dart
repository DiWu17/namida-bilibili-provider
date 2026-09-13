import 'package:online_media_provider/online_media_provider.dart';

/// Base class for structured Bilibili provider failures.
abstract base class BilibiliException extends OnlineMediaException {
  const BilibiliException(
    super.message, {
    this.httpStatusCode,
    this.platformErrorCode,
    super.cause,
    super.stackTrace,
  });

  /// HTTP status associated with the failure, when available.
  final int? httpStatusCode;

  /// Bilibili API code field, when available.
  final int? platformErrorCode;
}

final class BilibiliNetworkException extends BilibiliException {
  const BilibiliNetworkException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

final class BilibiliNotFoundException extends BilibiliException {
  const BilibiliNotFoundException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

final class BilibiliAccessDeniedException extends BilibiliException {
  const BilibiliAccessDeniedException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

/// The caller is not signed in, the session expired, or the csrf token needed
/// for a write request is missing/rejected.
///
/// Instances must never carry cookie, `SESSDATA`, or csrf values in [message].
final class BilibiliAuthenticationException extends BilibiliException {
  const BilibiliAuthenticationException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

/// A non-zero Bilibili API code that does not map to a more specific failure.
final class BilibiliApiException extends BilibiliException {
  const BilibiliApiException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

final class BilibiliParseException extends BilibiliException {
  const BilibiliParseException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

final class BilibiliUnsupportedContentException extends BilibiliException {
  const BilibiliUnsupportedContentException(
    super.message, {
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });
}

final class BilibiliRateLimitException extends BilibiliException {
  const BilibiliRateLimitException(
    super.message, {
    this.retryAfter,
    super.httpStatusCode,
    super.platformErrorCode,
    super.cause,
    super.stackTrace,
  });

  final Duration? retryAfter;
}
