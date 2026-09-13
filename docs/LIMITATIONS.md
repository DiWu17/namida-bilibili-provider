# Limitations

- The provider targets ordinary public Bilibili videos plus the signed-in user's
  own account data (current profile and favorites).
- Anonymous access is the default. The account layer only sends credentials after
  an explicit `BilibiliAccountManager.signIn` with user-supplied cookies.
- Sign-in is cookie-only: there is no QR-code, password, or SMS login flow.
- The default cookie store is in-memory, so nothing is written to disk unless the
  application opts in. The shipped opt-in store,
  `PlainTextFileBilibiliCookieStore` (`package:bilibili_provider/io.dart`), keeps
  cookies as **plain text** in the per-user application data directory
  (`%APPDATA%` on Windows, `~/Library/Application Support` on macOS,
  `$XDG_DATA_HOME` or `~/.local/share` elsewhere). It relies on directory
  permissions, not encryption, and on Linux the file inherits the process umask.
  Applications that need at-rest protection must supply an
  OS keychain / DPAPI / `flutter_secure_storage` backed `BilibiliCookieStore`.
  `ConditionalBilibiliCookieStore` lets a sign-in form offer "do not remember"
  without any file being written.
- `dart:io` is kept out of the main provider library, so importing the provider
  cannot write credentials and web builds remain possible.
- Account reads use the caller's own cookies, and account writes (favorite
  add/remove) require the session's `bili_jct` csrf token. Requests are never
  retried automatically, and nothing is requested for another account.
- Favorites that Bilibili marks invalid are kept in `BilibiliFavoritePage.entries`
  but excluded from `BilibiliFavoritePage.media`, because they cannot be resolved.
- Favorite, history, and playlist APIs never expose a CID, so those items need
  `BilibiliProvider.resolveById` before `getPlayback`.
- No DRM, premium, paid-content, region-lock, or credential-extraction bypass.
- No history, subscriptions, user playlists/collections, live, bangumi, search,
  recommendations, comments, danmaku, or download manager yet.
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
