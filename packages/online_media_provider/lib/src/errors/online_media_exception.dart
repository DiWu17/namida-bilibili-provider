/// Base type for structured online-media provider failures.
///
/// `base` prevents external packages from implementing this type accidentally
/// while still allowing provider-specific subclasses such as
/// `BilibiliNotFoundException` to extend it.
abstract base class OnlineMediaException implements Exception {
  const OnlineMediaException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// A transport/network failure before a valid provider response was obtained.
final class OnlineMediaNetworkException extends OnlineMediaException {
  const OnlineMediaNetworkException(
    super.message, {
    this.statusCode,
    super.cause,
    super.stackTrace,
  });

  final int? statusCode;
}

/// The provider could not find the requested media.
final class OnlineMediaNotFoundException extends OnlineMediaException {
  const OnlineMediaNotFoundException(
    super.message, {
    this.platformErrorCode,
    super.cause,
    super.stackTrace,
  });

  final int? platformErrorCode;
}

/// The provider refused anonymous access or requires explicit authorization.
final class OnlineMediaAccessDeniedException extends OnlineMediaException {
  const OnlineMediaAccessDeniedException(
    super.message, {
    this.platformErrorCode,
    this.httpStatusCode,
    super.cause,
    super.stackTrace,
  });

  final int? platformErrorCode;
  final int? httpStatusCode;
}

/// The URL or content type is not supported by this provider.
final class OnlineMediaUnsupportedException extends OnlineMediaException {
  const OnlineMediaUnsupportedException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// The provider or a caller hit a rate limit.
final class OnlineMediaRateLimitException extends OnlineMediaException {
  const OnlineMediaRateLimitException(
    super.message, {
    this.retryAfter,
    super.cause,
    super.stackTrace,
  });

  final Duration? retryAfter;
}

/// A provider response was obtained but could not be parsed safely.
final class OnlineMediaParseException extends OnlineMediaException {
  const OnlineMediaParseException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
