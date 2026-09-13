# namida-bilibili-provider

A standalone Bilibili online-media provider designed for potential integration
with [Namida](https://github.com/namidaco/namida).

**This project is not an official Namida component.** It does not depend on
Namida or on the private `youtipie` package. The goal is to make the Bilibili
side complete, testable, and playable on its own so a future Namida adapter only
has to map a small provider-neutral playback contract into Namida's player.

> Current status: Stage 0-3. The provider-neutral contract, BV/av/b23 URL
> parser, bounded short-link resolution, metadata/CID mapping, DASH
> audio/video parsing, and offline tests are in place. A real public Bilibili
> video was manually resolved and its DASH streams were returned successfully.
> Stream range validation and the standalone Flutter player remain.

## Problem

Namida already has YouTube playback, but its YouTube parsing/stream extraction
is supplied by a private package (`youtipie`). This makes it impossible to
clone, extend, build, and verify a Bilibili integration locally. A feature
request alone would leave all Bilibili API, CID, DASH, header, and expiry work
to the Namida maintainer.

## Goal

Implement a complete, independently testable Bilibili provider that exposes:

- provider-neutral metadata and parts;
- separate DASH video and audio stream descriptions;
- raw codec, quality, resolution, FPS, bitrate, headers, backup URLs, and
  expiry information;
- structured errors and an optional explicit auth boundary;
- a standalone Flutter demo proving real playback without Namida/YoutiPie.

The remaining Namida-side work should be only a thin adapter from
`OnlinePlaybackData` to Namida's existing audio/video source layer.

## Architecture

```mermaid
flowchart TD
    URL[Bilibili URL]
    Provider[BilibiliProvider]
    API[Bilibili Web/API]
    DTO[OnlinePlaybackData]
    Demo[Standalone Player]
    Adapter[Future Namida Adapter]
    Namida[Namida Player]

    URL --> Provider
    Provider --> API
    API --> Provider
    Provider --> DTO
    DTO --> Demo
    DTO --> Adapter
    Adapter --> Namida
```

The repository is split into two packages:

- `packages/online_media_provider`  provider-neutral DTOs and contracts.
- `packages/bilibili_provider`  Bilibili URL/API/DASH implementation. The
  public provider API does not expose Bilibili API JSON models.

## Five-line usage example

```dart
final provider = BilibiliProvider();
final media = await provider.resolve(Uri.parse('https://www.bilibili.com/video/BV...'));
final playback = await provider.getPlayback(media.id);
final audio = playback.audioStreams.first; // choose with your own policy
final video = playback.videoStreams.first;
// Pass audio.url/video.url and audio.headers/video.headers to the player.
```

## Supported URLs

MVP target:

- `https://www.bilibili.com/video/BV...`
- `https://www.bilibili.com/video/av...`
- `https://b23.tv/...`
- `?p=N` part selection

The parser and metadata stage handle all of these, including bounded redirects for b23.tv short links.

## Supported playback features (MVP target)

- metadata: title, UP name, cover, duration, description;
- multi-part/P selection and CID resolution;
- DASH separate audio/video streams;
- quality id/label, resolution, FPS parsing;
- raw codec plus coarse codec family;
- required per-stream HTTP headers;
- backup URL lists;
- URL expiry metadata and stream refresh through `getPlayback`;
- stream HTTP range validation;
- real playback in the standalone Flutter example.

## Test status

Offline tests are required to pass without network access. The current suite
contains 54 offline tests: 7 provider-neutral model tests and 47 Bilibili
URL/client/metadata/DASH-resolve tests. Online integration tests are tagged and run
only through the scheduled/manual workflow.

Run locally:

```powershell
cd packages/online_media_provider
dart pub get
dart test

cd ../bilibili_provider
dart pub get
dart test
```

## Standalone demo

The standalone Flutter demo lives under `example/standalone_player/` and will be
implemented in Stage 5. Its purpose is to prove that the provider can resolve
and play real public Bilibili DASH streams with no Namida or YoutiPie
dependency.

## Namida integration boundary

Namida currently has no formal provider interface; its playable dispatch mainly
recognizes `Selectable`/`YoutubeID`, and its stream types come from YoutiPie.
This project does **not** claim a tested Namida integration. We provide a
reference adapter and minimal integration proposal for the Namida maintainer to
evaluate after the provider itself is tested.

See [docs/NAMIDA_INTEGRATION.md](docs/NAMIDA_INTEGRATION.md).

## Known limitations

- Anonymous/public ordinary videos only in the MVP.
- No login/QR/cookie extraction.
- No paid, DRM, region-locked, or member-only bypass.
- No live, bangumi, comments, danmaku, search, or recommendations in the MVP.
- Stream range validation and the standalone Flutter demo are later stages.

## Development stages

- [x] Stage 0  repository bootstrap, provider-neutral DTOs/contract, tests, CI
- [x] Stage 1  BV/av/b23 URL parser and part parameter
- [x] Stage 2  metadata, uploader, cover, duration, parts, CID resolution
- [x] Stage 3  DASH playback resolver
- [ ] Stage 4  stream HTTP validation
- [ ] Stage 5  standalone Flutter player
- [ ] Stage 6  complete documentation
- [ ] Stage 7  optional untested Namida reference adapter




