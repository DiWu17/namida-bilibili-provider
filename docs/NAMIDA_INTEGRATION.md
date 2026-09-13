# Namida Integration Boundary

## Status statement

- Bilibili provider: implemented and tested by this project (as stages complete).
- Standalone playback: implemented by this project (Stage 5).
- Namida adapter: reference integration only, not compiled or tested here.

This is because the current public Namida build depends on private packages,
including `youtipie`.

## Current Namida shape (public-source understanding)

```text
YoutubeID
    |
YoutubeInfoController
    |
YoutiPie
    |
VideoStreamsResult
    +-- AudioStream (YoutiPie type)
    +-- VideoStream (YoutiPie type)
    |
Namida player
```

`AudioStream`, `VideoStream`, and `VideoStreamsResult` are YoutiPie-owned types.
Playable dispatch mainly recognizes `Selectable` and `YoutubeID`, so third-party
online providers currently have no formal integration point.

## What Namida actually needs

The Bilibili side can already provide everything Namida needs:

```text
media metadata          -> OnlineMedia
audio stream + headers  -> OnlineAudioStream
video stream + headers  -> OnlineVideoStream
quality/codec/fps/etc.  -> stream metadata fields
```

A minimal Namida-side change should introduce a generic online playable
resolver hook, conceptually:

```dart
abstract interface class OnlinePlayableResolver {
  bool canHandle(Playable item);
  Future<OnlinePlaybackData> resolve(Playable item);
}
```

The project does not insist on a particular class name or architecture. We only
recommend that the dispatch point accept Bilibili/third-party providers and map
`OnlinePlaybackData` into the existing player source layer.

## Important boundary

This project does not modify Namida as its primary implementation and does not
claim that Namida integration is tested. See
[NAMIDA_REFERENCE_ADAPTER.md](NAMIDA_REFERENCE_ADAPTER.md) for untested
reference code and exact conceptual mapping.
