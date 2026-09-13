import 'dart:convert';

import '../errors/bilibili_exception.dart';

/// Decoded Bilibili API envelope:
///
/// ```json
/// { "code": 0, "message": "0", "data": { ... } }
/// ```
///
/// Unlike [BilibiliApiResponse.decodeData] this keeps the raw platform [code]
/// so account callers can treat "not signed in" as a state instead of an error.
class BilibiliApiEnvelope {
  const BilibiliApiEnvelope({
    required this.code,
    required this.message,
    this.data,
  });

  /// Platform code, or null when the response contained no usable code.
  final int? code;

  /// Platform message. Never contains credentials.
  final String message;

  /// Raw `data` object, when the response carried one.
  final Map<String, Object?>? data;

  /// Whether the platform reported success.
  bool get isOk => code == null || code == 0;

  @override
  String toString() => 'BilibiliApiEnvelope(code: $code)';
}

/// Decodes the common Bilibili API envelope:
///
/// ```json
/// { "code": 0, "message": "0", "data": { ... } }
/// ```
///
/// Only the `data` map is returned. Non-zero platform codes are converted to
/// structured [BilibiliException]s so callers never parse error strings.
class BilibiliApiResponse {
  const BilibiliApiResponse._();

  static Map<String, Object?> decodeData(
    String body, {
    required String operation,
  }) {
    final envelope = decodeEnvelope(body, operation: operation);

    final code = envelope.code;
    if (code != null && code != 0) {
      throw exceptionForApiCode(code: code, message: envelope.message);
    }

    final data = envelope.data;
    if (data == null) {
      throw BilibiliParseException('$operation returned no data object.');
    }
    return data;
  }

  /// Decodes the outer envelope without rejecting non-zero platform codes.
  ///
  /// Account endpoints such as `x/web-interface/nav` report "not signed in" as
  /// a non-zero code that is a normal state rather than a failure, so the
  /// caller must be able to inspect [BilibiliApiEnvelope.code] itself.
  static BilibiliApiEnvelope decodeEnvelope(
    String body, {
    required String operation,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (error, stackTrace) {
      throw BilibiliParseException(
        '$operation returned invalid JSON.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    final envelope = asMap(decoded);
    if (envelope == null) {
      throw BilibiliParseException(
        '$operation returned a JSON value that is not an object.',
      );
    }

    return BilibiliApiEnvelope(
      code: asInt(envelope['code']),
      message:
          asString(envelope['message']) ??
          asString(envelope['msg']) ??
          'Unknown Bilibili API error.',
      data: asMap(envelope['data']),
    );
  }

  static BilibiliException exceptionForApiCode({
    required int code,
    required String message,
    int? httpStatusCode,
  }) {
    switch (code) {
      case -404:
      case 404:
        return BilibiliNotFoundException(
          message,
          httpStatusCode: httpStatusCode,
          platformErrorCode: code,
        );
      case -401:
      case -403:
      case 62002:
      case 62004:
        return BilibiliAccessDeniedException(
          message,
          httpStatusCode: httpStatusCode,
          platformErrorCode: code,
        );
      case -101:
      case -111:
        return BilibiliAuthenticationException(
          message,
          httpStatusCode: httpStatusCode,
          platformErrorCode: code,
        );
      case -509:
      case -799:
        return BilibiliRateLimitException(
          message,
          httpStatusCode: httpStatusCode,
          platformErrorCode: code,
        );
      default:
        return BilibiliApiException(
          message,
          httpStatusCode: httpStatusCode,
          platformErrorCode: code,
        );
    }
  }

  static Map<String, Object?>? asMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
    }
    return null;
  }

  static List<Object?>? asList(Object? value) {
    if (value is List<Object?>) {
      return value;
    }
    return null;
  }

  static int? asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static String? asString(Object? value) {
    return value is String ? value : null;
  }

  static bool? asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  /// Parses a Unix timestamp in seconds, ignoring values that are not a usable
  /// moment in time (deleted resources often report `0`).
  ///
  /// The result is UTC so parsing is independent of the machine time zone.
  static DateTime? asDateTimeSeconds(Object? value) {
    final seconds = asInt(value);
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static Uri? asUri(Object? value) {
    final raw = asString(value);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null || !parsed.hasScheme) {
      return null;
    }
    return parsed;
  }

  static Duration? asDurationSeconds(Object? value) {
    final seconds = asDouble(value);
    if (seconds == null || seconds.isNaN || seconds.isInfinite || seconds < 0) {
      return null;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }
}
