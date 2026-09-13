# Bilibili Account and Personal-Data Layer

Status:

```text
Stage 8   account foundation (cookies, store, session, current account)  implemented + offline tested
Stage 9   favorites (favlist links, folders, items, writes)              implemented + offline tested
Stage 9b  scan-to-login (QR) and the in-app login/favorites UI           implemented + verified by hand
Stage 10  history                                                        not started
Stage 11  subscriptions / following                                      not started
Stage 12  user playlists / collections                                   not started
```

This document describes the Bilibili-side account layer. It is a Bilibili-only
implementation: it does not fork Namida, does not modify Namida, and does not
depend on `youtipie`. The goal is that a future Namida adapter is a thin mapping
layer, because every capability Namida needs already exists here with a
Bilibili-native shape.

---

## 1. Why the layer is separate from playback

`BilibiliProvider` is a *playback* provider: `canHandle`, `resolve`,
`getPlayback`. Its inputs are video URLs and `OnlineMediaId`s.

Account data is a different problem:

- it needs credentials;
- it has a session lifecycle (anonymous, signed in, expired);
- it returns containers (favorite folders, history pages) rather than one video;
- it has write operations (add/remove favorite).

Those concerns are kept out of the playback contract so `BilibiliProvider` keeps
working anonymously and unchanged. One additive bridge exists:

```text
favorite list -> OnlineMedia(BVID, no CID) -> BilibiliProvider.resolveById() -> OnlineMedia(BVID, CID) -> getPlayback()
```

`resolveById` was added for this; favorite/history/playlist APIs never expose a
CID, and `getPlayback` requires one.

---

## 2. Security model

Hard rules for this layer:

| Rule | How it is enforced |
|---|---|
| Anonymous by default | `BilibiliAccountManager` starts on `BilibiliAccountSession.anonymous`; no request carries a cookie until `signIn` succeeds |
| Credentials only from the caller | cookies enter through `signIn` / `signInWithCookies` / `BilibiliCookieStore`; there is no browser-profile, keychain, or environment scraping |
| Nothing is written to disk by default | the default store is `InMemoryBilibiliCookieStore`; persistence needs an explicit opt-in (`package:bilibili_provider/io.dart`, or an application-supplied store) |
| Persistence can be switched off at runtime | `ConditionalBilibiliCookieStore` drops writes while `persist == false`, so a "do not remember" choice cannot leak to disk |
| Cookies never logged | `BilibiliCookies.toString()`, `redactedSummary`, `BilibiliAccountSession.toString()`, `BilibiliAccountAuthProvider.toString()`, `BilibiliCookieStoreState.toString()`, `BilibiliAccountManager.toString()`, and the file store's `toString()` (path only) are all redacted; `BilibiliHttpTransport` forwards only `METHOD host/path -> status` to a debug sink |
| Debug output off by default | `debug: false` is the default everywhere and no sink is installed unless the caller passes `onDebugLog` |
| Cookies never in exception messages | failures are built from fixed strings plus platform codes; the `csrf` token is read once and sent as a form field only |
| No credential bypass | no DRM, membership, paid, or region-lock handling; VIP fields from `nav` are exposed as display metadata only |
| Only the user's own authorized content | every account endpoint is called with the caller's own cookies; nothing is fetched on behalf of another account |

Enforced by offline tests:

```text
test/bilibili_cookies_test.dart          redaction surfaces + parsing rules
test/bilibili_account_client_test.dart   debug-log sanitization, csrf handling, no-leak assertions
test/bilibili_account_manager_test.dart  rejected cookies never replace a working session
```

Query strings are deliberately excluded from debug output, because Bilibili write
endpoints take `csrf` in the body and it is safer to log no parameters at all.

---

## 3. File map

```text
packages/bilibili_provider/lib/src/account/
    bilibili_cookies.dart           BilibiliCookies (redaction-safe jar, paste-friendly parsing)
    bilibili_cookie_store.dart      BilibiliCookieStore, BilibiliCookieStoreState,
                                   InMemoryBilibiliCookieStore,
                                   ConditionalBilibiliCookieStore
    bilibili_cookie_file_store.dart PlainTextFileBilibiliCookieStore (dart:io)
    bilibili_account_session.dart   BilibiliSessionState, BilibiliCookieValidity,
                                   BilibiliAccountSession
    bilibili_account_auth.dart      BilibiliAccountAuthProvider (BilibiliAuthProvider)
    bilibili_account_manager.dart   BilibiliAccountManager

packages/bilibili_provider/lib/
    bilibili_provider.dart          main library: no dart:io, web-safe
    io.dart                         opt-in entry point that exports the file store

packages/bilibili_provider/lib/src/client/
    bilibili_http.dart              BilibiliHttpTransport (shared request plumbing)
    bilibili_account_client.dart    BilibiliAccountClient
    bilibili_client.dart            BilibiliClient (playback, now on the shared transport)

packages/bilibili_provider/lib/src/models/
    bilibili_account_api_models.dart
        BilibiliAccountInfo, BilibiliNavResult, BilibiliFavoriteFolder,
        BilibiliFavoriteItem, BilibiliFavoritePage, BilibiliFavoriteOrder,
        BilibiliFavoriteAction

packages/bilibili_provider/lib/src/parser/
    bilibili_account_parser.dart    BilibiliAccountParser
    bilibili_fav_url_parser.dart    BilibiliFavListUrlParser, BilibiliFavListRef,
                                   BilibiliFavListType
    bilibili_api_response.dart      + BilibiliApiEnvelope, asBool, asDateTimeSeconds

packages/bilibili_provider/test/fixtures/   nav_*, space_myinfo, fav_*
packages/bilibili_provider/test/            bilibili_cookies_test, bilibili_cookie_store_test,
                                            bilibili_cookie_file_store_test,
                                            bilibili_fav_url_parser_test,
                                            bilibili_account_parser_test,
                                            bilibili_account_client_test,
                                            bilibili_account_manager_test,
                                            bilibili_favorites_test
packages/bilibili_provider/test/online/     bilibili_account_online_test (@Tags online)
                                            bilibili_authenticated_online_test (env-gated)
packages/bilibili_provider/tool/            bilibili_account_check (manual diagnostics)

example/standalone_player/lib/
    main.dart                       player screen + account/favorites wiring
    account_ui.dart                 login dialog, account card, favorites browser
    bilibili_format.dart            shared duration formatting
```

Provider-neutral DTOs stay in `packages/online_media_provider` and are unchanged.
Bilibili-specific account DTOs live in `bilibili_provider`. Favorites are the one
place a Bilibili response becomes provider-neutral: `BilibiliFavoriteItem` is
mapped to `OnlineMedia`.

`BilibiliHttpTransport` is the single place a cookie header is attached, so the
playback client and the account client cannot drift apart on headers, timeouts,
or error mapping.

`dart:io` is kept out of the main library on purpose:

- the provider keeps working in web builds;
- importing the provider never implies that credentials can be written to disk.

A desktop or server application opts in explicitly:

```dart
import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:bilibili_provider/io.dart';
```

---

## 4. Public API

### 4.1 Cookies

```dart
final cookies = BilibiliCookies.parse('SESSDATA=...; bili_jct=...; DedeUserID=...');
cookies.cookieHeader;        // credential: hand to HTTP only
cookies.sessData;            // credential
cookies.csrfToken;           // credential, sent as the `csrf` form field
cookies.userId;              // mid from DedeUserID
cookies.redactedSummary;     // '<redacted: 3 cookie(s)>'
cookies.toString();          // names only, no values
```

`BilibiliCookies.fromSetCookieHeaders(...)` reads `Set-Cookie` responses, which is
the hook a future explicit login flow needs. `Set-Cookie` attributes
(`Path`, `Domain`, `HttpOnly`, ...) are never turned into cookies.

### 4.2 Cookie store

```dart
abstract interface class BilibiliCookieStore {
  Future<BilibiliCookieStoreState> read();
  Future<void> write(BilibiliCookieStoreState state);
  Future<void> clear();
}
```

`BilibiliCookieStoreState` holds `accounts` (key = mid) plus `activeAccountKey`.
Only cookies are persisted; name/avatar are re-derived from `nav` on demand.

Three implementations ship:

| Store | Where | Behaviour |
|---|---|---|
| `InMemoryBilibiliCookieStore` | main library | default; nothing touches the disk |
| `ConditionalBilibiliCookieStore` | main library | decorator; drops `write` while `persist == false`, so a "do not remember" choice cannot leak to disk, and an existing saved login is left untouched |
| `PlainTextFileBilibiliCookieStore` | `package:bilibili_provider/io.dart` | JSON file under the per-user application data directory |

The file store is deliberately **not** part of the main library, so importing the
provider never implies disk writes and web builds stay possible:

```dart
import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:bilibili_provider/io.dart';

final store = ConditionalBilibiliCookieStore(
  PlainTextFileBilibiliCookieStore(),   // %APPDATA%\namida_bilibili_provider\...json
);
final manager = BilibiliAccountManager(cookieStore: store);
await manager.restore();

store.persist = rememberMe;             // user choice from the login form
await manager.signInWithCookies(BilibiliCookies.fromUserInput(pasted));
```

Storage details:

- path: `%APPDATA%` on Windows, `~/Library/Application Support` on macOS,
  `$XDG_DATA_HOME` or `~/.local/share` elsewhere;
- the file is **plain text**, protected only by the directory's per-user
  permissions; on Linux it inherits the process umask, so applications that need
  stronger protection must supply an encrypted store instead;
- writes go through a temporary file and a rename, and a missing, unreadable, or
  malformed file reads as "no saved login" instead of breaking startup;
- `toString()` exposes the path only, never the payload;
- `Platform.environment` / `Platform.operatingSystem` can be injected, so the path
  mapping is unit-tested without touching the real machine.

### 4.3 Session and validity

```dart
enum BilibiliSessionState { anonymous, authenticated, expired, csrfInvalid, unknown }

final validity = manager.cookieValidity;
validity.isAuthenticated;   // server accepted the cookies
validity.requiresSignIn;    // expired or csrfInvalid -> ask the user again
```

`nav` answers "not signed in" with code `-101`, which is not an error: it is
either the anonymous state (no cookie was sent) or an expired session (a cookie
was sent). `BilibiliAccountParser.parseNavResponse(..., sentSessionToken: ...)`
distinguishes them, and `BilibiliAccountClient.getNav()` derives the flag from the
request it is about to make.

### 4.4 Sign-in

Two paths exist. Scan-to-login is the normal one; the manual paste path is a
fallback for environments where scanning is not possible.

#### Scan to login (primary)

```dart
final session = await manager.signInWithQrCode(
  onProgress: (status) => showQrOrProgress(status),   // status.login.uri is the QR content
  pollInterval: const Duration(seconds: 2),
  timeout: const Duration(minutes: 3),
  isCancelled: () => dialogClosed,
);
```

Endpoints (host `passport.bilibili.com`, not `api.bilibili.com`):

| Step | Endpoint | Notes |
|---|---|---|
| issue | `GET x/passport-login/web/qrcode/generate` | returns `data.url` (QR content) + `data.qrcode_key` |
| poll | `GET x/passport-login/web/qrcode/poll?qrcode_key=...` | the state is in `data.code`, while the envelope code stays `0` |

States, mapped onto `BilibiliQrLoginStage`:

```text
pending    data.code 86101   未扫码        keep polling
scanned    data.code 86090   已扫码未确认   keep polling
confirmed  data.code 0                     adopt the session, then validate with nav
expired    data.code 86038   二维码已过期    ask for a new ticket
failed     anything else / unusable reply
```

The session arrives as `Set-Cookie` headers and/or inside `data.url` (the
platform's cross-domain redirect URL, which carries `SESSDATA`, `bili_jct`,
`DedeUserID`, ...). Both sources are merged, `Set-Cookie` winning, and only known
Bilibili cookie names are taken from the URL so parameters such as `gourl` cannot
pollute the jar. A confirmation without a usable session is reported as `failed`
rather than adopted.

Why this is the correct flow rather than a shortcut:

- the user authenticates in Bilibili's own app and confirms on their own device;
- this package never sees a password, a captcha, or a browser profile;
- the QR content and key are single-use login tickets, so they are redacted in
  `toString()` and never logged;
- nothing is adopted until the platform confirms and `nav` accepts the result.

`BilibiliQrLoginStatus.login` carries the ticket, so a UI renders the QR image
and the progress text from the same callback.

#### Manual cookie paste (fallback)

```dart
await manager.signInWithCookies(BilibiliCookies.fromUserInput(pastedHeader));
```

Kept because it needs no camera and no second device, and because a user may
already have the header at hand. It is not the primary path: the desktop app
offers it behind a "manual" tab.

#### Account lifecycle

```dart
await manager.restore();                     // load persisted cookies
manager.isAnonymous;                         // false after sign-in
manager.activeAccountKey;                    // '100000001'
manager.signedInAccounts;                    // List<BilibiliAccountSession>
manager.activeAccountDetails;                 // BilibiliAccountInfo?
await manager.getCurrentAccount(forceRefresh: true);  // profile, or null when expired
await manager.validateActiveCookies();        // BilibiliCookieValidity
await manager.switchAccount('100000002');
await manager.setAnonymous();                 // keep accounts, send no cookies
await manager.signOut();                      // drop active, fall back to another
await manager.signOutAll();                   // drop everything + clear store
manager.onAccountChanged;                     // Stream<BilibiliAccountSession>
manager.createMediaProvider();                // BilibiliProvider sharing the session
```

Behaviour worth knowing:

- `signInWithCookies` validates the candidate cookies against `nav` *before*
  adopting them. A rejected jar throws `BilibiliAuthenticationException` and the
  previous session, the auth provider, and the store are left untouched.
- `signInWithQrCode` reuses that same path once the platform confirms, so a QR
  session is validated exactly like a pasted one.
- `getCurrentAccount()` returns `null` for an expired session instead of throwing,
  because "expired" is normal UI state. Transport and parse failures still throw.
- The expired session object is kept after an expiry check so a UI can name the
  account that needs re-login.
- Writes additionally require `bili_jct`; a session without it can read but not
  favorite.
- `signOutAll()` deletes the persisted cookies; `setAnonymous()` keeps them.

### 4.5 Account client endpoints

| Method | Endpoint | Notes |
|---|---|---|
| `getNav({cookies})` | `GET x/web-interface/nav` | current account + validity; `cookies` overrides for candidate validation |
| `getMyInfo({mid})` | `GET x/space/myinfo` | full profile |
| `getCreatedFavoriteFolders({mid})` | `GET x/v3/fav/folder/created/list-all` | folders incl. private ones, flagged by `isPublic` |
| `getFavoriteFolderInfo({mediaId})` | `GET x/v3/fav/folder/info` | folder metadata |
| `getFavoriteResources(...)` | `GET x/v3/fav/resource/list` | one page, `pn`/`ps`/`order`/`keyword`; `ps` capped at 20 |
| `paginateFavoriteResources(...)` | same | `Stream<BilibiliFavoritePage>`, bounded by `maxPages` (default 50) |
| `getAllFavoriteMedia(...)` | same | one deduplicated `List<OnlineMedia>` |
| `getFavoriteResourcesFromUri(uri)` | same | parses a `favlist` link first |
| `addFavorite({aid, folderIds})` | `POST x/v3/fav/resource/deal` | `add_media_ids`, `csrf` from the session |
| `removeFavorite({aid, folderIds})` | same | `del_media_ids` |
| `dealFavorite({aid, action, folderIds})` | same | explicit form |

`aid` is the numeric archive id (`rid`), not a BVID: the write API does not accept
a BVID. A favorite entry already carries `extra['aid']`, or
`BilibiliFavoriteItem.aid` if the raw entry is used.

### 4.6 Favorite-list URLs

```dart
const parser = BilibiliFavListUrlParser();
final ref = parser.parse(Uri.parse(
  'https://space.bilibili.com/100000001/favlist?fid=200000001&ftype=create',
));
ref.mid;      // 100000001
ref.mediaId;  // 200000001  (the API's media_id)
ref.type;     // BilibiliFavListType.created
parser.buildUri(ref);
```

Supported: `ftype=create` (default), `ftype=collect`, legacy `#/...?fid=` hash
routes, trailing slashes, and unrelated query parameters.

`BilibiliUrlParser` and `BilibiliProvider.canHandle` keep *rejecting* `favlist`
links. A favorite folder is a container, not a video, so it must not resolve into
`OnlineMedia`; tests assert this separation explicitly.

### 4.7 Favorites to playback

```dart
final provider = manager.createMediaProvider();          // or BilibiliProvider()

final page = await client.getFavoriteResources(mediaId: 200000001);
final item = page.media.first;                           // no CID yet
final resolved = await provider.resolveById(item.id);     // one metadata request
final playback = await provider.getPlayback(resolved.id);
```

`page.media` already excludes resources Bilibili marks invalid
(`attr & 1`, or the `已失效视频` title), while `page.entries` keeps them for a UI
that wants to show the gap.

---

## 5. Namida / YoutiPie mapping

Interface-shape comparison only. Namida's YoutiPie types are private and are not
compiled here. The playback boundary and its warnings are in
[INTERFACE_REFERENCE.md](INTERFACE_REFERENCE.md).

| Namida / YoutiPie surface | Bilibili account layer | State |
|---|---|---|
| `YoutiAccountManager.signIn(pageConfig:, onProgress:, forceSignIn:)` | `BilibiliAccountManager.signInWithQrCode(onProgress:, pollInterval:, timeout:, isCancelled:)` | yes, platform-native flow |
| `YoutiLoginProgress` progress states on the sign-in button | `BilibiliQrLoginStage` (`pending` / `scanned` / `confirmed` / `expired` / `failed`) | yes |
| `LoginPageConfiguration(header:, popPage:, pushPage:)` | No equivalent needed: the QR content is handed back to the caller, which decides how to display it | boundary |
| `YoutiPie.cookies` | `BilibiliCookies` + `BilibiliAccountAuthProvider` | yes |
| `YoutiPie.cookies.signOut(userChannel)` | `BilibiliAccountManager.signOut(accountKey)` | yes |
| `YoutiPie.cookies.setAccount(...)` | `BilibiliAccountManager.switchAccount(accountKey)` | yes |
| `YoutiPie.cookies.setAnonymous()` | `BilibiliAccountManager.setAnonymous()` | yes |
| `YoutiPie.cookies.activeAccountChannel` | `BilibiliAccountManager.activeAccountKey` | yes |
| `YoutiPie.cookies.signedInAccounts` | `BilibiliAccountManager.signedInAccounts` | yes |
| `YoutiPie.cookies.canAddMultiAccounts` | `allowMultipleAccounts` / `maxAccounts` / `canAddMultipleAccounts` | yes |
| `YoutiPie.cookies.addOnAccountChanged(...)` | `BilibiliAccountManager.onAccountChanged` | yes |
| `YoutiPie.activeAccountDetails` | `BilibiliAccountManager.activeAccountDetails` | yes |
| `UserChannelInfo` | `BilibiliAccountInfo` (mid, name, avatar, sign, level, counts) | yes |
| `AccountCookiesValidity` | `BilibiliCookieValidity` / `BilibiliSessionState` | yes |
| Cookie persistence in an app data directory (`AppDirs.YOUTIPIE_DATA`) | `PlainTextFileBilibiliCookieStore` under `%APPDATA%` / app support dir | yes |
| Cookie persistence in encrypted storage | `BilibiliCookieStore` interface; the shipped file store is plain text |  partial |
| `YoutubeAccountController` | `BilibiliAccountManager` | yes |
| Membership-gated sign-in (`_checkCanSignIn` + Patreon/Supabase tiers) | Not replicated: sign-in here is unconditional |  N/A |
| `YoutubeInfoController.userplaylist.getUserPlaylists(...)` | `BilibiliAccountClient.getCreatedFavoriteFolders` | partial (favorites only) |
| `YoutubeInfoController.userplaylist.getPlaylistEditInfo(...)` | `getFavoriteFolderInfo` | partial |
| `YoutubePlaylistController.favouriteButtonOnPressed(...)` | `addFavorite` / `removeFavorite` | yes |
| `YoutubeInfoController.history.fetchHistory(...)` |  | Stage 10 |
| `YoutubeInfoController.history.markVideoWatched(...)` |  | Stage 10 |
| `YoutubeInfoController.userchannel.fetchUserChannels(...)` |  | Stage 11 |
| `YoutubeSubscriptionsController.toggleChannelSubscription(...)` |  | Stage 11 |
| `YoutubeInfoController.video.fetchVideoPage(videoId)` | `BilibiliProvider.resolve` / `resolveById` | yes |
| `YoutubeInfoController.video.fetchVideoStreams(videoId)` | `BilibiliProvider.getPlayback` | yes |
| `YoutiPie.search` / `feed` / `comment` / `notificationsAction` |  | out of scope for this layer |
| `YoutiPie.sponsorblock` / `returnyoutubedislike` / `potoken` |  | no Bilibili equivalent |

A Namida-side adapter therefore needs to:

1. own a `BilibiliCookieStore` implementation on top of Namida's encrypted
   storage;
2. construct one `BilibiliAccountManager` and expose `onAccountChanged`;
3. render `BilibiliQrLoginStatus.login.uri` when `signInWithQrCode` reports
   progress, and map the stages onto its own progress UI;
4. map `BilibiliAccountInfo` into whatever `activeAccountDetails` expects;
5. map `BilibiliFavoriteFolder` / `OnlineMedia` into its own playlist model;
6. add a `Playable` branch that consumes `OnlineMediaId` (see the reference patch).

### Why there is no `LoginPageConfiguration` equivalent

Namida's `LoginPageConfiguration(header:, popPage:, pushPage:)` exists because the
YouTube flow pushes a login *page* (an embedded web/GDK login) into the app's
navigator, so the library needs the app's navigation callbacks.

Bilibili's web QR flow needs none of that: the login surface is one image plus
progress text, which the caller can render anywhere. So instead of requesting
navigator callbacks, `signInWithQrCode` reports status and hands back the QR
content through `BilibiliQrLoginStatus.login`. That keeps the account layer free
of Flutter dependencies, so it stays unit-testable offline.

If Bilibili ever requires a page-based login, the same progress-callback shape can
drive it without changing the account layer's public surface.

---

## 6. Testing

Offline tests never touch the network: every account test drives
`MockClient` and on-disk fixtures.

```text
packages/bilibili_provider/test/fixtures/
    nav_logged_in.json                  code 0, isLogin true
    nav_logged_in_second.json           second account, for switching
    nav_anonymous.json                  code 0, isLogin false
    nav_not_logged_in.json              code -101
    nav_csrf_invalid.json               code -111
    space_myinfo.json                   profile
    fav_folder_list.json                three folders, one private
    fav_folder_info.json                scheme-relative cover
    fav_resource_list_page1.json        two playable + one expired, has_more true
    fav_resource_list_page2.json        last page, has_more false
    fav_resource_list_no_has_more.json  flag missing -> "page was full" fallback
    fav_resource_deal_ok.json           code 0 without a data object
    fav_resource_deal_csrf_invalid.json code -111
    fav_folder_list_unauthorized.json   code -101
```

Fixtures contain only de-sensitized placeholder values; no real cookie, token, or
mid appears in this repository.

The file store tests use `Directory.systemTemp` and never the real application data
directory, so running the suite cannot touch a developer's saved login.

Online tests stay tagged and credential-free:

```text
test/online/bilibili_account_online_test.dart          @Tags(['online'])
```

They assert only that anonymous `nav` still returns an unauthenticated session and
that the manager sends no cookies. Tests that need a real account cookie are
deliberately not committed.

Run offline:

```powershell
cd packages/bilibili_provider
dart test
```

### Manual authenticated verification

Authenticated behaviour is verified with your own account, driven by environment
variables. Nothing is committed, and no test runs without credentials:

- the file is tagged `online` + `authenticated`, and `dart_test.yaml` skips both
  tags, so a plain `dart test` never touches it;
- because `--run-skipped` overrides a declared skip, every test also self-skips at
  runtime when its variables are missing. Running the suite without credentials
  therefore reports skips with a reason instead of failing or reaching an
  authenticated endpoint.

The QR flow itself is verified separately in two ways: an offline suite drives the
whole state machine with fixtures, and a credential-free online test issues a real
ticket and checks the live `pending` reply. A real scan is a manual step.

```text
test/online/bilibili_authenticated_online_test.dart    @Tags(['online', 'authenticated'])
tool/bilibili_account_check.dart                       manual, read-only diagnostics
```

| Variable | Used for |
|---|---|
| `BILIBILI_TEST_COOKIES` | required; your own `Cookie` header |
| `BILIBILI_TEST_FOLDER_ID` | optional; folder to browse (default: first created folder) |
| `BILIBILI_TEST_BVID` | optional; video for the favorites -> playback bridge |
| `BILIBILI_TEST_WRITE_FOLDER_ID` | opt-in; folder for the mutating round trip |
| `BILIBILI_TEST_WRITE_BVID` | opt-in; video for the mutating round trip |

#### 1. Get a cookie header

Sign in with your own browser, open DevTools -> Network, pick any `api.bilibili.com`
request, and copy the `Cookie` request header. Keep at least:

```text
SESSDATA=<session>        required for every authenticated request
bili_jct=<csrf>           required for favorite add/remove
DedeUserID=<mid>          makes the account key available before the first nav
```

The account layer never reads a browser profile itself: copying the value by hand
*is* the explicit provisioning step. Treat it like a password.

#### 2. Run the read-only checks

```powershell
cd packages/bilibili_provider
$env:BILIBILI_TEST_COOKIES = 'SESSDATA=...; bili_jct=...; DedeUserID=...'
dart test --tags authenticated --run-skipped
```

The suite verifies, in order: `signIn` produces an authenticated session with
`bili_jct` present; `myinfo` agrees with `nav`; the created-folder list loads and
page 1 maps to `OnlineMedia` with `subId == null`; and the favorites -> playback
bridge turns an entry into a CID-bearing id that yields real audio/video streams.

`$env:X = ...` only affects the current shell session, and the value is never
printed by the tests.

#### 3. Manual, read-only diagnostics

```powershell
dart run tool/bilibili_account_check.dart                  # account + folders
dart run tool/bilibili_account_check.dart --folders-only
dart run tool/bilibili_account_check.dart --folder 200000001
dart run tool/bilibili_account_check.dart --play BV1xx411c7mD
```

It prints the mid, name, level, counts, validity state, whether a csrf token is
present, the folder list, one favorite page, and DASH stream counts. It never
prints cookie values or stream URLs, and it changes nothing.

#### 4. Opt-in write round trip

Only this group mutates account state, and it restores what it found:

```powershell
$env:BILIBILI_TEST_WRITE_FOLDER_ID = '200000001'
$env:BILIBILI_TEST_WRITE_BVID = 'BV1xx411c7mD'
dart test --tags authenticated --run-skipped
```

It resolves the BVID to its numeric `aid`, records whether the item is already in
the folder, then:

```text
not present -> add -> assert listed -> remove -> assert gone
already present -> add (idempotent) -> assert still listed, state untouched
```

If the cookie lacks `bili_jct`, the write is refused *before* any request is sent
(`BilibiliAuthenticationException`), which is itself a useful check.

#### 5. What to do when a check fails

| Symptom | Meaning |
|---|---|
| `BilibiliAuthenticationException`, code `-101` | the cookie expired; sign in again and re-copy |
| `BilibiliAuthenticationException`, code `-111` | `bili_jct` is missing or stale |
| `BilibiliAccessDeniedException` / code `62002`/`62004` | the folder or media is not accessible with these cookies |
| `BilibiliApiException` with code `-352` | Bilibili risk control rejected the request; wait, and never retry in a loop |

`validity.requiresSignIn` is the programmatic version of the first row.

---

## 7. Deliberately not implemented

```text
QR / password / SMS login            QR scan-to-login is implemented; password and
                                     SMS are not, and are not planned
an encrypted cookie store            only a plain-text file store is shipped;
                                     supply a keychain/DPAPI-backed store instead
history (x/v2/history, toview)       Stage 10
following / subscriptions            Stage 11
user playlists / collections         Stage 12
search, feed, notifications, comments, danmaku
live, bangumi, downloads
account sync, settings sync
any DRM / membership / paid / region-lock handling
```

## 7.1 Standalone app integration

`example/standalone_player` wires the account layer into a real Flutter app, which
is how the layer is verified by hand:

```text
BilibiliAccountAuthProvider  --shared-->  BilibiliAccountManager
         |                                        |
         +--> BilibiliProvider(auth:)             +--> ConditionalBilibiliCookieStore
              (playback also sends cookies)            --> PlainTextFileBilibiliCookieStore
```

- `lib/account_ui.dart` — login dialog (paste a cookie header, remember switch,
  recognized-name preview), account card (avatar, mid, validity, refresh,
  switch-to-anonymous, sign out, delete saved cookies), and the favorites browser;
- the favorites browser lists folders, pages through items (`ps=20`), hides
  expired entries with a count, and hands an item to the player;
- the player resolves the missing CID with `resolveById()` before `getPlayback()`;
- the login dialog only reports which cookie *names* were recognized, because the
  values must never be rendered.

Run it with:

```powershell
cd example/standalone_player
flutter run -d windows
```

See `example/standalone_player/README.md` for the click-by-click walkthrough.

## 8. Next stages

```text
Stage 10  history:  GET x/v2/history, optional mark-watched, OnlineMedia mapping
Stage 11  following list + subscribed-UP video feed
Stage 12  user playlists / collections (polymer seasons & series)
```
