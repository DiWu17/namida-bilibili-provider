# Provider Contract

## OnlineMediaProvider

```dart
abstract interface class OnlineMediaProvider {
  String get providerId;
  bool canHandle(Uri uri);
  Future<OnlineMedia> resolve(
    Uri uri, {
    OnlineMediaResolveOptions options = const OnlineMediaResolveOptions(),
  });
  Future<OnlinePlaybackData> getPlayback(
    OnlineMediaId mediaId, {
    OnlinePlaybackOptions options = const OnlinePlaybackOptions(),
  });
}
```

## Core DTOs

`OnlineMediaId` is provider-neutral. For Bilibili:

- `provider` = `bilibili`
- `id` = BVID (`subId` may carry a CID when useful)
- `subId` = CID when a specific part is selected

`OnlineMedia` contains title, artist/uploader, thumbnail, duration,
description, parts, and an `extra` map for non-contract metadata.

`OnlineMediaPart` represents a selectable part. For Bilibili, `id` is the CID
and `index` is zero-based.

`OnlinePlaybackData` contains:

- `media`;
- `audioStreams`;
- `videoStreams`;
- `muxedStreams` (optional, not an MVP requirement);
- overall known expiry.

## Streams

Every `OnlineStream` exposes:

```dart
Uri get url;
List<Uri> get backupUrls;
Map<String, String> get headers;
String get mimeType;
String? get codec;       // raw codec string
String? get rawCodec;    // alias, explicitly preserved
OnlineCodecFamily get codecFamily;
int? get bitrate;
int? get sizeInBytes;
Duration? get duration;
DateTime? get expiresAt;
```

Video streams additionally expose `qualityId`, `qualityLabel`, `width`,
`height`, and `fps`. Audio streams expose `qualityId`, `qualityLabel`,
`sampleRate`, and `channels`.

The raw codec string must never be lost when mapping to a family enum.

## Expiry and refresh

A provider must not pretend a URL is permanent. Bilibili CDN URLs can expire.
Expiry is used only when inferable from API fields or URL parameters;
otherwise `expiresAt` is null. Callers should call `getPlayback` again when a
stream is stale or fails.
