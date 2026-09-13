# Namida Reference Integration

> Status: **UNTESTED REFERENCE INTEGRATION**
>
> The current public Namida build depends on private packages (`youtipie`,
> `basic_audio_handler`, and others). This reference patch was written after
> inspecting the public Namida source, but it has not been compiled or tested
> against Namida.

Inspected public source:

```text
commit: d3d8871
branch: main
```

## Goal

Show a minimal, honest integration boundary:

```text
Namida Playable item
-> OnlinePlayable / BilibiliID
-> OnlineMediaProvider.resolve()
-> OnlinePlaybackData
-> AudioVideoSource.uri(video.url, headers: video.headers)
-> AudioVideoSource.uri(audio.url, headers: audio.headers)
-> existing Namida player source layer
```

The provider keeps Bilibili video and audio as separate streams. The reference
adapter must not create a fake muxed URL or disguise Bilibili data as YouTube.

## Key findings from public Namida source

- `Playable` and `Selectable` are defined in `lib/class/track.dart`.
- `YoutubeID` is the only online `Playable` implementation in public source:
  `lib/youtube/class/youtube_id.dart`.
- `PlayableExecuter.execute()` / `executeAsync()` hard-code only two branches:
  `Selectable` and `YoutubeID`:
  `lib/base/audio_handler.dart`.
- `NamidaAudioVideoHandler.prepareItem()` and `onItemPlay()` dispatch through
  those two branches.
- `_itemToPrepareConfigYoutubeID()` creates `AudioVideoSource` values for
  YoutiPie `VideoStream` / `AudioStream`.
- Existing source creation already supports per-stream headers:
  `AudioVideoSource.uri(..., headers: ...)`.
- `VideoSourceOptions` already accepts a separate video source.
- UI stream selectors and `VideoController.currentVideoConfig.currentYTStreams`
  are strongly typed to YoutiPie `VideoStream` / `AudioStream` / `VideoStreamsResult`.

## Recommended minimum Namida-side change

1. Add a provider-neutral `OnlinePlayable` interface in Namida.
2. Add `BilibiliID` as a new `Playable` type.
3. Add one optional `onlinePlayable` branch to `PlayableExecuter`.
4. Add an `OnlineMediaResolver`/`BilibiliResolver` hook.
5. Add Bilibili branches to `prepareItem()`, `onItemPlay()`, queue separation,
   and item properties.
6. Map provider streams to player sources:
   - `AudioVideoSource.uri(audio.url, headers: audio.headers)`
   - `AudioVideoSource.uri(video.url, headers: video.headers)`
   - `VideoSourceOptions(source: videoSource, loop: false, videoOnly: false)`
7. For the first integration, auto-select the best video/audio stream.
   A generic quality selector can follow later.

## Files

- `NAMIDA_DISPATCH_ANALYSIS.md`  detailed dispatch/integration analysis.
- `minimal_namida_hook.pseudo.diff`  conceptual minimal diff.
- `namida_bilibili_reference_adapter.dart`  reference adapter code, not
  part of any package and not expected to compile as-is.
