/// Coarse codec family derived from the raw codec string.
enum OnlineCodecFamily {
  avc,
  hevc,
  av1,
  aac,
  opus,
  unknown;

  /// Best-effort mapping from a raw codec string such as `avc1.640028`.
  ///
  /// The raw value must always remain available through [OnlineStream.rawCodec]
  /// / [OnlineStream.codec]. This helper only exists for UI grouping.
  static OnlineCodecFamily fromCodec(String? codec) {
    if (codec == null || codec.trim().isEmpty) {
      return OnlineCodecFamily.unknown;
    }

    final normalized = codec.toLowerCase();
    if (normalized.contains('avc') || normalized.contains('h264')) {
      return OnlineCodecFamily.avc;
    }
    if (normalized.contains('hev') ||
        normalized.contains('hvc') ||
        normalized.contains('h265')) {
      return OnlineCodecFamily.hevc;
    }
    if (normalized.contains('av01') || normalized == 'av1') {
      return OnlineCodecFamily.av1;
    }
    if (normalized.contains('mp4a') || normalized.contains('aac')) {
      return OnlineCodecFamily.aac;
    }
    if (normalized.contains('opus')) {
      return OnlineCodecFamily.opus;
    }
    return OnlineCodecFamily.unknown;
  }
}

/// Provider-neutral description of a single media stream.
///
/// [url] and [backupUrls] must be used together with [headers]. In particular,
/// Bilibili CDN requests commonly need a `Referer`, `User-Agent` and sometimes
/// a `Cookie` header.
abstract interface class OnlineStream {
  Uri get url;

  List<Uri> get backupUrls;

  Map<String, String> get headers;

  String get mimeType;

  /// Raw codec string, for example `avc1.640028` or `mp4a.40.2`.
  String? get codec;

  /// Explicit alias for [codec], preserving the raw codec value.
  String? get rawCodec;

  OnlineCodecFamily get codecFamily;

  int? get bitrate;

  int? get sizeInBytes;

  Duration? get duration;

  DateTime? get expiresAt;
}

/// Convenience helpers for [OnlineStream].
extension OnlineStreamExpiry on OnlineStream {
  /// Whether [expiresAt] is known and already in the past.
  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now());
  }
}
