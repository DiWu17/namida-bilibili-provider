# Namida Reference Adapter (Untested)

> Status: reference pseudocode only. The current public Namida build depends on
> private packages, so this code has not been compiled or tested against Namida.
> Confirm all player-source APIs against Namida's current public source before
> treating any snippet as compilable.

## Conceptual mapping

```dart
final media = await bilibiliProvider.resolve(uri);
final playback = await bilibiliProvider.getPlayback(media.id);

final audio = chooseAudio(playback.audioStreams);
final video = chooseVideo(playback.videoStreams);

// Pseudocode: adapt to Namida's actual AudioVideoSource constructor.
final audioSource = AudioVideoSource.uri(
  audio.url,
  headers: audio.headers,
);

final videoSource = AudioVideoSource.uri(
  video.url,
  headers: video.headers,
);
```

The essential contract is:

```text
audio.url     + audio.headers
video.url     + video.headers
```

No Bilibili-specific JSON or stream classes should be imported by the adapter.

## Minimal dispatch point

A future Namida adapter should:

1. detect Bilibili URLs/items through `canHandle`;
2. call `resolve` for metadata;
3. call `getPlayback` for the selected part;
4. map each separate DASH resource to the player's source type while preserving
   headers and expiry;
5. re-call `getPlayback` if a stream URL expires.
