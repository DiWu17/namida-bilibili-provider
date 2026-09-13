// UNTESTED REFERENCE INTEGRATION
//
// This file is intentionally outside `packages/` and is not included in the
// provider packages or CI. It references Namida-private types and is not
// expected to compile in this repository.
//
// It shows the intended boundary:
//
//   BilibiliProvider
//     -> OnlinePlaybackData
//     -> AudioVideoSource.uri(url, headers: stream.headers)
//
// No Bilibili data is disguised as YouTube data.

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:online_media_provider/online_media_provider.dart';

// ---------------------------------------------------------------------------
// Namida-side marker types (reference only).
// ---------------------------------------------------------------------------

/// A Namida `Playable` item that can be resolved by a neutral online provider.
abstract interface class OnlinePlayable {
  String get key;

  OnlineMediaId get onlineMediaId;
}

/// Bilibili implementation of the Namida-side marker.
class BilibiliID implements OnlinePlayable {
  const BilibiliID({required this.onlineMediaId});

  @override
  final OnlineMediaId onlineMediaId;

  @override
  String get key => onlineMediaId.toString();
}

// ---------------------------------------------------------------------------
// Online resolver hook.
// ---------------------------------------------------------------------------

abstract interface class OnlineMediaResolver {
  bool canHandle(OnlinePlayable item);

  Future<OnlineMedia> resolveMetadata(OnlinePlayable item);

  Future<OnlinePlaybackData> resolvePlayback(OnlinePlayable item);
}

class BilibiliResolver implements OnlineMediaResolver {
  BilibiliResolver({BilibiliProvider? provider})
    : provider = provider ?? BilibiliProvider();

  final BilibiliProvider provider;

  @override
  bool canHandle(OnlinePlayable item) {
    return item.onlineMediaId.provider == provider.providerId;
  }

  @override
  Future<OnlineMedia> resolveMetadata(OnlinePlayable item) async {
    // BilibiliID normally comes from an already resolved URL. If metadata was
    // not cached by the caller, re-resolve it through the provider.
    final id = item.onlineMediaId;
    final metadata = await provider.resolve(
      Uri.parse('https://www.bilibili.com/video/${id.id}'),
      options: OnlineMediaResolveOptions(
        preferredPartIndex: _partIndex(id.subId),
      ),
    );
    return metadata;
  }

  @override
  Future<OnlinePlaybackData> resolvePlayback(OnlinePlayable item) {
    return provider.getPlayback(
      item.onlineMediaId,
      options: const OnlinePlaybackOptions(allowMuxedFallback: true),
    );
  }

  int? _partIndex(String? subId) {
    // Callers should pass a proper zero-based part index if available.
    // Returning null keeps the provider's default/first-part behavior.
    return null;
  }
}

// ---------------------------------------------------------------------------
// Namida source mapping (reference pseudo-code).
// ---------------------------------------------------------------------------
//
// The actual Namida patch must import its existing source types:
//
//   UriSource
//   AudioVideoSource
//   VideoSourceOptions
//
// Namida already constructs sources like this:

/*
final audioSource = AudioVideoSource.uri(
  audio.url,
  headers: audio.headers,
);

final videoSource = AudioVideoSource.uri(
  video.url,
  headers: video.headers,
);

final videoOptions = VideoSourceOptions(
  source: videoSource,
  loop: false,
  videoOnly: false,
);
*/

OnlineVideoStream? chooseBestVideo(List<OnlineVideoStream> streams) {
  if (streams.isEmpty) {
    return null;
  }

  final sorted = List<OnlineVideoStream>.of(streams)
    ..sort((a, b) {
      final aArea = (a.width ?? 0) * (a.height ?? 0);
      final bArea = (b.width ?? 0) * (b.height ?? 0);
      final areaCompare = bArea.compareTo(aArea);
      if (areaCompare != 0) {
        return areaCompare;
      }
      return (b.fps ?? 0).compareTo(a.fps ?? 0);
    });
  return sorted.first;
}

OnlineAudioStream? chooseBestAudio(List<OnlineAudioStream> streams) {
  if (streams.isEmpty) {
    return null;
  }

  final sorted = List<OnlineAudioStream>.of(streams)
    ..sort((a, b) {
      final aBitrate = a.bitrate ?? a.qualityId ?? 0;
      final bBitrate = b.bitrate ?? b.qualityId ?? 0;
      return bBitrate.compareTo(aBitrate);
    });
  return sorted.first;
}

// ---------------------------------------------------------------------------
// Reference URL handler.
// ---------------------------------------------------------------------------

Future<BilibiliID?> bilibiliIdFromUrl(
  Uri uri, {
  BilibiliProvider? provider,
}) async {
  final actualProvider = provider ?? BilibiliProvider();
  if (!actualProvider.canHandle(uri)) {
    return null;
  }

  final media = await actualProvider.resolve(uri);
  return BilibiliID(onlineMediaId: media.id);
}
