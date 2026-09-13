# Namida Dispatch Analysis

Inspected public source commit `d3d8871`.

## 1. Playable type system

Files:

```text
lib/class/track.dart
lib/youtube/class/youtube_id.dart
```

Current shape:

```text
abstract class Playable<T extends Object>
abstract class Selectable<T extends Object> extends Playable<T>
class Track extends Selectable<String>
class Video extends Track
class YoutubeID implements Playable<Map<String, dynamic>>
```

There is no generic online-media playable interface. Bilibili needs a new
Playable type, for example:

```dart
class BilibiliID extends Playable<Map<String, dynamic>> {
  final OnlineMediaId mediaId; // provider: bilibili, id: BVID, subId: CID
}
```

Do not encode Bilibili BVID/CID into `YoutubeID`.

## 2. Hard-coded Playable dispatch

File:

```text
lib/base/audio_handler.dart
```

Current extension:

```dart
extension PlayableExecuter on Playable {
  T? execute<T>({
    required T Function(Selectable finalItem) selectable,
    required T Function(YoutubeID finalItem) youtubeID,
  }) { ... }

  FutureOr<T?> executeAsync<T>({
    required FutureOr<T?> Function(Selectable finalItem) selectable,
    required FutureOr<T?> Function(YoutubeID finalItem) youtubeID,
  }) { ... }
}
```

Minimal change: add an **optional** third branch:

```dart
T? execute<T>({
  required T Function(Selectable finalItem) selectable,
  required T Function(YoutubeID finalItem) youtubeID,
  T Function(OnlinePlayable finalItem)? onlinePlayable,
}) {
  if (item is Selectable) return selectable(item);
  if (item is YoutubeID) return youtubeID(item);
  if (item is OnlinePlayable && onlinePlayable != null) {
    return onlinePlayable(item);
  }
  return null;
}
```

Existing call sites keep compiling because the new callback is optional.

## 3. Audio handler dispatch points

File:

```text
lib/base/audio_handler.dart
```

Important methods:

```text
prepareItem()
onItemPlay()
beforeQueueAddOrInsert()
itemToTotalListenTimeKey()
onItemMarkedListened()
ensureReplayGainVolumeUpdated()
_itemToPrepareConfigSelectable()
_itemToPrepareConfigYoutubeID()
onItemPlayYoutubeID()
onItemPlayYoutubeIDSetQuality()
onItemPlayYoutubeIDSetAudio()
```

Bilibili needs parallel branches, initially:

```text
_itemToPrepareConfigOnlinePlayable()
onItemPlayOnlinePlayable()
onItemPlayOnlinePlayableSetQuality()
onItemPlayOnlinePlayableSetAudio()
```

## 4. Existing player source creation supports separate audio/video + headers

File:

```text
lib/base/audio_handler.dart
```

`_resolveYTNetworkSources()` currently:

```dart
final audioUri = preferredAudioStream.buildUrl();
finalAudioSource = _buildLockCachingAudioSource(
  audioUri,
  stream: preferredAudioStream,
  ...
);
```

and later:

```dart
final videoUri = preferredVideoStream.buildUrl();
finalVideoSource = _buildLockCachingVideoSource(
  videoUri,
  stream: preferredVideoStream,
  ...
);
```

`_buildLockCachingAudioSource()` / `_buildLockCachingVideoSource()` eventually
call `_buildCacheableAVSource()`, which uses:

```dart
return AudioVideoSource.uri(
  cacheUrl,
  headers: headers,
  onDispose: disposeStream,
);
```

This is directly compatible with our contract:

```dart
AudioVideoSource.uri(audio.url, headers: audio.headers)
AudioVideoSource.uri(video.url, headers: video.headers)
VideoSourceOptions(source: videoSource, loop: false, videoOnly: false)
```

The Bilibili adapter can reuse the existing source plumbing without touching
`basic_audio_handler`.

## 5. Video quality/audio quality UI coupling

Files:

```text
lib/controller/video_controller.dart
lib/packages/miniplayer_base.dart
lib/packages/miniplayer.dart
```

Current UI types:

```dart
final currentYTStreams = Rxn<VideoStreamsResult>();
```

`FocusedMenuOptions` uses:

```dart
Rxn<VideoStreamsResult> streams;
bool Function(VideoStream stream, File? cacheFile) isStreamSelected;
Future<void> Function(... VideoStream stream ...) onStreamVideoTap;
```

These are YoutiPie types. First Bilibili integration should avoid forcing
Bilibili into `VideoStreamsResult`.

Recommended first step:

- Auto-select preferred `OnlineVideoStream` / `OnlineAudioStream`.
- Expose provider-neutral current stream state separately.
- Add a Bilibili quality sheet later if desired.

## 6. External URL/link dispatch

Files:

```text
lib/main.dart
lib/core/extensions.dart
lib/controller/video_controller.dart
```

Current flow:

```text
external URL
-> getYoutubeID
-> settings.youtube.onYoutubeLinkOpen
-> YoutubeID queue item
```

Bilibili should add a parallel path:

```text
external URL
-> BilibiliProvider.canHandle(uri)
-> BilibiliID
-> resolve metadata / part / CID
-> normal Namida playback queue
```

Do not convert the Bilibili URL into a fake YouTube ID.

## 7. Minimal integration boundary

The Bilibili side already provides:

```text
OnlineMedia
OnlineMediaId
OnlineMediaPart
OnlineAudioStream
OnlineVideoStream
headers
backupUrls
expiresAt
```

Namida only needs to consume:

```dart
audio.url
audio.headers

video.url
video.headers
```

and optionally use the metadata/quality fields already present on the stream
objects.
