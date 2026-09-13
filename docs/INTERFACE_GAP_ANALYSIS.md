# Namida / YoutiPie Interface Gap Analysis

> Updated after Stage 8-9 (Bilibili account layer). See
> [BILIBILI_ACCOUNT_LAYER.md](BILIBILI_ACCOUNT_LAYER.md) for the implemented
> account/personal-data API. Sections 1, 2 and 5-6 are unchanged apart from the
> notes added at the end of this file.

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
| Stream `hasExpired()` method | `OnlineStreamExpiry.isExpired` extension on `OnlineStream` |  |
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
| `YoutiAccountManager.signIn(...)` | `BilibiliAccountManager.signIn(cookieHeader)` / `signInWithCookies(cookies)` |  |
| `YoutiPie.cookies` | `BilibiliCookies` + `BilibiliAccountAuthProvider` |  |
| `YoutiPie.cookies.signOut(userChannel)` | `BilibiliAccountManager.signOut(accountKey)` |  |
| `YoutiPie.cookies.setAccount(userChannel)` | `BilibiliAccountManager.switchAccount(accountKey)` |  |
| `YoutiPie.cookies.setAnonymous()` | `BilibiliAccountManager.setAnonymous()` (also `BilibiliProvider.anonymous()`) |  |
| `YoutiPie.cookies.activeAccountChannel` | `BilibiliAccountManager.activeAccountKey` |  |
| `YoutiPie.cookies.signedInAccounts` | `BilibiliAccountManager.signedInAccounts` |  |
| `YoutiPie.cookies.canAddMultiAccounts` | `allowMultipleAccounts` / `maxAccounts` / `canAddMultipleAccounts` |  |
| `YoutiPie.cookies.addOnAccountChanged(...)` | `BilibiliAccountManager.onAccountChanged` |  |
| `YoutiPie.activeAccountDetails` | `BilibiliAccountManager.activeAccountDetails` (`BilibiliAccountInfo`) |  |
| `UserChannelInfo` | `BilibiliAccountInfo` (mid, name, avatar, sign, level, counts) |  |
| `YoutiLoginProgress` | No login-progress model; sign-in is one validated call |  |
| `AccountCookiesValidity` | `BilibiliCookieValidity` / `BilibiliSessionState` |  |
| Cookie persistence in encrypted storage | `BilibiliCookieStore` + `ConditionalBilibiliCookieStore` + plain-text `PlainTextFileBilibiliCookieStore` (`io.dart`) |  partial |
| `YoutubeAccountController.signIn(...)` | `BilibiliAccountManager.signIn(...)` |  |
| `YoutubeAccountController.signOut(...)` | `BilibiliAccountManager.signOut(...)` |  |
| `YoutubeAccountController.setAccountActive(...)` | `BilibiliAccountManager.switchAccount(...)` |  |
| `YoutubeAccountController.setAccountAnonymous()` | `BilibiliAccountManager.setAnonymous()` |  |
| `YoutubeAccountController.current` (YoutiPie.cookies) | `BilibiliAccountManager.activeSession` / `authProvider` |  |
| QR-code / password / SMS login flow | Not implemented; explicit user-provided cookies only |  |
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
class BilibiliAccountAuthProvider implements BilibiliAuthProvider   // follows the active session
class BilibiliSession
```

Stage 8 added:

```text
BilibiliCookies                       redaction-safe cookie jar (parse / fromUserInput / Set-Cookie)
BilibiliCookieStore                   persistence boundary
InMemoryBilibiliCookieStore           default store; nothing is written to disk
ConditionalBilibiliCookieStore        runtime "remember this login" switch
PlainTextFileBilibiliCookieStore      io.dart entry point; plain-text file, opt-in
BilibiliCookieStoreState              stores cookies + the active account key
BilibiliAccountSession                accountId + cookies + name/avatar
BilibiliSessionState                  anonymous | authenticated | expired | csrfInvalid | unknown
BilibiliCookieValidity                cookie check result, never carries credentials
BilibiliAccountManager                restore / signIn / switch / signOut / setAnonymous
BilibiliAccountClient.getNav          x/web-interface/nav
BilibiliAccountClient.getMyInfo       x/space/myinfo
BilibiliAccountParser                 nav + myinfo parsing
```

This still does **not** provide:

```text
QR login
password login
an encrypted (keychain / DPAPI) cookie store
```

---

# 4. User Personal Data

| Original Namida / YoutiPie interface | Our Bilibili interface | Status |
|---|---|---|
| `YoutubeInfoController.userplaylist.getUserPlaylists(...)` | `BilibiliAccountClient.getCreatedFavoriteFolders(mid:)` |  partial |
| `YoutubeInfoController.userplaylist.createPlaylist(...)` | No Bilibili favorite-folder creation |  |
| `YoutubeInfoController.userplaylist.editPlaylist(...)` | No favorite-folder editing/renaming |  |
| `YoutubeInfoController.userplaylist.getPlaylistEditInfo(...)` | `BilibiliAccountClient.getFavoriteFolderInfo(mediaId:)` |  partial |
| `YoutubeInfoController.userplaylist.addHostedPlaylistToLibrary(...)` | No remote playlist import |  |
| `YoutubeInfoController.userplaylist.removeHostedPlaylistFromLibrary(...)` | No remote playlist removal |  |
| `YoutubePlaylistController.favouriteButtonOnPressed(...)` | `BilibiliAccountClient.addFavorite` / `removeFavorite` / `dealFavorite` |  |
| Local favourite playlists | `BilibiliFavoriteFolder` + `BilibiliFavoritePage` |  partial |
| `YoutubeInfoController.userchannel.fetchUserChannels(...)` | No Bilibili following list |  |
| `YoutubeInfoController.userchannel.fetchUserChannelsAllVideos(...)` | No subscribed-UP video feed |  |
| `YoutubeInfoController.history.fetchHistory(...)` | No Bilibili account history |  |
| `YoutubeInfoController.history.markVideoWatched(...)` | No Bilibili history write |  |
| `YoutubeSubscriptionsController.toggleChannelSubscription(...)` | No Bilibili subscriptions |  |
| `YoutubeSubscriptionsController.saveFile()` | No subscription persistence |  |
| `YoutubeHistoryController` local history manager | No Bilibili history manager |  |
| Favorite/favlist URL support | `BilibiliFavListUrlParser` (kept out of `BilibiliProvider.canHandle`) |  |
| Account profile / `nav` / `myinfo` | `getNav` / `getMyInfo` / `BilibiliAccountInfo` |  |
| Account-owned videos / folders / collections | Favorite folders only; collections are Stage 12 |  partial |
| Favorite paging | `getFavoriteResources`, `paginateFavoriteResources`, `getAllFavoriteMedia` |  |
| Favorite item -> playable media | `BilibiliAccountParser.toOnlineMedia` + `BilibiliProvider.resolveById` |  |

Relevant Bilibili account APIs and their current state:

```text
/x/web-interface/nav                    implemented
/x/space/myinfo                         implemented
/x/v3/fav/folder/created/list-all       implemented
/x/v3/fav/folder/info                   implemented
/x/v3/fav/resource/list                 implemented (paged)
/x/v3/fav/resource/deal                 implemented (add / remove)
/x/v2/history                           Stage 10
/x/relation/followings                  Stage 11
/x/polymer/web-space/seasons_series_list Stage 12
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
| `BilibiliAccountClient.getNav` / `getMyInfo` |  |
| `BilibiliAccountManager` (signIn / signOut / setAnonymous / switching) |  |
| `BilibiliCookies` + `BilibiliCookieStore` |  |
| `BilibiliFavListUrlParser` |  |
| favorite folder listing / paging / add / remove |  |
| `BilibiliProvider.resolveById` (favorites -> playable bridge) |  |

---

# 8. Summary

Implemented:

```text
ordinary public Bilibili video playback
explicit-cookie Bilibili sign-in, account switching and sign-out
current account profile (nav / myinfo)
favorite folders, paged favorite items, favorite add/remove
favorite-list URL parsing
```

Not implemented:

```text
QR / password / SMS login
an encrypted cookie store implementation (interface only)
history
subscriptions / following
user playlists / collections
search
feed
notifications
comments
danmaku
downloads
live
bangumi
subtitles
```

This matches the intended scope of the account-layer stages. The playback
provider contract is unchanged; the only addition is the additive
`BilibiliProvider.resolveById` bridge, which favorite/history/playlist items need
because those APIs never expose a CID.

Next stages are history (Stage 10), following/subscriptions (Stage 11), and user
playlists/collections (Stage 12). See
[BILIBILI_ACCOUNT_LAYER.md](BILIBILI_ACCOUNT_LAYER.md).
