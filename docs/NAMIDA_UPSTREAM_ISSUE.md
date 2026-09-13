# Draft: upstream issue for namidaco/namida

Status: **draft for review, not posted.** Nothing in the repository depends on it.

Suggested title:

```text
[Feature request] Pluggable online-video providers (Bilibili provider ready to plug in)
```

---

## Body

### TL;DR

I built a standalone Bilibili provider (playback + account/favorites, 231 offline
tests, real playback verified on Windows) that depends on neither Namida nor
`youtipie`:

https://github.com/DiWu17/namida-bilibili-provider

Namida cannot use it today, because `PlayableExecuter.execute()` only recognizes
`Selectable` and `YoutubeID`, and anything else resolves to `null`. This issue asks
for a small, backwards-compatible hook so a third-party provider can plug in.

I am **not** asking you to bundle anything, to publish `youtipie`, or to change how
the YouTube side works.

### Why this exists outside Namida

`youtipie` and `namico_login_manager` are private git dependencies
(`https://api.github.com/repos/namidaco/youtipie` returns 404), so nobody outside
the project can build, run, or test a new online provider against Namida. Rather
than ask you to do all of the Bilibili work, I did it on my side and kept the
boundary thin.

### What already exists there

- a provider-neutral contract: `OnlineMedia`, `OnlineMediaId`, `OnlineMediaPart`,
  `OnlineAudioStream`, `OnlineVideoStream`, `OnlineMuxedStream`,
  `OnlinePlaybackData`;
- DASH video and audio kept as separate streams with per-stream headers, backup
  URLs, codec/quality/resolution/FPS/bitrate, and expiry information;
- an account layer: scan-to-login (Bilibili's own QR flow), cookie storage,
  account switching, sign-out, current profile, favorite folders with paging and
  add/remove, all unit-tested against fixtures.

The complete public surface is documented in one file, so there is no need to read
the source: **[docs/INTERFACE_REFERENCE.md](https://github.com/DiWu17/namida-bilibili-provider/blob/master/docs/INTERFACE_REFERENCE.md)**
(every type, signature, endpoint, and guarantee).

`docs/INTERFACE_GAP_ANALYSIS.md` compares Namida's YouTube side with this provider
row by row, including what is still missing.

### The exact blocker, verified against current `main`

**1. Playable dispatch is hard-coded to two types** — `lib/base/audio_handler.dart`:

```dart
extension PlayableExecuter on Playable {
  T? execute<T>({
    required T Function(Selectable finalItem) selectable,
    required T Function(YoutubeID finalItem) youtubeID,
  }) {
    final item = this;
    if (item is Selectable) {
      return selectable(item);
    } else if (item is YoutubeID) {
      return youtubeID(item);
    }
    return null;                       // <- a third-party playable stops here
  }
}
```

`executeAsync` is identical. So `onItemPlay()`, `prepareItem()`, queue
separation, and the item properties all fall through to `null` for any new
`Playable` type, and `_itemToPrepareConfigSelectable` /
`_itemToPrepareConfigYoutubeID` / `onItemPlayYoutubeID` /
`onItemPlayYoutubeIDSetQuality` / `onItemPlayYoutubeIDSetAudio` have no third
branch to call.

**2. The stream builders are typed to YoutiPie models**, same file:

```dart
UriSource _buildLockCachingAudioSource(Uri uriDDL,
  {required AudioStream stream, required String videoId, required VideoStreamsResult? streamsResult}) { ... }

UriSource _buildLockCachingVideoSource(Uri uriDDL,
  {required VideoStream stream, required String videoId, required VideoStreamsResult? streamsResult}) { ... }
```

**3. Good news: header plumbing already exists**, it just is not reachable from the
DASH path:

```dart
// line ~2804: headers is already an optional parameter ...
UriSource _buildCacheableAVSource(Uri uriDDL, {
  required int? size,
  Map<String, String>? headers,          // <-- already here
  required File cacheFile,
  ...
}) {
  ...
  return AudioVideoSource.uri(cacheUrl, headers: headers, onDispose: disposeStream);  // line ~2828
}
```

and `AudioVideoSource.uri(uri, headers: uriDDLInfo.headers)` is already used for
track sources (line ~2877). The only gap is that `_buildAVSource` (line ~2579) does
not accept or forward `headers`, so the DASH/lock-caching path always passes
`null`.

**4. UI coupling** — `VideoController.currentVideoConfig.currentYTStreams` is
`Rxn<VideoStreamsResult>`, and the quality sheet in `FocusedMenuOptions` is typed
to YoutiPie `VideoStream`/`AudioStream`. I am **not** asking to change that now.

### A possible shape for the hook (just a sketch)

I am deliberately not prescribing a patch. Anything I write about your side is
guesswork, because I cannot compile against Namida, and you know the player far
better than I do. What I can offer is the shape that would need the fewest changes
on your side:

1. an optional third branch in `PlayableExecuter.execute`/`executeAsync` — an
   optional parameter, so every existing call site keeps compiling and YouTube
   behaviour is unchanged;
2. a provider-neutral marker for online items, e.g.
   `abstract interface class OnlinePlayable { OnlineMediaId get onlineMediaId; }`,
   so a Bilibili item is a new `Playable` instead of a fake `YoutubeID`;
3. a resolver the app installs: `bool canHandle(item)` plus
   `Future<ResolvedStreams> resolve(item)` returning `audioUrl`/`audioHeaders`,
   `videoUrl`/`videoHeaders`, and an optional muxed URL;
4. somewhere for those URLs to reach `AudioVideoSource.uri(url, headers: ...)`.

On point 4 there is one concrete gap I did verify, and it is worth checking first:
`_buildCacheableAVSource` already accepts `headers` and forwards them to
`AudioVideoSource.uri(cacheUrl, headers: headers, ...)` (~line 2828), but
`_buildAVSource` (~line 2579) neither accepts nor forwards `headers`, so the
DASH/lock-caching path always passes `null`. Bilibili CDN URLs need `Referer` and
`User-Agent`, so without one more parameter on that path the result is
"metadata resolves, playback 403s".

Whether the real answer is a callback, a registry, a `Playable` subclass, or
something else entirely is your call. If you tell me the shape, I will implement it
on my side.

### What I am not asking for

- no changes to `youtipie`, and no need for it to be public;
- no paid, DRM, membership, or region-lock bypass — the provider only requests
  what an anonymous or signed-in user may already watch, and it implements no such
  unlock at all;
- no bundling of my package in Namida's repository;
- no change to membership gating: I noticed `_checkCanSignIn()` ties sign-in to
  Patreon/Supabase tiers. That is your decision and I am not touching it. The
  Bilibili account layer has no membership concept and needs no YoutiPie
  operation.
- no change to the existing quality UI; auto-select first.

### Account side (optional, for later)

The account layer was written to the same shape your YouTube side uses, so an
adapter stays thin:

| Namida / YoutiPie | provider side |
|---|---|
| `YoutiAccountManager.signIn(pageConfig:, onProgress:)` | `signInWithQrCode(onProgress:, pollInterval:, timeout:, isCancelled:)` |
| `YoutiLoginProgress` | `BilibiliQrLoginStage` (pending/scanned/confirmed/expired/failed) |
| `YoutiPie.cookies.signedInAccounts` | `signedInAccounts` |
| `YoutiPie.cookies.activeAccountChannel` | `activeAccountKey` |
| `YoutiPie.cookies.setAccount` / `signOut` / `setAnonymous` | `switchAccount` / `signOut` / `setAnonymous` |
| `YoutiPie.activeAccountDetails` | `activeAccountDetails` |
| `AccountCookiesValidity` | `BilibiliCookieValidity` |

Sign-in uses Bilibili's native QR flow (user scans in the Bilibili app and
confirms on their device), so there is no password, captcha, or webview, and
therefore no need for a `LoginPageConfiguration`-style navigator callback.

### Verification, and what is not verified

Verified here:

- 231 offline tests (fixtures + mocked HTTP, no network);
- 9 tagged online tests, 4 of which need no credentials at all;
- real playback in a standalone Flutter app, `flutter build windows --debug`
  succeeds, and scan-to-login was confirmed by hand on Windows.

**Not** verified: anything against Namida itself. I cannot compile against your
private dependencies, so the integration notes in this issue are reasoned from the
public source only, not tested.

### Question

Would a pluggable provider hook be something you would consider? If so, I would
rather you pick the boundary:

1. the optional `onlinePlayable` callback sketched above,
2. a resolver registry / interface you define, which I then implement, or
3. a different approach entirely — for example keeping the hook outside
   `Playable` if that fits better.

I will adapt to whatever shape suits Namida, and I am happy to turn the reference
patch into a pull request if you would like to try it out.
