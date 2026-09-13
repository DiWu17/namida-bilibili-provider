# Architecture

## Layer boundary

```text
Bilibili URL / API JSON
        |
        v
bilibili_provider internal models + parsers
        |
        +--> playback mapping
        |    v
        |    provider-neutral DTOs (OnlineMedia / OnlinePlaybackData)
        |            |
        |            +--> standalone Flutter demo
        |            |
        |            +--> future thin Namida adapter
        |
        +--> account layer (cookies, session, favorites)
             - Bilibili-specific account DTOs stay inside bilibili_provider
             - favorites are the only account data mapped to OnlineMedia
```

Rules:

1. `online_media_provider` contains no Bilibili API knowledge.
2. `bilibili_provider` never exposes raw API JSON models as its public API.
3. The player consumes `OnlineAudioStream` and `OnlineVideoStream` as separate
   resources. Bilibili DASH must not be flattened into a fake single URL.
4. Every stream carries its own headers and backup URLs.
5. `getPlayback` is always allowed to re-resolve fresh CDN URLs.
6. Playback and account code share only `BilibiliHttpTransport`. Account DTOs must
   not leak into the `OnlineMediaProvider` contract.
7. Credentials live in `BilibiliCookies` and are attached in exactly one place
   (`BilibiliHttpTransport.requestHeaders`). No other code may build a `Cookie`
   header, log one, or put one in an exception.
8. `BilibiliProvider` keeps working anonymously; account state is opt-in through
   `BilibiliAccountManager`.
9. The main library (`bilibili_provider.dart`) contains no `dart:io`. Filesystem
   stores live behind the separate `io.dart` entry point, so importing the
   provider never implies writing credentials and web builds stay possible.

## Packages

- `packages/online_media_provider`  pure Dart, provider-neutral DTOs and the
  `OnlineMediaProvider` interface.
- `packages/bilibili_provider`  Bilibili URL parser, HTTP transport, playback and
  account clients, parsers, auth hook, structured errors, `BilibiliProvider`, and
  `BilibiliAccountManager`. The `io.dart` entry point adds filesystem-backed
  cookie stores for desktop/server consumers.
- `example/standalone_player`  Flutter proof of real playback (Stage 5) and of the
  account layer: login dialog, cookie persistence, account card, favorites browser.
- `integration_test`  optional end-to-end tests (later stages).

## Account layer boundary

```text
BilibiliAccountManager            session lifecycle: anonymous -> signed in -> expired
        |
        +-- BilibiliAccountAuthProvider   live cookies for any HTTP client
        +-- BilibiliCookieStore           persistence boundary
        |       +-- InMemoryBilibiliCookieStore        default
        |       +-- ConditionalBilibiliCookieStore     runtime "remember" switch
        |       +-- PlainTextFileBilibiliCookieStore   io.dart, opt-in
        +-- BilibiliAccountClient         nav / myinfo / favorites / favorite writes
                    |
                    +-- BilibiliAccountParser     response -> internal models
                    +-- BilibiliFavListUrlParser  favlist links -> folder refs
```

`resolveById` on `BilibiliProvider` is the only playback-side addition the account
layer needed, because account APIs return a BVID without a CID.

## Error boundary

Provider-neutral exceptions live in `online_media_provider`. Bilibili-specific
exceptions extend the provider-neutral base so callers can catch either broad
online-media failures or specific Bilibili failures without parsing strings.
`BilibiliAuthenticationException` covers "not signed in / expired / bad csrf" and
never carries credential material.

Sensitive headers (cookies, tokens, authorization) must never be logged.

## Verification status

- Provider core: offline fixtures + real public Bilibili metadata/DASH probes.
- Stream validation: real HTTP 206 range checks on video and audio DASH URLs.
- Account layer: offline fixtures only; online tests are credential-free.
- Standalone player: manually verified on Windows with `flutter run -d windows`.
- Namida adapter: reference only; not compiled or tested against Namida.
