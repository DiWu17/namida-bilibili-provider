# Architecture

## Layer boundary

```text
Bilibili URL / API JSON
        |
        v
bilibili_provider internal models + parsers
        |
        v mapping
        v
provider-neutral DTOs (OnlineMedia / OnlinePlaybackData)
        |
        +--> standalone Flutter demo
        |
        +--> future thin Namida adapter
```

Rules:

1. `online_media_provider` contains no Bilibili API knowledge.
2. `bilibili_provider` never exposes raw API JSON models as its public API.
3. The player consumes `OnlineAudioStream` and `OnlineVideoStream` as separate
   resources. Bilibili DASH must not be flattened into a fake single URL.
4. Every stream carries its own headers and backup URLs.
5. `getPlayback` is always allowed to re-resolve fresh CDN URLs.

## Packages

- `packages/online_media_provider`  pure Dart, provider-neutral DTOs and the
  `OnlineMediaProvider` interface.
- `packages/bilibili_provider`  Bilibili URL parser, HTTP client, parsers,
  auth hook, structured errors, and `BilibiliProvider`.
- `example/standalone_player`  Flutter proof of real playback (Stage 5).
- `integration_test`  optional end-to-end tests (later stages).

## Error boundary

Provider-neutral exceptions live in `online_media_provider`. Bilibili-specific
exceptions extend the provider-neutral base so callers can catch either broad
online-media failures or specific Bilibili failures without parsing strings.

Sensitive headers (cookies, tokens, authorization) must never be logged.

## Verification status

- Provider core: offline fixtures + real public Bilibili metadata/DASH probes.
- Stream validation: real HTTP 206 range checks on video and audio DASH URLs.
- Standalone player: manually verified on Windows with `flutter run -d windows`.
- Namida adapter: reference only; not compiled or tested against Namida.
