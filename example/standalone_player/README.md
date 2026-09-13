# Standalone Player

This Flutter app is the Stage 5 proof that the provider can resolve and play
real public Bilibili DASH streams without Namida or YoutiPie.

## Verification status

Manually verified on Windows:

```text
flutter run -d windows
-> build succeeded
-> resolve succeeded
-> metadata displayed
-> PLAY displayed real video
-> audio played
-> pause/seek worked
```

## What it does

```text
Bilibili URL
-> BilibiliProvider.resolve()
-> metadata
-> part selection
-> BilibiliProvider.getPlayback()
-> video DASH stream selection
-> audio DASH stream selection
-> real playback
```

The provider keeps video and audio as two separate `OnlineStream` resources.
For the standalone demo, media_kit/mpv is used twice:

- a muted video `Player` for the video DASH URL;
- an audio `Player` for the audio DASH URL;
- both players are started, paused, and seeked together.

This dual-player strategy is deliberate: it avoids changing the provider model
or faking DASH muxing. A future Namida adapter can map the two streams into
whatever source model Namida provides.

## Included platform

This repository includes generated Windows runner files:

```text
windows/
```

Run on Windows:

```powershell
cd example/standalone_player
flutter pub get
flutter run -d windows
```

If you need Android, iOS, macOS, Linux, or web platform folders, generate them
once with the Flutter tool:

```text
flutter create --platforms=android,ios,linux,macos,web .
```

Then run `flutter run` for the desired device.

## Account, login and favorites

The app has an account panel at the top and a favorite browser at the bottom, so
the account layer can be exercised by hand.

```text
[ 未登录（匿名访问） ]  [ 登录 ]
        |
        v  scan the QR with the Bilibili app (or paste a Cookie as a fallback)
[ 头像 + 昵称 ]  [ 刷新账号信息 / 继续浏览但不再发送 Cookie / 退出当前账号 / 清除已保存的 Cookie ]
        |
        v
[ 收藏夹 ]  [ 刷新 ]  ->  folder list  ->  items  ->  tap to load into the player
```

### Signing in by scanning (default)

1. Tap 登录.
2. The dialog opens on 扫码登录 and shows a QR code.
3. Scan it with the Bilibili mobile app and confirm on the phone.
4. The status line walks through 请扫描 -> 已扫码，请在手机上确认 -> 登录成功, and the
   dialog closes by itself.

`BilibiliAccountManager.signInWithQrCode()` drives this: it requests a ticket from
`passport.bilibili.com`, polls until the platform confirms, then validates the
delivered cookies through `nav` before adopting them. The QR image comes from
`BilibiliQrLoginStatus.login.uri`; the ticket is a login credential, so it is never
printed and the dialog never renders it as text. If the code expires, 刷新二维码
issues a new one.

No password, captcha, or browser profile is involved: you authenticate in
Bilibili's own app, on your own device.

### Signing in by pasting a Cookie (fallback)

Only needed when scanning is impossible. Switch the dialog to 手动输入 Cookie and
paste the value of the `Cookie` request header from your own browser
(DevTools -> Network -> any `api.bilibili.com` request -> Request Headers).

Include at least:

```text
SESSDATA      required for every authenticated request
bili_jct      required for favorite add/remove
DedeUserID    gives the account key before the first request
```

The dialog reports only which cookie **names** it recognized and disables the
login button when `SESSDATA` is missing, so it is obvious whether the paste was
complete. Values are never displayed. Anything the app requires is explicit user
input: it never reads a browser profile, never touches a keychain, and never asks
for a password.

### Where the cookie is stored

```text
%APPDATA%\namida_bilibili_provider\bilibili_account_cookies.json
```

The login dialog shows the exact path. The file is **plain text**, protected only
by the per-user permissions of the application data directory, which is why the
dialog has a "保存到本机" switch (it applies to both login paths):

- switch on -> `ConditionalBilibiliCookieStore.persist = true`, the manager writes
  the file and the next launch signs in automatically;
- switch off -> writes are dropped, the cookies live in memory for this run only,
  and any previously saved file is left untouched.

Use "清除已保存的 Cookie 并退出" to delete the file. Neither the cookie nor the file
contents are ever logged, and stream URLs are never printed either.

### Playing from favorites

Favorites carry a BVID but no CID, so tapping an item calls
`BilibiliProvider.resolveById()` (one metadata request) and only then
`getPlayback()`. That path is the same one a thin Namida adapter would use.

`加载更多` walks the folder page by page (`ps=20`), and items Bilibili marks as
expired are hidden with a count so the list stays playable.

## Testing without the UI

The account layer itself is covered by the package test suites; see the
[Testing section](../../README.md#testing) of the root README:

```powershell
cd packages/bilibili_provider
dart test                                              # 231 offline tests

$env:BILIBILI_TEST_COOKIES = 'SESSDATA=...; bili_jct=...; DedeUserID=...'
dart test --tags authenticated --run-skipped            # read-only, your account
dart run tool/bilibili_account_check.dart               # manual diagnostics
```

## Windows media_kit download troubleshooting

`media_kit_libs_windows_video` downloads two GitHub release archives during the
first Windows build:

```text
mpv-dev-x86_64-20230924-git-652a1dd.7z
MD5: a832ef24b3a6ff97cd2560b5b9d04cd8

ANGLE.7z
MD5: e866f13e8d552348058afaafe869b1ed
```

If the build fails with:

```text
Integrity check failed, please try to re-build project again.
```

and the archive under `build/windows/x64/` is 0 bytes, your network could not
reach GitHub release assets.

Options:

1. Enable a VPN/proxy and run the following.

If you are using **cmd.exe** (the shell shown by `D:\...>`), use `set`:

```bat
set HTTP_PROXY=http://127.0.0.1:7897
set HTTPS_PROXY=http://127.0.0.1:7897
set http_proxy=http://127.0.0.1:7897
set https_proxy=http://127.0.0.1:7897

REM Optional: verify proxy connectivity before Flutter runs CMake.
curl -x http://127.0.0.1:7897 -I https://github.com

flutter run -d windows
```

If you are using **PowerShell**, use `$env:`:

```powershell
$env:HTTP_PROXY = "http://127.0.0.1:7897"
$env:HTTPS_PROXY = "http://127.0.0.1:7897"
$env:http_proxy = "http://127.0.0.1:7897"
$env:https_proxy = "http://127.0.0.1:7897"

flutter run -d windows
```

Replace `7897` with your actual proxy port.

2. Download these files in a browser/with a proxy:

```text
https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z
https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z
```

Then place them before running the app:

```powershell
.\tool\place_windows_media_kit_archives.ps1 `
  -MpvArchive C:\Downloads\mpv-dev-x86_64-20230924-git-652a1dd.7z `
  -AngleArchive C:\Downloads\ANGLE.7z

flutter run -d windows
```

Do not run `flutter clean` after placing the archives unless you will place them
again, because `flutter clean` deletes the `build/` directory.
