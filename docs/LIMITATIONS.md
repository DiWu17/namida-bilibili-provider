# Limitations

- The MVP targets ordinary public Bilibili videos only.
- Anonymous access is the default; authenticated playback requires a future
  caller-provided auth implementation.
- No DRM, premium, paid-content, region-lock, or credential-extraction bypass.
- No live, bangumi, search, recommendations, comments, danmaku, or download
  manager in the MVP.
- Bilibili Web API responses can change. Raw JSON models are kept internal so
  changes are contained in `bilibili_provider`.
- CDN URLs can expire and may require headers; a player adapter must pass stream
  headers through to its HTTP stack.
- Online tests depend on public Bilibili availability and are therefore
  scheduled/manual rather than part of every commit.

## Stream validation behavior

- `BilibiliStreamValidator` reads only a small prefix (`maxBytes`, default
  1024) and never downloads a complete media file.
- HTTP 206 is treated as range support.
- HTTP 200 is accepted as a limited fallback when a CDN ignores or rejects
  `Range`; this is recorded as `rangeSupported = false`.
- HTTP 416 / 501 causes one retry without `Range`, still limited by `maxBytes`.
- Validation results do not expose full stream URLs or sensitive query strings.

## Platform verification

- Standalone playback was manually verified on Windows.
- Android/iOS/macOS/Linux/web platform folders and playback are not included by
  default and have not been verified.
- Windows requires the media_kit libmpv/ANGLE archives; restricted networks may
  need the offline workaround documented in `example/standalone_player/README.md`.
