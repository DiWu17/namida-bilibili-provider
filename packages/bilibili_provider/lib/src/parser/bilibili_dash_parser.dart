import 'package:online_media_provider/online_media_provider.dart';

import '../models/bilibili_api_models.dart';
import 'bilibili_api_response.dart';
import 'bilibili_frame_rate.dart';

/// Parses Bilibili `x/player/playurl` responses and maps them to the
/// provider-neutral playback contract.
class BilibiliDashParser {
  const BilibiliDashParser();

  static const Map<int, String> _fallbackQualityLabels = <int, String>{
    127: '8K',
    126: 'Dolby Vision',
    125: 'HDR',
    120: '4K',
    116: '1080P60',
    112: '1080P+',
    80: '1080P',
    74: '720P60',
    64: '720P',
    32: '480P',
    16: '360P',
    30280: '192K',
    30232: '132K',
    30216: '64K',
    30250: 'Dolby Atmos',
    30251: 'Hi-Res Lossless',
  };

  /// Parses a full Bilibili playurl response body.
  BilibiliPlaybackResponse parsePlaybackResponse(
    String body, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili playurl API',
    );
    return parsePlaybackData(data, headers: headers);
  }

  /// Parses the `data` object from `x/player/playurl`.
  BilibiliPlaybackResponse parsePlaybackData(
    Map<String, Object?> data, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final qualityLabels = _parseQualityLabels(data);
    final dash = BilibiliApiResponse.asMap(data['dash']);
    final duration =
        BilibiliApiResponse.asDurationSeconds(dash?['duration']) ??
        _durationFromMilliseconds(data['timelength']);

    final videoStreams = _parseVideoStreams(dash?['video'], qualityLabels);
    final audioStreams = _parseAudioStreams(dash?['audio'], qualityLabels);
    final muxedStreams = _parseMuxedStreams(data, qualityLabels, duration);

    final knownExpiries = <DateTime?>[
      for (final stream in videoStreams) stream.expiresAt,
      for (final stream in audioStreams) stream.expiresAt,
      for (final stream in muxedStreams) stream.expiresAt,
    ];

    return BilibiliPlaybackResponse(
      headers: Map<String, String>.unmodifiable(headers),
      videoStreams: List<BilibiliDashVideoStream>.unmodifiable(videoStreams),
      audioStreams: List<BilibiliDashAudioStream>.unmodifiable(audioStreams),
      muxedStreams: List<BilibiliMuxedStream>.unmodifiable(muxedStreams),
      duration: duration,
      expiresAt: _earliestExpiry(knownExpiries),
    );
  }

  /// Maps internal Bilibili streams to provider-neutral playback data.
  OnlinePlaybackData toOnlinePlaybackData(
    BilibiliPlaybackResponse response,
    OnlineMedia media, {
    OnlinePlaybackOptions options = const OnlinePlaybackOptions(),
  }) {
    final videoStreams = <OnlineVideoStream>[];
    for (var index = 0; index < response.videoStreams.length; index++) {
      final stream = response.videoStreams[index];
      videoStreams.add(
        OnlineVideoStream(
          id: 'video_${stream.qualityId ?? index}',
          qualityId: stream.qualityId,
          qualityLabel: stream.qualityLabel,
          width: stream.width,
          height: stream.height,
          fps: stream.fps,
          url: stream.url,
          backupUrls: stream.backupUrls,
          headers: response.headers,
          mimeType: stream.mimeType,
          codec: stream.codec,
          bitrate: stream.bitrate,
          sizeInBytes: stream.sizeInBytes,
          duration: response.duration,
          expiresAt: stream.expiresAt,
        ),
      );
    }

    final audioStreams = <OnlineAudioStream>[];
    for (var index = 0; index < response.audioStreams.length; index++) {
      final stream = response.audioStreams[index];
      audioStreams.add(
        OnlineAudioStream(
          id: 'audio_${stream.qualityId ?? index}',
          qualityId: stream.qualityId,
          qualityLabel: stream.qualityLabel,
          sampleRate: stream.sampleRate,
          channels: stream.channels,
          url: stream.url,
          backupUrls: stream.backupUrls,
          headers: response.headers,
          mimeType: stream.mimeType,
          codec: stream.codec,
          bitrate: stream.bitrate,
          sizeInBytes: stream.sizeInBytes,
          duration: response.duration,
          expiresAt: stream.expiresAt,
        ),
      );
    }

    final muxedStreams = <OnlineMuxedStream>[];
    for (var index = 0; index < response.muxedStreams.length; index++) {
      final stream = response.muxedStreams[index];
      muxedStreams.add(
        OnlineMuxedStream(
          id: 'muxed_${stream.qualityId ?? index}',
          qualityId: stream.qualityId,
          qualityLabel: stream.qualityLabel,
          width: stream.width,
          height: stream.height,
          fps: stream.fps,
          sampleRate: stream.sampleRate,
          channels: stream.channels,
          url: stream.url,
          backupUrls: stream.backupUrls,
          headers: response.headers,
          mimeType: stream.mimeType,
          codec: stream.codec,
          bitrate: stream.bitrate,
          sizeInBytes: stream.sizeInBytes,
          duration: stream.duration ?? response.duration,
          expiresAt: stream.expiresAt,
        ),
      );
    }

    return OnlinePlaybackData(
      media: media,
      audioStreams: audioStreams,
      videoStreams: videoStreams,
      muxedStreams: muxedStreams,
      expiresAt: response.expiresAt,
    );
  }

  List<BilibiliDashVideoStream> _parseVideoStreams(
    Object? rawStreams,
    Map<int, String> qualityLabels,
  ) {
    final streams = <BilibiliDashVideoStream>[];
    for (final rawStream
        in BilibiliApiResponse.asList(rawStreams) ?? const <Object?>[]) {
      final stream = BilibiliApiResponse.asMap(rawStream);
      if (stream == null) {
        continue;
      }

      final url = _primaryUri(stream);
      if (url == null) {
        continue;
      }

      final backupUrls = _backupUris(stream);
      final qualityId = BilibiliApiResponse.asInt(stream['id']);
      streams.add(
        BilibiliDashVideoStream(
          url: url,
          backupUrls: backupUrls,
          mimeType:
              BilibiliApiResponse.asString(stream['mimeType']) ??
              BilibiliApiResponse.asString(stream['mime_type']) ??
              'video/mp4',
          qualityId: qualityId,
          qualityLabel: qualityLabels[qualityId],
          width: BilibiliApiResponse.asInt(stream['width']),
          height: BilibiliApiResponse.asInt(stream['height']),
          fps: parseFrameRate(
            BilibiliApiResponse.asString(stream['frameRate']) ??
                BilibiliApiResponse.asString(stream['frame_rate']),
          ),
          codec:
              BilibiliApiResponse.asString(stream['codecs']) ??
              BilibiliApiResponse.asString(stream['codec']),
          bitrate:
              BilibiliApiResponse.asInt(stream['bandwidth']) ??
              BilibiliApiResponse.asInt(stream['bitrate']),
          sizeInBytes: BilibiliApiResponse.asInt(stream['size']),
          expiresAt: _expiryForStream(url, backupUrls),
        ),
      );
    }
    return streams;
  }

  List<BilibiliDashAudioStream> _parseAudioStreams(
    Object? rawStreams,
    Map<int, String> qualityLabels,
  ) {
    final streams = <BilibiliDashAudioStream>[];
    for (final rawStream
        in BilibiliApiResponse.asList(rawStreams) ?? const <Object?>[]) {
      final stream = BilibiliApiResponse.asMap(rawStream);
      if (stream == null) {
        continue;
      }

      final url = _primaryUri(stream);
      if (url == null) {
        continue;
      }

      final backupUrls = _backupUris(stream);
      final qualityId = BilibiliApiResponse.asInt(stream['id']);
      streams.add(
        BilibiliDashAudioStream(
          url: url,
          backupUrls: backupUrls,
          mimeType:
              BilibiliApiResponse.asString(stream['mimeType']) ??
              BilibiliApiResponse.asString(stream['mime_type']) ??
              'audio/mp4',
          qualityId: qualityId,
          qualityLabel: qualityLabels[qualityId],
          sampleRate:
              BilibiliApiResponse.asInt(stream['sampleRate']) ??
              BilibiliApiResponse.asInt(stream['sample_rate']) ??
              BilibiliApiResponse.asInt(stream['audioSamplingRate']) ??
              BilibiliApiResponse.asInt(stream['audio_sampling_rate']),
          channels: BilibiliApiResponse.asInt(stream['channels']),
          codec:
              BilibiliApiResponse.asString(stream['codecs']) ??
              BilibiliApiResponse.asString(stream['codec']),
          bitrate:
              BilibiliApiResponse.asInt(stream['bandwidth']) ??
              BilibiliApiResponse.asInt(stream['bitrate']),
          sizeInBytes: BilibiliApiResponse.asInt(stream['size']),
          expiresAt: _expiryForStream(url, backupUrls),
        ),
      );
    }
    return streams;
  }

  List<BilibiliMuxedStream> _parseMuxedStreams(
    Map<String, Object?> data,
    Map<int, String> qualityLabels,
    Duration? fallbackDuration,
  ) {
    final rawStreams = BilibiliApiResponse.asList(data['durl']);
    if (rawStreams == null || rawStreams.isEmpty) {
      return const <BilibiliMuxedStream>[];
    }

    final qualityId = BilibiliApiResponse.asInt(data['quality']);
    final streams = <BilibiliMuxedStream>[];
    for (final rawStream in rawStreams) {
      final stream = BilibiliApiResponse.asMap(rawStream);
      if (stream == null) {
        continue;
      }

      final url = _primaryUri(stream, additionalKeys: const <String>['url']);
      if (url == null) {
        continue;
      }

      final backupUrls = _backupUris(stream);
      streams.add(
        BilibiliMuxedStream(
          url: url,
          backupUrls: backupUrls,
          mimeType: 'video/mp4',
          qualityId: qualityId,
          qualityLabel: qualityLabels[qualityId],
          bitrate: BilibiliApiResponse.asInt(stream['bandwidth']),
          sizeInBytes: BilibiliApiResponse.asInt(stream['size']),
          duration:
              _durationFromMilliseconds(stream['length']) ?? fallbackDuration,
          expiresAt: _expiryForStream(url, backupUrls),
        ),
      );
    }
    return streams;
  }

  Map<int, String> _parseQualityLabels(Map<String, Object?> data) {
    final labels = <int, String>{};
    final qualities = BilibiliApiResponse.asList(data['accept_quality']);
    final descriptions = BilibiliApiResponse.asList(data['accept_description']);
    if (qualities != null && descriptions != null) {
      final count = qualities.length < descriptions.length
          ? qualities.length
          : descriptions.length;
      for (var index = 0; index < count; index++) {
        final quality = BilibiliApiResponse.asInt(qualities[index]);
        final description = BilibiliApiResponse.asString(descriptions[index]);
        if (quality != null && description != null && description.isNotEmpty) {
          labels[quality] = description;
        }
      }
    }

    final supportFormats = BilibiliApiResponse.asList(data['support_formats']);
    if (supportFormats != null) {
      for (final rawFormat in supportFormats) {
        final format = BilibiliApiResponse.asMap(rawFormat);
        if (format == null) {
          continue;
        }
        final quality = BilibiliApiResponse.asInt(format['quality']);
        final description =
            BilibiliApiResponse.asString(format['new_description']) ??
            BilibiliApiResponse.asString(format['display_desc']) ??
            BilibiliApiResponse.asString(format['description']);
        if (quality != null && description != null && description.isNotEmpty) {
          labels[quality] = description;
        }
      }
    }

    for (final entry in _fallbackQualityLabels.entries) {
      labels.putIfAbsent(entry.key, () => entry.value);
    }
    return labels;
  }

  Uri? _primaryUri(
    Map<String, Object?> stream, {
    List<String> additionalKeys = const <String>[],
  }) {
    final keys = <String>['baseUrl', 'base_url', 'baseURL', ...additionalKeys];
    for (final key in keys) {
      final uri = _parseUri(stream[key]);
      if (uri != null) {
        return uri;
      }
    }
    return null;
  }

  List<Uri> _backupUris(Map<String, Object?> stream) {
    for (final key in const <String>['backupUrl', 'backup_url', 'backupURL']) {
      final uris = _parseUriList(stream[key]);
      if (uris.isNotEmpty) {
        return List<Uri>.unmodifiable(uris);
      }
    }
    return const <Uri>[];
  }

  List<Uri> _parseUriList(Object? value) {
    if (value is String) {
      final uri = _parseUri(value);
      return uri == null ? const <Uri>[] : <Uri>[uri];
    }

    final list = BilibiliApiResponse.asList(value);
    if (list == null) {
      return const <Uri>[];
    }

    final result = <Uri>[];
    for (final item in list) {
      final uri = _parseUri(item);
      if (uri != null) {
        result.add(uri);
      }
    }
    return result;
  }

  Uri? _parseUri(Object? value) {
    final raw = BilibiliApiResponse.asString(value);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  DateTime? _expiryForStream(Uri url, List<Uri> backupUrls) {
    return _inferExpiry(url) ??
        (backupUrls.isEmpty ? null : _inferExpiry(backupUrls.first));
  }

  DateTime? _inferExpiry(Uri uri) {
    for (final key in const <String>['deadline', 'expires', 'expire']) {
      final raw = uri.queryParameters[key];
      final seconds = int.tryParse(raw ?? '');
      if (seconds == null) {
        continue;
      }

      // Deadline values below this are almost certainly not Unix epoch
      // seconds. Above this is far enough in the future that we do not want to
      // present it as a playback expiry.
      if (seconds < 1000000000 || seconds > 4102444800) {
        continue;
      }
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    }
    return null;
  }

  Duration? _durationFromMilliseconds(Object? value) {
    final milliseconds = BilibiliApiResponse.asInt(value);
    if (milliseconds == null || milliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: milliseconds);
  }

  DateTime? _earliestExpiry(Iterable<DateTime?> values) {
    DateTime? earliest;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (earliest == null || value.isBefore(earliest)) {
        earliest = value;
      }
    }
    return earliest;
  }
}
