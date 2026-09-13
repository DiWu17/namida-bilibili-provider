import 'dart:convert';

import '../errors/bilibili_exception.dart';

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

    final code = asInt(envelope['code']);
    final message =
        asString(envelope['message']) ??
        asString(envelope['msg']) ??
        'Unknown Bilibili API error.';

    if (code != null && code != 0) {
      throw exceptionForApiCode(code: code, message: message);
    }

    final data = asMap(envelope['data']);
    if (data == null) {
      throw BilibiliParseException('$operation returned no data object.');
    }
    return data;
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
