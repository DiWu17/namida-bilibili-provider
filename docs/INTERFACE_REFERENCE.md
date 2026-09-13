# Provider Interface Reference

The complete public surface of `bilibili_provider`, written so an integrator can
read one file instead of the source.

Status: matches stages 0-9 (playback, account layer, scan-to-login, favorites).

Two packages are involved:

| Package | Role |
|---|---|
| `online_media_provider` | provider-neutral contract and DTOs; knows nothing about Bilibili |
| `bilibili_provider` | Bilibili implementation: HTTP, parsers, provider, account layer |

Nothing here depends on Namida or on `youtipie`.

## 1. Entry points

```dart
// Playback + account layer. Contains no dart:io, so it is web-safe.
import 'package:bilibili_provider/bilibili_provider.dart';

// Opt-in: filesystem-backed cookie store for desktop/server.
import 'package:bilibili_provider/io.dart';
```

Importing the main library can never write credentials to disk; persistence needs
the explicit second import.

## 2. Playback contract

### 2.1 `OnlineMediaProvider` (online_media_provider)

```dart
abstract interface class OnlineMediaProvider {
  String get providerId;
  bool canHandle(Uri uri);
  Future<OnlineMedia> resolve(Uri uri, {OnlineMediaResolveOptions options});
  Future<OnlinePlaybackData> getPlayback(OnlineMediaId mediaId,
      {OnlinePlaybackOptions options});
}
```

### 2.2 `BilibiliProvider implements OnlineMediaProvider`

```dart
BilibiliProvider({
  BilibiliClient? client,
  BilibiliUrlParser? urlParser,
  BilibiliMetadataParser? metadataParser,
  BilibiliDashParser? playbackParser,
  BilibiliAuthProvider? auth,
  bool debug = false,
});
BilibiliProvider.anonymous({...});            // identical defaults
```

| Member | Behaviour |
|---|---|
| `providerId` | `'bilibili'` |
| `canHandle(Uri)` | true for `/video/BV...`, `/video/av...`, `b23.tv/...`. **False** for `space.bilibili.com/.../favlist` (a folder is not a video) |
| `resolve(uri, {options})` | metadata + parts. Resolves `b23.tv` short links (bounded redirects). `options.preferredPartIndex` is zero-based and only applies when the URL has no `?p=` |
| `getPlayback(mediaId, {options})` | fresh DASH (or muxed) streams. Requires `mediaId.subId` (the CID) |
| `resolveById(mediaId, {options})` | re-resolves metadata + parts for an id that has **no** CID (favorites, history, playlists) so the result can be passed to `getPlayback` |
| `client` | the underlying `BilibiliClient`, exposed for adapters/tests |
| `debug` | diagnostics only; must never log credentials, and no sink exists unless the client was given one |

Errors: wrong provider on `getPlayback`/`resolveById` →
`BilibiliUnsupportedContentException`; missing CID → `BilibiliNotFoundException`;
muxed-only response without `allowMuxedFallback` →
`BilibiliUnsupportedContentException`.

### 2.3 Options (online_media_provider)

```dart
class OnlineMediaResolveOptions {
  const OnlineMediaResolveOptions({this.preferredPartIndex});
  final int? preferredPartIndex;          // zero-based
}

class OnlinePlaybackOptions {
  const OnlinePlaybackOptions({
    this.preferredVideoQualityId,          // Bilibili `qn` hint
    this.preferredAudioQualityId,          // accepted, not used for filtering yet
    this.allowMuxedFallback = false,
  });
}
```

## 3. Provider-neutral DTOs (online_media_provider)

### 3.1 `OnlineMediaId`

```dart
const OnlineMediaId({required String provider, required String id, String? subId});
```

For Bilibili: `provider = 'bilibili'`, `id` = BVID, `subId` = CID when a part is
selected. Value equality on all three fields.

### 3.2 `OnlineMedia` and `OnlineMediaPart`

```dart
class OnlineMedia {
  final OnlineMediaId id;
  final String title;
  final String? artist;        // Bilibili UP name
  final Uri? thumbnail;
  final Duration? duration;
  final String? description;
  final List<OnlineMediaPart> parts;
  final Map<String, Object?> extra;   // non-contract; do not depend on it

  OnlineMediaPart? partForSubId(String? subId);  // null subId -> first part
}

class OnlineMediaPart {
  final String id;      // Bilibili CID
  final String title;
  final int index;      // zero-based
  final Duration? duration;
}
```

`extra` keys Bilibili sets today: `aid`, `ownerMid`, and for favorites
`favoriteFolderId`, `favoriteTime`, `publishTime`, `invalid`.

### 3.3 `OnlinePlaybackData`

```dart
class OnlinePlaybackData {
  final OnlineMedia media;
  final List<OnlineAudioStream> audioStreams;
  final List<OnlineVideoStream> videoStreams;
  final List<OnlineMuxedStream> muxedStreams;   // optional fallback only
  final DateTime? expiresAt;                    // earliest known expiry

  bool get hasStreams;
}
```

The split audio/video model is the contract: a provider must not fake a muxed URL.

### 3.4 Streams

Common members (`OnlineStream`):

```dart
Uri get url;
List<Uri> get backupUrls;
Map<String, String> get headers;   // MUST be sent with url and backupUrls
String get mimeType;
String? get codec;                 // raw, e.g. avc1.640028
String? get rawCodec;              // alias, never loses the raw value
OnlineCodecFamily get codecFamily; // avc, hevc, av1, aac, opus, unknown
int? get bitrate;
int? get sizeInBytes;
Duration? get duration;
DateTime? get expiresAt;

extension OnlineStreamExpiry on OnlineStream {
  bool get isExpired;              // expiresAt known and already past
}
```

Concrete types add an `id` string and their own extras:

| Type | Extras |
|---|---|
| `OnlineVideoStream` | `qualityId`, `qualityLabel`, `width`, `height`, `fps` |
| `OnlineAudioStream` | `qualityId`, `qualityLabel`, `sampleRate`, `channels` |
| `OnlineMuxedStream` | video + audio fields combined |

Bilibili CDN URLs need `Referer: https://www.bilibili.com/` and a browser-like
`User-Agent`; `headers` carries them, and `Cookie` only when a session is active.

## 4. Exceptions

```text
OnlineMediaException                     base (message, cause, stackTrace)
  OnlineMediaNetworkException            transport, statusCode
  OnlineMediaNotFoundException           platformErrorCode
  OnlineMediaAccessDeniedException       platformErrorCode, httpStatusCode
  OnlineMediaUnsupportedException
  OnlineMediaRateLimitException          retryAfter
  OnlineMediaParseException

BilibiliException extends OnlineMediaException    adds httpStatusCode, platformErrorCode
  BilibiliNetworkException
  BilibiliNotFoundException
  BilibiliAccessDeniedException
  BilibiliAuthenticationException        -101 not signed in / -111 bad csrf
  BilibiliApiException
  BilibiliParseException
  BilibiliUnsupportedContentException
  BilibiliRateLimitException             adds retryAfter
```

Platform codes mapped today: `-404`/`404` → not found, `-401`/`-403`/`62002`/
`62004` → access denied, `-101`/`-111` → authentication, `-509`/`-799` → rate
limit, everything else → `BilibiliApiException`. HTTP 401/403 → access denied,
404 → not found, 429 → rate limit.

**No exception message ever contains a cookie, csrf token, QR ticket, or stream
URL.** Messages are fixed text plus platform codes.

## 5. Account layer

Optional, additive, and never required for playback.

### 5.1 `BilibiliCookies`

```dart
BilibiliCookies([Map<String, String> values]);
factory BilibiliCookies.parse(String? rawCookieHeader);
factory BilibiliCookies.fromSetCookieHeaders(Iterable<String> setCookieHeaders);
factory BilibiliCookies.fromUserInput(String raw);   // paste-tolerant
static final BilibiliCookies empty;
static const String sessDataName = 'SESSDATA';
static const String csrfName = 'bili_jct';
static const String userIdName = 'DedeUserID';
static const String userIdCheckName = 'DedeUserID__ckMd5';
static const String sessionIdName = 'sid';

Map<String, String> get values;     // insertion ordered
bool get isEmpty / isNotEmpty;
int get length;
String? operator [](String name);
String? get sessData;               // credential
String? get csrfToken;              // credential, sent as `csrf`
int? get userId;                    // mid
bool get hasSessionToken;
bool get hasCsrfToken;
String get cookieHeader;            // credential: HTTP only
BilibiliCookies withValues(Map<String, String> overrides);
BilibiliCookies merge(BilibiliCookies other);       // other wins
BilibiliCookies without(Iterable<String> names);
String get redactedSummary;         // '<redacted: N cookie(s)>'
```

`fromUserInput` accepts a raw header, a `Cookie:` prefix, one pair per line,
quotes, and `Set-Cookie` attribute noise. `toString()` prints cookie **names**
only, never values.

### 5.2 Cookie stores

```dart
class BilibiliCookieStoreState {
  final Map<String, BilibiliCookies> accounts;   // key = mid
  final String? activeAccountKey;
  static final BilibiliCookieStoreState empty;
  bool get isEmpty;
  BilibiliCookieStoreState copyWith({..., bool clearActiveAccount = false});
}

abstract interface class BilibiliCookieStore {
  Future<BilibiliCookieStoreState> read();          // empty when nothing stored
  Future<void> write(BilibiliCookieStoreState state);
  Future<void> clear();
}
```

| Implementation | Library | Notes |
|---|---|---|
| `InMemoryBilibiliCookieStore` | main | default; nothing touches disk |
| `ConditionalBilibiliCookieStore(inner, {persist = true})` | main | `write` is dropped while `persist == false`; `read`/`clear` still delegate |
| `PlainTextFileBilibiliCookieStore({Directory? directory, String fileName})` | `io.dart` | JSON file, **plain text** |

`PlainTextFileBilibiliCookieStore` extras:

```dart
static const String defaultFileName = 'bilibili_account_cookies.json';
static const String appFolderName = 'namida_bilibili_provider';
static const int payloadVersion = 1;
static Directory defaultDirectory({Map<String, String>? environment, String? operatingSystem});
static Map<String, Object?> encodeState(BilibiliCookieStoreState state);
static BilibiliCookieStoreState decodeState(String raw);

Directory get directory;
File get file;
Future<bool> exists();
```

Default location: `%APPDATA%\namida_bilibili_provider\...` on Windows,
`~/Library/Application Support/...` on macOS,
`$XDG_DATA_HOME` or `~/.local/share` elsewhere. A missing, unreadable, or
malformed file reads as "no saved login" instead of failing startup. `toString()`
shows the path only, never the payload.

### 5.3 Session and validity

```dart
enum BilibiliSessionState { anonymous, authenticated, expired, csrfInvalid, unknown }

class BilibiliCookieValidity {
  final BilibiliSessionState state;
  final DateTime? checkedAt;
  final int? platformErrorCode;
  final String? message;
  static const BilibiliCookieValidity unchecked;
  bool get isAuthenticated;
  bool get isAnonymous;
  bool get requiresSignIn;      // expired || csrfInvalid
}

class BilibiliAccountSession {
  final String accountId;       // mid as string, or 'anonymous'
  final BilibiliCookies cookies;
  final String? name;
  final Uri? avatar;
  final bool isAnonymous;
  static final BilibiliAccountSession anonymous;
  static const String anonymousAccountId = 'anonymous';
  int? get mid;
  bool get hasSessionToken;
  BilibiliAccountSession copyWith({...});
}
```

Both types redact `toString()`.

### 5.4 Auth providers

```dart
abstract interface class BilibiliAuthProvider {
  Map<String, String> get requestHeaders;
  String? get cookieHeader;
}

const AnonymousBilibiliAuthProvider();                  // default: no cookie
class BilibiliSession { BilibiliSession({String? cookie, String userAgent}); }
const SessionBilibiliAuthProvider(BilibiliSession session);   // fixed cookie

class BilibiliAccountAuthProvider {                     // follows the active session
  BilibiliAccountAuthProvider([BilibiliAccountSession? session]);
  BilibiliAccountSession get session;
  void setSession(BilibiliAccountSession session);
}
const String defaultBilibiliUserAgent;
```

### 5.5 `BilibiliAccountManager`

```dart
BilibiliAccountManager({
  BilibiliAccountClient? client,
  BilibiliAccountAuthProvider? authProvider,
  BilibiliCookieStore? cookieStore,       // default: in-memory
  bool allowMultipleAccounts = true,
  int maxAccounts = 5,
});
```

| Member | Behaviour |
|---|---|
| `restore()` | loads persisted cookies and the previously active account; no network, no profile fetch |
| `getCurrentAccount({forceRefresh = false})` | profile, or `null` when expired. Never throws for "expired"; transport/parse errors do throw. Cached until `forceRefresh` |
| `validateActiveCookies({forceRefresh = true})` | `BilibiliCookieValidity`; anonymous resolves locally without a request |
| `signIn(String cookieHeader)` | parses then delegates to `signInWithCookies` |
| `signInWithCookies(BilibiliCookies)` | requires `SESSDATA`, validates through `nav`, then adopts. A rejected jar throws `BilibiliAuthenticationException` and leaves the previous session untouched |
| `signInWithQrCode({onProgress, pollInterval = 2s, timeout = 3min, isCancelled})` | scan-to-login; returns the session, or `null` on expiry/timeout/cancel. Confirmed cookies go through `signInWithCookies` |
| `switchAccount(String accountKey)` | makes a stored account active; unknown key → `BilibiliNotFoundException` |
| `signOut([String? accountKey])` | drops an account (active by default); the active slot falls back to another account, else anonymous |
| `signOutAll()` | drops every account **and clears the store** |
| `setAnonymous()` | keeps accounts but sends no cookies |
| `activeSession`, `activeAccountKey`, `activeAccountDetails`, `cookieValidity`, `isAnonymous`, `signedInAccounts`, `canAddMultipleAccounts`, `allowMultipleAccounts`, `maxAccounts` | state |
| `onAccountChanged` | `Stream<BilibiliAccountSession>`; emits on sign-in/switch/sign-out/anonymous, not on profile refresh |
| `authProvider` | the live `BilibiliAccountAuthProvider`; share it with any other client |
| `client` | the `BilibiliAccountClient` in use |
| `createMediaProvider({debug = false})` | a `BilibiliProvider` that shares the session |
| `dispose()` | closes the change stream |

Only cookies are persisted; `name`/`avatar` are re-derived from `nav` on demand.
`signOutAll()` is what a "delete my saved login" button should call.

### 5.6 Account DTOs

```dart
class BilibiliAccountInfo {          // nav + myinfo
  final int mid; final String name; final Uri? avatar; final String? sign;
  final int? level; final double? coins;
  final int? followingCount; final int? followerCount;
  final String? birthday; final bool isVip; final String? vipLabel;
}

class BilibiliNavResult {
  final int? code; final String message;
  final BilibiliCookieValidity validity;
  final BilibiliAccountInfo? account;
  bool get isLogin;
}

class BilibiliFavoriteFolder {
  final int mediaId; final String title; final int? ownerMid;
  final int mediaCount; final Uri? cover; final String? intro;
  final bool isPublic;
}

class BilibiliFavoriteItem {
  final int aid; final String bvid; final String title;
  final String? intro; final Uri? cover; final Duration? duration;
  final BilibiliOwner? owner; final DateTime? favoriteTime;
  final DateTime? publishTime; final int attr;
  bool get isInvalid;      // attr bit 0, or a "已失效视频" title
  bool get isPlayable;     // !isInvalid && bvid.isNotEmpty
}

class BilibiliFavoritePage {
  final List<BilibiliFavoriteItem> entries;  // raw, includes invalid
  final List<OnlineMedia> media;             // mapped, invalid excluded, no CID
  final int folderId; final int page; final int pageSize;
  final bool hasMore; final int? totalCount;
  final BilibiliFavoriteFolder? folder;
  bool get isEmpty;
}

enum BilibiliFavoriteOrder { favoriteTime('mtime'), viewCount('view') }
enum BilibiliFavoriteAction { add('add_media_ids'), remove('del_media_ids') }
```

`BilibiliOwner { int? mid; String? name; Uri? avatar; }` comes from
`bilibili_api_models.dart` and is shared with playback metadata.

### 5.7 QR login (scan to log in)

```dart
class BilibiliQrLogin {
  final String qrcodeKey;   // single-use ticket
  final Uri uri;            // content to render as a QR image; single-use ticket
  String toString();        // 'BilibiliQrLogin(<redacted>)'
}

enum BilibiliQrLoginStage { pending, scanned, confirmed, expired, failed }

class BilibiliQrLoginStatus {
  final BilibiliQrLoginStage stage;
  final BilibiliQrLogin? login;     // attached by the manager, so a UI has the QR
  final String? message;            // never contains credentials
  final BilibiliCookies? cookies;   // only when confirmed
  final String? refreshToken;       // never log
  bool get isConfirmed;
  bool get isTerminal;
  BilibiliQrLoginStatus withLogin(BilibiliQrLogin login);
}
```

Platform states (the state lives in `data.code` while the envelope `code` is `0`):

```text
86101 -> pending     未扫码
86090 -> scanned     已扫码未确认
0     -> confirmed   cookies delivered
86038 -> expired     二维码已过期
other -> failed
```

Cookies are taken from `Set-Cookie` headers and/or the cross-domain `data.url`,
merged with the headers winning; only known cookie names are accepted from the
URL. A confirmation without a usable session is reported as `failed`, not adopted.

## 6. Lower-level clients and parsers

### 6.1 Playback client and parsers

```dart
class BilibiliClient {
  BilibiliClient({BilibiliAuthProvider auth = const AnonymousBilibiliAuthProvider(),
                  BilibiliMetadataParser? metadataParser,
                  BilibiliDashParser? playbackParser,
                  BilibiliUrlParser? urlParser,
                  http.Client? httpClient, bool debug = false,
                  Duration requestTimeout = const Duration(seconds: 15),
                  int maxShortLinkRedirects = 5,
                  void Function(String message)? onDebugLog});
  Future<BilibiliVideoInfo> getVideoInfo({required String id});          // BVID or av
  Future<BilibiliPlaybackResponse> getPlayback({required String bvid,
                                                required String cid, int? qn});
  Future<Uri> resolveShortUrl(Uri shortUri);
}

class BilibiliUrlParser { bool canHandle(Uri); BilibiliMediaRef parse(Uri); }
class BilibiliMediaRef { BilibiliMediaIdKind kind; String id; Uri source; int? page;
                         bool get isShortLink; String get platformVideoId; }
enum BilibiliMediaIdKind { bvid, aid, shortLink }

class BilibiliMetadataParser {
  BilibiliVideoInfo parseVideoInfoResponse(String body);
  BilibiliVideoInfo parseVideoInfoData(Map<String, Object?> data);
  OnlineMedia toOnlineMedia(BilibiliVideoInfo info, {int? selectedPage});
}

class BilibiliDashParser {
  BilibiliPlaybackResponse parsePlaybackResponse(String body,
      {Map<String, String> headers = const <String, String>{}});
  BilibiliPlaybackResponse parsePlaybackData(Map<String, Object?> data,
      {Map<String, String> headers = const <String, String>{}});
  OnlinePlaybackData toOnlinePlaybackData(BilibiliPlaybackResponse response,
      OnlineMedia media, {OnlinePlaybackOptions options = const OnlinePlaybackOptions()});
}
```

Internal-but-exported platform models: `BilibiliVideoInfo`, `BilibiliPart`,
`BilibiliOwner`, `BilibiliDashVideoStream`, `BilibiliDashAudioStream`,
`BilibiliMuxedStream`, `BilibiliPlaybackResponse`.

### 6.2 `BilibiliAccountClient`

```dart
BilibiliAccountClient({
  BilibiliAuthProvider? auth,
  BilibiliAccountParser? parser,
  BilibiliFavListUrlParser? favListUrlParser,
  http.Client? httpClient,
  bool debug = false,
  Duration requestTimeout = 15s,
  void Function(String)? onDebugLog,
});
static const int maxFavoritePageSize = 20;
static const int defaultFavoritePageSize = 20;
```

| Method | Endpoint | Notes |
|---|---|---|
| `getNav({BilibiliCookies? cookies})` | `GET x/web-interface/nav` | current account + validity; `cookies` overrides the provider for one request (candidate validation) |
| `getMyInfo({int? mid})` | `GET x/space/myinfo` | profile; requires a session |
| `generateQrLogin()` | `GET x/passport-login/web/qrcode/generate` | issues a ticket |
| `pollQrLogin(BilibiliQrLogin)` | `GET x/passport-login/web/qrcode/poll?qrcode_key=` | one observation |
| `getCreatedFavoriteFolders({required int mid})` | `GET x/v3/fav/folder/created/list-all` | includes private folders |
| `getFavoriteFolderInfo({required int mediaId})` | `GET x/v3/fav/folder/info` | |
| `getFavoriteResources({mediaId, page = 1, pageSize = 20, keyword, order})` | `GET x/v3/fav/resource/list` | one page; `pageSize` must be 1..20 |
| `paginateFavoriteResources({mediaId, pageSize, startPage, maxPages = 50, keyword, order})` | same | `Stream<BilibiliFavoritePage>` |
| `getAllFavoriteMedia({mediaId, pageSize, maxPages = 50, keyword, order})` | same | deduplicated `List<OnlineMedia>` |
| `getFavoriteResourcesFromUri(Uri favListUri, {...})` | same | parses a `favlist` link first |
| `addFavorite({required int aid, required List<int> folderIds})` | `POST x/v3/fav/resource/deal` | `add_media_ids` + `csrf` |
| `removeFavorite({required int aid, required List<int> folderIds})` | same | `del_media_ids` + `csrf` |
| `dealFavorite({required int aid, required BilibiliFavoriteAction action, required List<int> folderIds})` | same | explicit form |

`aid` is the numeric archive id (`rid`), **not** a BVID. Writes need a session
with `bili_jct`; without it they throw `BilibiliAuthenticationException` **before
sending anything**, and they are never retried automatically.

### 6.3 `BilibiliAccountParser`

```dart
static const String providerId = 'bilibili';

BilibiliNavResult parseNavResponse(String body, {DateTime? now, bool sentSessionToken = false});
BilibiliQrLogin parseQrLoginGenerateResponse(String body);
BilibiliQrLoginStatus parseQrLoginPollResponse(String body, {List<String> setCookieHeaders});
BilibiliAccountInfo parseMyInfoResponse(String body);
List<BilibiliFavoriteFolder> parseCreatedFolderListResponse(String body);
BilibiliFavoriteFolder parseFolderInfoResponse(String body);
BilibiliFavoritePage parseFavoriteResourceListResponse(String body,
    {required int folderId, required int page, required int pageSize});
void parseFavoriteDealResponse(String body, {required BilibiliFavoriteAction action});
OnlineMedia toOnlineMedia(BilibiliFavoriteItem item, {int? folderId});
List<OnlineMedia> toOnlineMediaList(Iterable<BilibiliFavoriteItem> items, {int? folderId});
```

`sentSessionToken` matters: `nav` answers `-101` both for "no cookie was sent"
(anonymous) and "the cookie was rejected" (expired), and the parser needs the hint
to report the right one.

### 6.4 `BilibiliFavListUrlParser`

```dart
BilibiliFavListRef parse(Uri uri);        // throws BilibiliException on bad input
bool canHandle(Uri uri);
Uri buildUri(BilibiliFavListRef ref);
static const String pathSegment = 'favlist';
static Map<String, String> mergedQueryParameters(Uri uri);
static BilibiliFavListType? BilibiliFavListType.fromPlatformValue(String?);

class BilibiliFavListRef { int mid; int mediaId; BilibiliFavListType type; Uri source; }
enum BilibiliFavListType { created('create'), collected('collect') }
```

Accepts `.../favlist?fid=<id>&ftype=create|collect`, a missing `ftype` (defaults
to created), legacy `#/...?fid=` fragments, and unrelated query parameters.
Rejects video URLs, non-Bilibili hosts, and non-positive ids.

### 6.5 `BilibiliStreamValidator`

```dart
BilibiliStreamValidator({http.Client? httpClient,
                         Duration timeout = const Duration(seconds: 10)});
Future<BilibiliStreamValidationResult> validate(OnlineStream stream, {int maxBytes = 1024});

class BilibiliStreamValidationResult {
  bool get isPlayable; int get bytesRead; int? get statusCode;
  String? get contentType; bool? get rangeSupported;
  String? get reason; Duration? get elapsed;
}
```

Reads at most `maxBytes` with `Range`, follows the stream's own `headers`, accepts
HTTP 206 as full range support and 200 as a limited fallback, retries once without
`Range` on 416/501, and never exposes or returns the full signed stream URL.

## 7. HTTP endpoints used

| Host | Path | Auth |
|---|---|---|
| `api.bilibili.com` | `x/web-interface/view` | anonymous |
| `api.bilibili.com` | `x/player/playurl` | anonymous or session |
| `api.bilibili.com` | `x/web-interface/nav` | optional (it reports the state) |
| `api.bilibili.com` | `x/space/myinfo` | session |
| `api.bilibili.com` | `x/v3/fav/folder/created/list-all` | session |
| `api.bilibili.com` | `x/v3/fav/folder/info` | session |
| `api.bilibili.com` | `x/v3/fav/resource/list` | session |
| `api.bilibili.com` | `x/v3/fav/resource/deal` | session + csrf |
| `passport.bilibili.com` | `x/passport-login/web/qrcode/generate` | none |
| `passport.bilibili.com` | `x/passport-login/web/qrcode/poll` | none (ticket) |
| `b23.tv` | any token | anonymous (redirect resolution) |

## 8. Guarantees

1. Playback works with no account at all; nothing about the account layer is
   required to resolve or play a public video.
2. Credentials come only from the caller: an explicit sign-in, the user's own
   pasted header, or a cookie store the application supplies. There is no browser
   profile, keychain, or environment scraping.
3. `dart:io` is not in the main library, so importing the provider cannot write
   credentials; persistence is opt-in via `io.dart`.
4. Redaction is enforced by tests: `BilibiliCookies`, `BilibiliAccountSession`,
   `BilibiliAccountAuthProvider`, `BilibiliCookieStoreState`,
   `BilibiliAccountManager`, `BilibiliQrLogin`, `BilibiliQrLoginStatus`, and
   `PlainTextFileBilibiliCookieStore` never print a cookie, csrf token, QR ticket,
   or refresh token.
5. Debug output is off by default and, when enabled, contains only
   `METHOD host/path -> status` — no query strings, no bodies, no headers.
6. Cookies are validated against `nav` before being adopted, so a rejected jar
   never replaces a working session.
7. Streams always carry the headers their CDN needs; `getPlayback` may be called
   again at any time to refresh expired URLs.

## 9. What is not implemented

```text
password / SMS login                 QR scan-to-login only
an encrypted cookie store            plain-text file store, or supply your own
history, subscriptions, playlists    (planned stages 10-12)
search, feed, notifications, comments, danmaku
live, bangumi, downloads, subtitles
paid / membership / DRM / region-lock bypass   (by design, not a gap)
```

## 10. What a player adapter has to do

```text
1. detect a URL with canHandle(), or carry an OnlineMediaId of your own
2. resolve() for metadata/parts, or resolveById() when you only have a main id
3. getPlayback() for the selected part
4. map audioStreams/videoStreams/muxedStreams to your player's sources,
   passing url + headers for each stream
5. keep the split audio/video model (do not fabricate a muxed URL)
6. call getPlayback() again when a stream is expired or fails
```

Optional quality/part selection can use `qualityLabel`/`qualityId`, `width`,
`height`, `fps`, `bitrate`, and `OnlineMediaPart.index`.

## 11. Where things live

```text
packages/online_media_provider/lib/          provider-neutral DTOs + interface
packages/bilibili_provider/lib/
    bilibili_provider.dart                   main library (no dart:io)
    io.dart                                  file cookie store entry point
    src/bilibili_provider.dart               BilibiliProvider
    src/client/                              bilibili_http, bilibili_client, bilibili_account_client
    src/account/                             cookies, stores, session, auth, manager
    src/models/                              playback + account + qr login models
    src/parser/                              url, metadata, dash, account, favlist, api envelope
    src/validation/                          stream validator
    src/errors/                              exception hierarchy
example/standalone_player/                   real Flutter app: playback + login + favorites
```

Related:

- [../README.md](../README.md) — introduction, quick start, testing, limits
- [NAMIDA_UPSTREAM_ISSUE.md](NAMIDA_UPSTREAM_ISSUE.md) — draft feature request for
  a pluggable-provider hook, if you are integrating this into a player
