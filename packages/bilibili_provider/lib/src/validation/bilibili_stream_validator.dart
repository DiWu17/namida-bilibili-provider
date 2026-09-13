import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:online_media_provider/online_media_provider.dart';

/// Result of a lightweight HTTP range validation for one media stream.
class BilibiliStreamValidationResult {
  const BilibiliStreamValidationResult({
    required this.isPlayable,
    required this.bytesRead,
    this.statusCode,
    this.contentType,
    this.rangeSupported,
    this.reason,
    this.elapsed,
  });

  final bool isPlayable;
  final int bytesRead;
  final int? statusCode;
  final String? contentType;

  /// `true` for HTTP 206 range responses, `false` for ordinary HTTP 200
  /// fallbacks, and `null` when validation failed before a valid response.
  final bool? rangeSupported;

  final String? reason;
  final Duration? elapsed;

  @override
  String toString() {
    return 'BilibiliStreamValidationResult('
        'playable=$isPlayable, status=$statusCode, bytes=$bytesRead, '
        'range=$rangeSupported, reason=$reason)';
  }
}

/// Validates that an [OnlineStream] URL returns real media bytes using the
/// stream's own headers.
///
/// The validator requests only a small prefix:
///
/// ```http
/// Range: bytes=0-1023
/// ```
///
/// It accepts HTTP 206 and HTTP 200 (limited fallback), but always stops after
/// `maxBytes`. No full media download is performed.
class BilibiliStreamValidator {
  BilibiliStreamValidator({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration timeout;

  Future<BilibiliStreamValidationResult> validate(
    OnlineStream stream, {
    int maxBytes = 1024,
  }) async {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }

    final stopwatch = Stopwatch()..start();
    final rangeResult = await _attempt(
      stream,
      maxBytes: maxBytes,
      useRange: true,
    );

    final shouldRetryWithoutRange =
        !rangeResult.isPlayable &&
        (rangeResult.statusCode == 416 || rangeResult.statusCode == 501);
    if (!shouldRetryWithoutRange) {
      return rangeResult.withElapsed(stopwatch.elapsed);
    }

    final fallbackResult = await _attempt(
      stream,
      maxBytes: maxBytes,
      useRange: false,
    );
    return fallbackResult.withElapsed(stopwatch.elapsed);
  }

  Future<BilibiliStreamValidationResult> _attempt(
    OnlineStream stream, {
    required int maxBytes,
    required bool useRange,
  }) async {
    final request = http.Request('GET', stream.url);
    request.headers.addAll(stream.headers);
    if (useRange) {
      request.headers['Range'] = 'bytes=0-${maxBytes - 1}';
    }

    try {
      final response = await _httpClient.send(request).timeout(timeout);
      final bytes = await _readAtMost(
        response.stream,
        maxBytes,
      ).timeout(timeout);
      final statusCode = response.statusCode;
      final acceptedStatus = statusCode == 200 || statusCode == 206;
      final isPlayable = acceptedStatus && bytes.isNotEmpty;

      return BilibiliStreamValidationResult(
        isPlayable: isPlayable,
        bytesRead: bytes.length,
        statusCode: statusCode,
        contentType: response.headers['content-type'],
        rangeSupported: statusCode == 206,
        reason: isPlayable
            ? null
            : statusCode == 200 || statusCode == 206
            ? 'Response contained no media bytes.'
            : 'Unexpected HTTP $statusCode response.',
      );
    } on TimeoutException {
      return const BilibiliStreamValidationResult(
        isPlayable: false,
        bytesRead: 0,
        reason: 'Timed out while validating stream.',
      );
    } catch (error) {
      return BilibiliStreamValidationResult(
        isPlayable: false,
        bytesRead: 0,
        reason: 'Transport error: ${error.runtimeType}.',
      );
    }
  }

  Future<List<int>> _readAtMost(Stream<List<int>> stream, int maxBytes) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      final remaining = maxBytes - bytes.length;
      if (remaining <= 0) {
        break;
      }
      bytes.addAll(chunk.take(remaining));
      if (bytes.length >= maxBytes) {
        break;
      }
    }
    return bytes;
  }
}

extension on BilibiliStreamValidationResult {
  BilibiliStreamValidationResult withElapsed(Duration elapsed) {
    return BilibiliStreamValidationResult(
      isPlayable: isPlayable,
      bytesRead: bytesRead,
      statusCode: statusCode,
      contentType: contentType,
      rangeSupported: rangeSupported,
      reason: reason,
      elapsed: elapsed,
    );
  }
}
