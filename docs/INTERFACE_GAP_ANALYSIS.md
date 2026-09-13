# Namida / YoutiPie Interface Gap Analysis

Reference project:

```text
https://github.com/namidaco/namida
```

Inspected public source:

```text
commit d3d8871
branch main
```

Purpose:

```text
Compare the interfaces used by Namida's public YouTube/YoutiPie side
with the interfaces currently exposed by namida-bilibili-provider.
```

Status legend:

```text
 = equivalent or supported
 = not implemented
```

Important:

```text
This is an interface comparison, not a claim that Namida can compile the
Bilibili provider today. Namida currently depends on private packages.
```

---

# 1. Core URL, Metadata and Playback

| Original Namida / YoutiPie interface | Our Bilibili interface | Status |
|---|---|---|
| URL handling via `YoutiPie` URL utils | `BilibiliUrlParser.parse()` / `BilibiliProvider.canHandle()` |  |
| YouTube video URL -> `YoutubeID(id: ...)` | `BilibiliMediaRef` + `OnlineMediaId(provider: bilibili, id: BVID, subId: CID)` |  |
| `YoutubeInfoController.video.fetchVideoPage(videoId)` | `BilibiliProvider.resolve(uri)` |  |
| `YoutubeInfoController.video.fetchVideoPageCache(videoId)` | `BilibiliProvider` metadata cache by BVID |  partial |
| `YoutubeInfoController.video.fetchVideoStreams(videoId)` | `BilibiliProvider.getPlayback(mediaId)` |  |
| `YoutubeInfoController.video.fetchVideoStreamsCache(videoId)` | No stream URL cache; `getPlayback` refreshes on every call |  |
| `YoutubeInfoController.video.ensureJSPlayerInitialized()` | Bilibili has no YouTube cipher/JS player concept |  N/A |
| `YoutubeInfoController.video.forceRefreshJSPlayer()` | Bilibili has no YouTube cipher/JS player concept |  N/A |
| `YoutubeInfoController.video.getJSPlayerVersion()` | Bilibili has no YouTube cipher/JS player concept |  N/A |
| `YoutubeInfoController.video.fetchLikeStatusForVideoCardInstant(videoId)` | No like status API |  |
| `YoutubeInfoController.video.fetchRelatedVideos(videoId)` | No related-video API |  |
| `YoutubeInfoController.playlist.getMixPlaylist(videoId)` | No mix/radio playlist API |  |
| External URL -> `YoutubeID` queue item | `BilibiliID` reference concept only; not integrated into Namida |  |
| Quality selection through `VideoStream` / `VideoStreamsResult` | `OnlineVideoStream` / `OnlineAudioStream` lists in `OnlinePlaybackData` |  partial |
| `preferredVideoQualityId` support | `OnlinePlaybackOptions.preferredVideoQualityId` passed as Bilibili `qn` hint |  partial |
| `preferredAudioQualityId` support | `OnlinePlaybackOptions.preferredAudioQualityId` exists but is not used for filtering |  |
| Muxed fallback | `OnlineMuxedStream` + `allowMuxedFallback` |  |
| Stream URL expiration | `OnlineStream.expiresAt` inferred from URL/API |  partial |
| Stream `hasExpired()` method | No method; callers compare `expiresAt` or re-resolve |  |
| Player source creation via `buildUrl()` | `OnlineStream.url` |  |
| Player header handling | `OnlineStream.headers` |  |
| Backup URL handling | `OnlineStream.backupUrls` |  |

---

# 2. Stream and Result Model Fields

| Original Namida / YoutiPie model member | Our provider-neutral model member | Status |
|---|---|---|
| `VideoStreamsResult.audioStreams` | `OnlinePlaybackData.audioStreams` |  |
| `VideoStreamsResult.videoStreams` | `OnlinePlaybackData.videoStreams` |  |
| `VideoStreamsResult.mixedStreams` | `OnlinePlaybackData.muxedStreams` |  |
| `VideoStreamsResult.info` | `OnlinePlaybackData.media` |  partial |
| `VideoStreamsResult.playability` | No playability model |  |
| `VideoStreamsResult.hlsManifestUrl` | No HLS manifest parsing |  |
| `VideoStreamsResult.dashManifestUrl` | No separate DASH manifest URL; only stream URLs |  |
| `VideoStreamsResult.loudnessDBData` | No loudness/replay-gain data |  |
| `VideoStreamsResult.hasExpired()` | No method; only `expiresAt` fields |  |
| `VideoStream.sizeInBytes` | `OnlineStream.sizeInBytes` |  partial for DASH; often null |
| `VideoStream.duration` | `OnlineStream.duration` |  |
| `VideoStream.bitrate` | `OnlineStream.bitrate` |  |
| `VideoStream.width` | `OnlineVideoStream.width` |  |
| `VideoStream.height` | `OnlineVideoStream.height` |  |
| `VideoStream.fps` | `OnlineVideoStream.fps` |  |
| `VideoStream.codecInfo` / `codecs` | `OnlineStream.codec` + `rawCodec` + `codecFamily` |  partial |
| `VideoStream.itag` | No equivalent |  N/A |
| `VideoStream.isWebm` | No flag; `mimeType`/`codec` can be inspected |  partial |
| `VideoStream.buildUrl()` | `OnlineStream.url` |  |
| `VideoStream.cachePath(videoId)` | No cache path / lock-caching integration |  |
| `AudioStream` fields | `OnlineAudioStream` |  partial |
| `AudioStream.buildUrl()` | `OnlineAudioStream.url` |  |
| `AudioStream.cachePath(videoId)` | No cache path / lock-caching integration |  |
| `VideoStreamInfo` basic metadata | `OnlineMedia` title / artist / thumbnail / duration / description / parts |  partial |
| `VideoStreamInfo.channelId` | No channel/BVID owner id beyond `extra.ownerMid` |  partial |
| `VideoStreamInfo.channelName` | `OnlineMedia.artist` |  |
| `VideoStreamInfo.channelThumbnails` | No channel avatar list |  |
| `VideoStreamInfo.viewCount` | No view count |  |
| `VideoStreamInfo.releaseDate` | No publish date in core contract |  |
| `VideoStreamInfo.isLive` | No live support |  |
| `VideoInfo`, `VideoResult`, `YoutiPieVideoPageResult` rich page data | `OnlineMedia` + `extra` |  partial |
| `MissingVideoInfo` | No missing-video model |  |
| `VideoHeatMap` | No heatmap |  |
| `EndscreenItemBase` | No endscreen |  |
| `Caption` / caption tracks | No subtitles/captions |  |
| `AudioTrack` | No separate dubbing/audio-track language model |  |
| `StreamSegments` | No stream segment model |  |
| `SponsorBlockSegment(s)` | No SponsorBlock |  |
| `YoutiPieThumbnail` | `OnlineMedia.thumbnail` single URI |  partial |

---

# 3. Account, Login and Cookie Management

| Original Namida / YoutiPie interface | Our Bilibili interface | Status |
|---|---|---|
| `YoutiAccountManager.signIn(...)` | No Bilibili login flow |  |
| `YoutiPie.cookies` | `BilibiliAuthProvider` / `BilibiliSession` explicit cookie injection |  partial |
| `YoutiPie.cookies.signOut(userChannel)` | No sign-out API |  |
| `YoutiPie.cookies.setAccount(userChannel)` | No account switching |  |
| `YoutiPie.cookies.setAnonymous()` | `AnonymousBilibiliAuthProvider` / `BilibiliProvider.anonymous()` |  partial |
| `YoutiPie.cookies.activeAccountChannel` | No active-account model |  |
| `YoutiPie.cookies.signedInAccounts` | No multi-account storage |  |
| `YoutiPie.cookies.canAddMultiAccounts` | No multi-account setting |  |
| `YoutiPie.cookies.addOnAccountChanged(...)` | No account-change listener |  |
| `YoutiPie.activeAccountDetails` | No current-account model |  |
| `UserChannelInfo` | No Bilibili user info model |  |
| `YoutiLoginProgress` | No login-progress model |  |
| `AccountCookiesValidity` | No cookie-validity model |  |
| Cookie persistence in encrypted storage | No cookie store |  |
| `YoutubeAccountController.signIn(...)` | No Bilibili account controller |  |
| `YoutubeAccountController.signOut(...)` | No Bilibili account controller |  |
| `YoutubeAccountController.setAccountActive(...)` | No Bilibili account controller |  |
| `YoutubeAccountController.setAccountAnonymous()` | `BilibiliProvider.anonymous()` exists |  partial |
| `YoutubeAccountController.current` (YoutiPie.cookies) | No equivalent |  |
| Membership / Patreon / Supabase subscription integration | No Bilibili equivalent |  N/A |
| `YoutiPieOperation` account/membership gating | No equivalent |  N/A |

What we actually have:

```dart
abstract interface class BilibiliAuthProvider {
  Map<String, String> get requestHeaders;
  String? get cookieHeader;
}
```

```dart
class AnonymousBilibiliAuthProvider implements BilibiliAuthProvider
class SessionBilibiliAuthProvider implements BilibiliAuthProvider
class BilibiliSession
```

This only allows:

```text
caller supplies a cookie manually
BilibiliClient attaches cookie to requests
```

It does not provide:

```text
login
QR login
password login
cookie persistence
account switching
account info
favorites
history
subscriptions
```

---

# 4. User Personal Data

| Original Namida / YoutiPie interface | Our Bilibili interface | Status |
|---|---|---|
| `YoutubeInfoController.userplaylist.getUserPlaylists(...)` | No Bilibili favorites/playlist listing |  |
| `YoutubeInfoController.userplaylist.createPlaylist(...)` | No user playlist creation |  |
| `YoutubeInfoController.userplaylist.editPlaylist(...)` | No user playlist editing |  |
| `YoutubeInfoController.userplaylist.getPlaylistEditInfo(...)` | No playlist edit info |  |
| `YoutubeInfoController.userplaylist.addHostedPlaylistToLibrary(...)` | No remote playlist import |  |
| `YoutubeInfoController.userplaylist.removeHostedPlaylistFromLibrary(...)` | No remote playlist removal |  |
| `YoutubePlaylistController.favouriteButtonOnPressed(...)` | No Bilibili favorite/favourite toggle |  |
| Local favourite playlists | No Bilibili personal playlist model |  |
| `YoutubeInfoController.userchannel.fetchUserChannels(...)` | No Bilibili account channels/subscriptions |  |
| `YoutubeInfoController.userchannel.fetchUserChannelsAllVideos(...)` | No subscribed-channel video feed |  |
| `YoutubeInfoController.history.fetchHistory(...)` | No Bilibili account history |  |
| `YoutubeInfoController.history.markVideoWatched(...)` | No Bilibili history write |  |
| `YoutubeSubscriptionsController.toggleChannelSubscription(...)` | No Bilibili subscriptions |  |
| `YoutubeSubscriptionsController.saveFile()` | No subscription persistence |  |
| `YoutubeHistoryController` local history manager | No Bilibili history manager |  |
| Favorite/favlist URL support | Current parser rejects `space.bilibili.com/.../favlist` |  |
| Account profile / `nav` / `myinfo` | No current-user profile API |  |
| Account-owned videos / folders / collections | No user content APIs |  |

Relevant Bilibili account APIs that are not implemented:

```text
/x/web-interface/nav
/x/space/myinfo
/x/v3/fav/folder/created/list-all
/x/v3/fav/resource/list
/x/v2/history
/x/relation/followings
/x/v3/fav/folder/created/list-all
```

---

# 5. Search, Feed, Notifications and Social

| Original Namida / YoutiPie interface | Our Bilibili interface | Status |
|---|---|---|
| `YoutubeInfoController.search.getSuggestions(...)` | No search suggestions |  |
| `YoutubeInfoController.search.search(...)` | No Bilibili search |  |
| `YoutubeInfoController.feed` / `FeedResult` | No Bilibili feed/home |  |
| `YoutubeInfoController.notificationsAction` / `NotificationResult` | No notifications |  |
| `YoutubeInfoController.comment.fetchComments(...)` | No comments |  |
| `YoutubeInfoController.comment.fetchCommentReplies(...)` | No comment replies |  |
| `YoutubeInfoController.commentAction.createComment(...)` | No comment create |  |
| `YoutubeInfoController.commentAction.editComment(...)` | No comment edit |  |
| `YoutubeInfoController.commentAction.deleteComment(...)` | No comment delete |  |
| `YoutubeInfoController.commentAction.createReply(...)` | No reply create |  |
| `YoutubeInfoController.commentAction.editReply(...)` | No reply edit |  |
| `YoutubeInfoController.commentAction.deleteReply(...)` | No reply delete |  |
| `YoutubeInfoController.commentAction.changeLikeStatus(...)` | No comment like action |  |
| `RelatedVideosResult` | No related videos |  |
| `ChannelInfo`, `ChannelPageResult`, `ChannelTabResult`, `ChannelPageAbout` | No channel page support |  |
| `PlaylistResult`, `PlaylistUserResult`, `PlaylistMixResult` | No playlists/mix support |  |
| `YoutiPieHistoryResult` | No account history result |  |
| `YoutiPieSearchResult` | No search result |  |
| `YoutiPieFeedResult` | No feed result |  |
| `NotificationResult` | No notification result |  |

---

# 6. Download, Cache and Advanced Video Features

| Original Namida / YoutiPie interface | Our Bilibili interface | Status |
|---|---|---|
| YoutiPie stream `cachePath(videoId)` | No stream cache path |  |
| `_buildLockCachingAudioSource(...)` / `_buildLockCachingVideoSource(...)` | No lock-caching source adapter |  |
| `YoutubeController` download manager | No Bilibili download manager |  |
| Download progress model | No download progress |  |
| Audio cache controller integration | No Bilibili audio cache integration |  |
| Video cache controller integration | No Bilibili video cache integration |  |
| `SponsorBlockController` | No SponsorBlock |  N/A |
| `ReturnYouTubeDislike` | No Bilibili like/dislike equivalent |  |
| `POToken` | No Bilibili equivalent |  N/A |
| `YoutiPie.memoryCache` | No global provider memory cache |  |
| HLS live support | No live support |  |
| DASH live support | No live support |  |
| Bangumi / episode / season | No bangumi support |  |
| Paid / membership-only playback | No bypass; ordinary anonymous only |  N/A |
| DRM / region-lock bypass | Explicitly excluded |  N/A |
| Subtitles / captions | No subtitle tracks |  |
| Endscreens / cards | No endscreens |  |
| Heatmap / most replayed | No heatmap |  |
| Shorts detection | No short-content detection |  |
| Channel/avatar metadata | No channel avatar list |  partial |

---

# 7. What We Actually Implemented

| Our implemented interface | Status |
|---|---|
| `BilibiliProvider.canHandle(Uri)` |  |
| `BilibiliProvider.resolve(Uri)` |  |
| `BilibiliProvider.getPlayback(OnlineMediaId)` |  |
| `BilibiliClient.getVideoInfo(id)` |  |
| `BilibiliClient.getPlayback(bvid, cid, qn)` |  |
| `BilibiliClient.resolveShortUrl(Uri)` |  |
| `BilibiliUrlParser` |  |
| `BilibiliMetadataParser` |  |
| `BilibiliDashParser` |  |
| `parseFrameRate(String)` |  |
| `BilibiliStreamValidator` |  |
| `online_media_provider` DTOs and contract |  |
| BV / av / b23 support |  |
| BVID / CID / multi-part support |  |
| DASH audio / video stream separation |  |
| quality / codec / width / height / FPS / bitrate |  |
| per-stream headers |  |
| backup URLs |  |
| expiry inference |  partial |
| HTTP Range validation |  |
| standalone Flutter playback |  |

---

# 8. Summary

Implemented:

```text
ordinary public Bilibili video playback
```

Not implemented:

```text
login
cookies persistence
account info
favorites
user playlists
history
subscriptions
search
feed
notifications
comments
danmaku
downloads
live
bangumi
subtitles
advanced account/personal-data APIs
```

This matches the original MVP scope.

The next step, if desired, is to implement a separate Bilibili account/personal-data layer while keeping the playback provider contract unchanged.
