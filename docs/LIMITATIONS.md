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
