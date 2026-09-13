# Bilibili Implementation

## Flow

```text
URL
 -> normalize
 -> resolve b23.tv redirect if needed (bounded redirects)
 -> extract BVID or aid
 -> fetch view metadata
 -> resolve page/CID
 -> fetch playurl DASH response
 -> map to OnlinePlaybackData
```

## Supported MVP content

- ordinary public Bilibili videos;
- BV ids;
- av ids;
- b23.tv short links;
- multi-part videos through `?p=N` and CID selection;
- DASH separate audio/video streams.

Not supported in the MVP:

- live streams;
- bangumi;
- paid/member-only/DRM/region-locked bypass;
- login/QR/password flows;
- comments, danmaku, recommendations, search.

## HTTP and auth

`BilibiliClient` owns HTTP calls. `BilibiliProvider` maps platform models to
provider-neutral DTOs. Anonymous playback is the default. Cookies may only be
provided explicitly by the caller in a future auth implementation.

Each mapped stream must carry the headers required by its CDN URL:

- `Referer: https://www.bilibili.com/`
- browser-like `User-Agent`
- `Cookie` only when explicitly supplied by the caller/auth provider

## Parsing priorities

1. Preserve raw codec strings.
2. Parse FPS values including `30000/1001`.
3. Preserve primary and backup URLs.
4. Preserve quality ids and human-readable labels.
5. Keep `baseUrl`/`backupUrl` arrays distinct from audio/video kinds.
6. Reject unsupported or unavailable content with structured errors.

## Stage 2 implementation status

Stage 2 implements anonymous metadata resolution:

```text
Bilibili URL
 -> BilibiliUrlParser
 -> optional bounded b23.tv redirect resolution
 -> BilibiliClient GET /x/web-interface/view
 -> BilibiliMetadataParser
 -> OnlineMedia + OnlineMediaPart/CID
```

Implementation details:

- `BilibiliApiResponse` decodes the common `{code, message, data}` envelope.
- Non-zero Bilibili API codes map to structured exceptions.
- `BilibiliMetadataParser` tolerates missing optional fields and stringly
  typed numeric values.
- `OnlineMediaId.subId` is set to the selected CID.
- `?p=N` and `OnlineMediaResolveOptions.preferredPartIndex` select a part.
- `BilibiliClient.resolveShortUrl` follows at most
  `maxShortLinkRedirects` hops and rejects redirects outside recognized
  Bilibili hosts.
- `BilibiliClient` accepts an injected `http.Client`, which keeps client and
  provider tests fully offline via `MockClient`.

## Stage 3 implementation status

Stage 3 implements DASH playback resolution:

```text
BVID + CID
 -> BilibiliClient.getPlayback
 -> GET /x/player/playurl
    bvid=...&cid=...&qn=...&fnval=4048&fnver=0&fourk=1&platform=pc&otype=json
 -> BilibiliDashParser
 -> BilibiliDashVideoStream / BilibiliDashAudioStream / BilibiliMuxedStream
 -> OnlineVideoStream / OnlineAudioStream / OnlineMuxedStream
 -> OnlinePlaybackData
```

Implemented:

- separate DASH video/audio stream parsing;
- optional `durl` muxed fallback parsing;
- raw codec strings and `OnlineCodecFamily` mapping;
- quality IDs and quality labels from API fields plus fallback labels;
- width, height, FPS (`parseFrameRate`, including `30000/1001`), bitrate;
- primary URL and `backupUrl` preservation;
- per-stream headers, including explicit auth cookies when provided;
- URL expiry inference from a URL `deadline` / `expires` / `expire` parameter;
- `OnlinePlaybackData.expiresAt` as the earliest known stream expiry;
- `getPlayback` re-fetches stream URLs through the API each time.

### Manual real-video probe

During Stage 3 development the provider was manually run against this public
video:

```text
https://www.bilibili.com/video/BV17xeRz9EJs/
```

Observed result:

```text
canHandle        = true
metadata         = resolved
parts            = 1
video DASH       = 6 streams
audio DASH       = 3 streams
muxed fallback   = 0
per-stream headers and backup URLs were preserved
```

The favorites URL shape:

```text
https://space.bilibili.com/404380192/favlist?fid=...&ftype=create
```

is intentionally not supported by the ordinary-video MVP and returns
`canHandle == false`. Favorites require user-context APIs and are outside the
current scope.

## Stage 4 implementation status

Stage 4 adds lightweight stream validation:

```text
OnlineVideoStream / OnlineAudioStream
 -> GET stream.url
 -> request headers from the stream
 -> Range: bytes=0-1023
 -> read at most maxBytes
 -> HTTP 206 (preferred) or HTTP 200 fallback
 -> structured BilibiliStreamValidationResult
```

Implementation:

- `BilibiliStreamValidator` accepts an injected `http.Client`.
- Each stream's own `headers` are forwarded.
- Only the configured prefix is read and buffered.
- HTTP 206 is recorded as `rangeSupported = true`.
- HTTP 200 is accepted as a limited fallback and recorded as
  `rangeSupported = false`.
- HTTP 416 / 501 triggers one retry without the `Range` header; the retry is
  still limited by `maxBytes`.
- Timeouts and transport errors return a non-playable result with a safe reason.
- Validation never logs or returns the full sensitive stream URL query.

### Real validation result

Using the same public video:

```text
https://www.bilibili.com/video/BV17xeRz9EJs/
```

the first parsed video and audio stream both returned:

```text
status       = 206
bytesRead    = 1024
rangeSupport = true
isPlayable   = true
```

This demonstrates that the provider's resolved DASH URLs and per-stream headers
work against real Bilibili CDN endpoints, without downloading the full media.

## Stage 5 standalone Flutter player

`example/standalone_player/` contains a real Flutter application that consumes
only the provider-neutral `OnlineMedia` / `OnlinePlaybackData` contract.

Playback strategy:

```text
OnlineVideoStream -> muted media_kit Player -> VideoController -> Video widget
OnlineAudioStream -> separate media_kit Player
```

Why two players:

- Bilibili DASH exposes separate audio and video URLs.
- The provider deliberately keeps them as separate `OnlineStream` resources.
- The demo does not fake a muxed stream or change the provider model.
- `media_kit` / mpv can consume each DASH representation independently.
- Play, pause, and seek actions are applied to both players together.

Included:

- Bilibili URL field and Resolve button;
- thumbnail, title, uploader and duration;
- part / P selector;
- video quality dropdown (quality, resolution, FPS, codec);
- audio quality dropdown (quality, bitrate, codec);
- real video widget plus play/pause/seek controls;
- generated Windows runner files.

The Flutter GUI itself must be launched manually in a normal Flutter desktop or
mobile environment:

```powershell
cd example/standalone_player
dart pub get
flutter run -d windows
```
