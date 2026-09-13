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

