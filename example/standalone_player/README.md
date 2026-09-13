# Standalone Player

This Flutter app is the Stage 5 proof that the provider can resolve and play
real public Bilibili DASH streams without Namida or YoutiPie.

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
