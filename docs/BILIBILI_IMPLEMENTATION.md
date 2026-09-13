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
