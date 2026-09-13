import 'package:http/http.dart' as http;
import 'package:online_media_provider/online_media_provider.dart';

import '../account/bilibili_cookies.dart';
import '../auth/bilibili_auth.dart';
import '../errors/bilibili_exception.dart';
import '../models/bilibili_account_api_models.dart';
import '../models/bilibili_qr_login_models.dart';
import '../parser/bilibili_account_parser.dart';
import '../parser/bilibili_fav_url_parser.dart';
import 'bilibili_http.dart';

/// HTTP boundary for Bilibili account and personal-data endpoints.
///
/// Only capabilities the signed-in user already has are exposed: reading the
/// current profile, the account's own favorite folders, and adding/removing
/// items in those folders. No paid, DRM, region-locked, or member-only content
/// is unlocked here, and no content is fetched that the caller's cookies do not
/// already authorize.
///
/// Credentials come exclusively from [auth]; this client never reads cookies
/// from a browser profile, never writes them to disk, and never logs them.
class BilibiliAccountClient {
  BilibiliAccountClient({
    this.auth = const AnonymousBilibiliAuthProvider(),
    BilibiliAccountParser? parser,
    BilibiliFavListUrlParser? favListUrlParser,
    http.Client? httpClient,
    bool debug = false,
    Duration requestTimeout = const Duration(seconds: 15),
    void Function(String message)? onDebugLog,
  }) : _parser = parser ?? const BilibiliAccountParser(),
       favListUrlParser = favListUrlParser ?? const BilibiliFavListUrlParser(),
       _http = BilibiliHttpTransport(
         auth: auth,
         httpClient: httpClient,
         debug: debug,
         requestTimeout: requestTimeout,
         onDebugLog: onDebugLog,
       );

  /// Source of the cookie header attached to account requests.
  final BilibiliAuthProvider auth;

  /// Parses `favlist` links into folder references.
  final BilibiliFavListUrlParser favListUrlParser;

  final BilibiliAccountParser _parser;
  final BilibiliHttpTransport _http;

  /// Maximum `ps` Bilibili accepts for `x/v3/fav/resource/list`.
  static const int maxFavoritePageSize = 20;

  /// Default `ps` for `x/v3/fav/resource/list`.
  static const int defaultFavoritePageSize = 20;

  static const String _apiHost = 'api.bilibili.com';
  static const String _passportHost = 'passport.bilibili.com';
  static const String _webLocation = '333.1387';

  /// Checks the session and returns the current account, if any.
  ///
  /// [cookies] overrides the auth provider for this single request, which lets a
  /// caller validate a candidate cookie jar before adopting it. The override is
  /// never stored.
  Future<BilibiliNavResult> getNav({BilibiliCookies? cookies}) async {
    final effectiveCookies =
        cookies ?? BilibiliCookies.parse(auth.cookieHeader);
    final uri = Uri.https(_apiHost, '/x/web-interface/nav');
    final body = await _http.getString(uri, cookiesOverride: cookies);
    return _parser.parseNavResponse(
      body,
      sentSessionToken: effectiveCookies.hasSessionToken,
    );
  }

  /// Asks Bilibili for a login QR code.
  ///
  /// The returned ticket is single-use and short-lived: poll it with
  /// [pollQrLogin] until it is confirmed or expired, then request a new one.
  ///
  /// This is Bilibili's normal login flow. The user scans the code with the
  /// official app and confirms on their own device, so no password, captcha, or
  /// browser profile is involved.
  Future<BilibiliQrLogin> generateQrLogin() async {
    final uri = Uri.https(
      _passportHost,
      '/x/passport-login/web/qrcode/generate',
    );
    final body = await _http.getString(uri);
    return _parser.parseQrLoginGenerateResponse(body);
  }

  /// Polls [login] once and reports the current state.
  ///
  /// The session cookies arrive through `Set-Cookie` and/or the response's
  /// cross-domain URL, so this returns the whole result rather than only a body.
  Future<BilibiliQrLoginStatus> pollQrLogin(BilibiliQrLogin login) async {
    if (login.qrcodeKey.isEmpty) {
      throw const BilibiliParseException(
        'QR login polling requires a non-empty qrcode key.',
      );
    }

    final uri = Uri.https(
      _passportHost,
      '/x/passport-login/web/qrcode/poll',
      <String, String>{'qrcode_key': login.qrcodeKey},
    );
    final result = await _http.getResult(uri);
    return _parser.parseQrLoginPollResponse(
      result.body,
      setCookieHeaders: result.setCookieHeaders,
    );
  }

  /// Fetches the signed-in account profile from `x/space/myinfo`.
  Future<BilibiliAccountInfo> getMyInfo({int? mid}) async {
    final uri = Uri.https(_apiHost, '/x/space/myinfo', <String, String>{
      if (mid != null) 'mid': '$mid',
      'web_location': _webLocation,
    });
    final body = await _http.getString(uri);
    return _parser.parseMyInfoResponse(body);
  }

  /// Lists every favorite folder created by [mid].
  Future<List<BilibiliFavoriteFolder>> getCreatedFavoriteFolders({
    required int mid,
  }) async {
    if (mid <= 0) {
      throw const BilibiliParseException(
        'Favorite folder listing requires a positive mid.',
      );
    }

    final uri = Uri.https(
      _apiHost,
      '/x/v3/fav/folder/created/list-all',
      <String, String>{'up_mid': '$mid', 'web_location': _webLocation},
    );
    final body = await _http.getString(uri);
    return _parser.parseCreatedFolderListResponse(body);
  }

  /// Fetches metadata for one favorite folder.
  Future<BilibiliFavoriteFolder> getFavoriteFolderInfo({
    required int mediaId,
  }) async {
    _requirePositiveMediaId(mediaId);

    final uri = Uri.https(_apiHost, '/x/v3/fav/folder/info', <String, String>{
      'media_id': '$mediaId',
      'web_location': _webLocation,
    });
    final body = await _http.getString(uri);
    return _parser.parseFolderInfoResponse(body);
  }

  /// Reads one page of a favorite folder.
  ///
  /// The returned [BilibiliFavoritePage.media] values carry a BVID but no CID,
  /// because this endpoint does not expose CIDs. Resolve them with
  /// `BilibiliProvider.resolveById` before asking for playback.
  Future<BilibiliFavoritePage> getFavoriteResources({
    required int mediaId,
    int page = 1,
    int pageSize = defaultFavoritePageSize,
    String? keyword,
    BilibiliFavoriteOrder order = BilibiliFavoriteOrder.favoriteTime,
  }) async {
    _requirePositiveMediaId(mediaId);
    if (page < 1) {
      throw const BilibiliParseException(
        'Favorite resource page must be 1 or greater.',
      );
    }
    if (pageSize < 1 || pageSize > maxFavoritePageSize) {
      throw BilibiliParseException(
        'Favorite resource pageSize must be between 1 and '
        '$maxFavoritePageSize.',
      );
    }

    final trimmedKeyword = keyword?.trim();
    final uri = Uri.https(_apiHost, '/x/v3/fav/resource/list', <String, String>{
      'media_id': '$mediaId',
      'pn': '$page',
      'ps': '$pageSize',
      if (trimmedKeyword != null && trimmedKeyword.isNotEmpty)
        'keyword': trimmedKeyword,
      'order': order.platformValue,
      'type': '0',
      'tid': '0',
      'platform': 'web',
    });

    final body = await _http.getString(uri);
    return _parser.parseFavoriteResourceListResponse(
      body,
      folderId: mediaId,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Streams every page of a favorite folder until the platform reports the end.
  ///
  /// [maxPages] is a hard safety bound against an endpoint that keeps claiming
  /// more pages, so a caller can never spin forever.
  Stream<BilibiliFavoritePage> paginateFavoriteResources({
    required int mediaId,
    int pageSize = defaultFavoritePageSize,
    int startPage = 1,
    int maxPages = 50,
    String? keyword,
    BilibiliFavoriteOrder order = BilibiliFavoriteOrder.favoriteTime,
  }) async* {
    if (maxPages < 1) {
      throw const BilibiliParseException('maxPages must be 1 or greater.');
    }

    var page = startPage;
    var fetched = 0;
    while (fetched < maxPages) {
      final result = await getFavoriteResources(
        mediaId: mediaId,
        page: page,
        pageSize: pageSize,
        keyword: keyword,
        order: order,
      );
      yield result;
      fetched++;
      if (!result.hasMore) {
        return;
      }
      page++;
    }
  }

  /// Collects every playable item of a favorite folder into one list.
  ///
  /// Duplicate BVIDs are collapsed, because a folder can contain the same
  /// archive once per part in some Bilibili responses.
  Future<List<OnlineMedia>> getAllFavoriteMedia({
    required int mediaId,
    int pageSize = defaultFavoritePageSize,
    int maxPages = 50,
    String? keyword,
    BilibiliFavoriteOrder order = BilibiliFavoriteOrder.favoriteTime,
  }) async {
    final seen = <String>{};
    final collected = <OnlineMedia>[];
    await for (final page in paginateFavoriteResources(
      mediaId: mediaId,
      pageSize: pageSize,
      maxPages: maxPages,
      keyword: keyword,
      order: order,
    )) {
      for (final media in page.media) {
        if (seen.add(media.id.id)) {
          collected.add(media);
        }
      }
    }
    return List<OnlineMedia>.unmodifiable(collected);
  }

  /// Parses a `space.bilibili.com/<mid>/favlist?fid=...` link and reads one page.
  Future<BilibiliFavoritePage> getFavoriteResourcesFromUri(
    Uri favListUri, {
    int page = 1,
    int pageSize = defaultFavoritePageSize,
    BilibiliFavoriteOrder order = BilibiliFavoriteOrder.favoriteTime,
  }) {
    final ref = favListUrlParser.parse(favListUri);
    return getFavoriteResources(
      mediaId: ref.mediaId,
      page: page,
      pageSize: pageSize,
      order: order,
    );
  }

  /// Adds the archive [aid] to [folderIds].
  ///
  /// Requires a signed-in session whose cookies include the `bili_jct` csrf
  /// token. Nothing is retried automatically.
  Future<void> addFavorite({required int aid, required List<int> folderIds}) {
    return dealFavorite(
      aid: aid,
      action: BilibiliFavoriteAction.add,
      folderIds: folderIds,
    );
  }

  /// Removes the archive [aid] from [folderIds].
  Future<void> removeFavorite({
    required int aid,
    required List<int> folderIds,
  }) {
    return dealFavorite(
      aid: aid,
      action: BilibiliFavoriteAction.remove,
      folderIds: folderIds,
    );
  }

  /// Sends an explicit `x/v3/fav/resource/deal` write request.
  ///
  /// [folderIds] are `media_id` values, and [aid] is the numeric archive id
  /// (`rid`), not a BVID.
  Future<void> dealFavorite({
    required int aid,
    required BilibiliFavoriteAction action,
    required List<int> folderIds,
  }) async {
    if (aid <= 0) {
      throw const BilibiliParseException(
        'Favorite changes require a positive archive id.',
      );
    }

    final validFolderIds = <int>[];
    for (final folderId in folderIds) {
      if (folderId <= 0) {
        throw const BilibiliParseException(
          'Favorite changes require positive folder ids.',
        );
      }
      if (!validFolderIds.contains(folderId)) {
        validFolderIds.add(folderId);
      }
    }
    if (validFolderIds.isEmpty) {
      throw const BilibiliParseException(
        'Favorite changes require at least one folder id.',
      );
    }

    final csrf = _requireCsrfToken();
    final uri = Uri.https(_apiHost, '/x/v3/fav/resource/deal');

    final body = await _http.postForm(uri, <String, String>{
      'rid': '$aid',
      'type': '2',
      action.platformField: validFolderIds.join(','),
      'csrf': csrf,
      'platform': 'web',
    });

    _parser.parseFavoriteDealResponse(body, action: action);
  }

  void _requirePositiveMediaId(int mediaId) {
    if (mediaId <= 0) {
      throw const BilibiliParseException(
        'Favorite folder operations require a positive media id.',
      );
    }
  }

  /// Reads the csrf token from the active cookie header.
  ///
  /// The token is returned to be sent as the `csrf` form field and is never
  /// logged or embedded in an exception message.
  String _requireCsrfToken() {
    final cookies = BilibiliCookies.parse(auth.cookieHeader);
    final token = cookies.csrfToken;
    if (token == null || token.isEmpty) {
      throw const BilibiliAuthenticationException(
        'Changing favorites requires a signed-in Bilibili session that '
        'provides a csrf token.',
      );
    }
    return token;
  }
}
