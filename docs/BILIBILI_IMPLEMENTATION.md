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
