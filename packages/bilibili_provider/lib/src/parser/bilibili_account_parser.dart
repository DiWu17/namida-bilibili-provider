import 'package:online_media_provider/online_media_provider.dart';

import '../account/bilibili_account_session.dart';
import '../account/bilibili_cookies.dart';
import '../errors/bilibili_exception.dart';
import '../models/bilibili_account_api_models.dart';
import '../models/bilibili_api_models.dart';
import '../models/bilibili_qr_login_models.dart';
import 'bilibili_api_response.dart';

/// Parses account, profile and favorite-folder responses.
///
/// All cookies and csrf tokens are request-side only: nothing in a response body
/// carries credentials, so this parser never needs to touch a secret.
class BilibiliAccountParser {
  const BilibiliAccountParser();

  /// Provider id used for every [OnlineMediaId] created here.
  static const String providerId = 'bilibili';

  /// Parses `x/web-interface/nav`.
  ///
  /// `nav` reports "not signed in" as a non-zero code, which is a normal state
  /// for anonymous access, so [BilibiliNavResult.validity] is returned instead
  /// of throwing. Transport/parse failures still throw.
  ///
  /// [sentSessionToken] tells the parser whether the request actually carried a
  /// session cookie. Without that hint a `-101` answer is indistinguishable
  /// between "the caller sent nothing" (anonymous) and "the caller's cookie was
  /// rejected" (expired), and the two need very different UI.
  BilibiliNavResult parseNavResponse(
    String body, {
    DateTime? now,
    bool sentSessionToken = false,
  }) {
    final envelope = BilibiliApiResponse.decodeEnvelope(
      body,
      operation: 'Bilibili nav API',
    );

    final checkedAt = now ?? DateTime.now();
    final code = envelope.code;

    if (code != null && code != 0) {
      var state = _navStateForCode(code);
      if (state == BilibiliSessionState.expired && !sentSessionToken) {
        state = BilibiliSessionState.anonymous;
      }
      return BilibiliNavResult(
        code: code,
        message: envelope.message,
        validity: BilibiliCookieValidity(
          state: state,
          checkedAt: checkedAt,
          platformErrorCode: code,
          message: envelope.message,
        ),
      );
    }

    final data = envelope.data;
    if (data == null) {
      throw const BilibiliParseException(
        'Bilibili nav API returned no data object.',
      );
    }

    final isLogin =
        BilibiliApiResponse.asBool(data['isLogin']) ??
        ((BilibiliApiResponse.asInt(data['mid']) ?? 0) > 0);

    if (!isLogin) {
      return BilibiliNavResult(
        code: code,
        message: envelope.message,
        validity: BilibiliCookieValidity(
          state: BilibiliSessionState.anonymous,
          checkedAt: checkedAt,
          platformErrorCode: code,
          message: envelope.message,
        ),
      );
    }

    final account = _parseAccountInfo(data);
    if (account == null) {
      throw const BilibiliParseException(
        'Bilibili nav API reported a signed-in account without a mid.',
      );
    }

    return BilibiliNavResult(
      code: code,
      message: envelope.message,
      account: account,
      validity: BilibiliCookieValidity(
        state: BilibiliSessionState.authenticated,
        checkedAt: checkedAt,
        platformErrorCode: code,
        message: envelope.message,
      ),
    );
  }

  /// Parses `x/passport-login/web/qrcode/generate`.
  ///
  /// Returns the ticket the caller renders as a QR image plus the key it polls
  /// with. Requires being called again once the ticket expires.
  BilibiliQrLogin parseQrLoginGenerateResponse(String body) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili QR login generate API',
    );

    final qrcodeKey = BilibiliApiResponse.asString(data['qrcode_key']);
    if (qrcodeKey == null || qrcodeKey.isEmpty) {
      throw const BilibiliParseException(
        'Bilibili QR login generate API returned no qrcode_key.',
      );
    }

    final rawUri = BilibiliApiResponse.asString(data['url']);
    final uri = rawUri == null ? null : Uri.tryParse(rawUri);
    if (uri == null || !uri.hasScheme) {
      throw const BilibiliParseException(
        'Bilibili QR login generate API returned no usable login URL.',
      );
    }

    return BilibiliQrLogin(qrcodeKey: qrcodeKey, uri: uri);
  }

  /// Parses `x/passport-login/web/qrcode/poll`.
  ///
  /// The platform reports success, "not scanned", "scanned", and "expired"
  /// through `data.code` while the envelope code stays `0`, so this never throws
  /// for those states: it maps them onto [BilibiliQrLoginStage].
  ///
  /// Session cookies may arrive either as `Set-Cookie` headers or inside
  /// `data.url` (the platform's cross-domain redirect URL). Both sources are
  /// merged, because which one carries the session has varied.
  BilibiliQrLoginStatus parseQrLoginPollResponse(
    String body, {
    List<String> setCookieHeaders = const <String>[],
  }) {
    final envelope = BilibiliApiResponse.decodeEnvelope(
      body,
      operation: 'Bilibili QR login poll API',
    );

    if (!envelope.isOk) {
      return BilibiliQrLoginStatus(
        stage: BilibiliQrLoginStage.failed,
        message: envelope.message,
      );
    }

    final data = envelope.data;
    if (data == null) {
      return const BilibiliQrLoginStatus(
        stage: BilibiliQrLoginStage.failed,
        message: 'Bilibili QR login poll API returned no data object.',
      );
    }

    final platformCode = BilibiliApiResponse.asInt(data['code']);
    final platformMessage = BilibiliApiResponse.asString(data['message']);
    final refreshToken = BilibiliApiResponse.asString(data['refresh_token']);

    switch (platformCode) {
      case 0:
        final cookies = _cookiesFromQrLogin(
          setCookieHeaders: setCookieHeaders,
          redirectUrl: BilibiliApiResponse.asString(data['url']),
        );
        if (!cookies.hasSessionToken) {
          return BilibiliQrLoginStatus(
            stage: BilibiliQrLoginStage.failed,
            message:
                'Bilibili confirmed the QR login but returned no usable '
                'session cookie.',
            refreshToken: refreshToken,
          );
        }
        return BilibiliQrLoginStatus(
          stage: BilibiliQrLoginStage.confirmed,
          message: platformMessage,
          cookies: cookies,
          refreshToken: refreshToken,
        );
      case 86101:
        return BilibiliQrLoginStatus(
          stage: BilibiliQrLoginStage.pending,
          message: platformMessage,
        );
      case 86090:
        return BilibiliQrLoginStatus(
          stage: BilibiliQrLoginStage.scanned,
          message: platformMessage,
        );
      case 86038:
        return BilibiliQrLoginStatus(
          stage: BilibiliQrLoginStage.expired,
          message: platformMessage,
        );
      default:
        return BilibiliQrLoginStatus(
          stage: BilibiliQrLoginStage.failed,
          message: platformMessage ?? 'Unexpected QR login state.',
        );
    }
  }

  /// Merges the two places the QR login flow may deliver cookies.
  ///
  /// `Set-Cookie` is authoritative when present; cookies embedded in the
  /// cross-domain URL fill in whatever the headers did not carry. Only known
  /// Bilibili cookie names are taken from the URL, so unrelated query parameters
  /// (such as `gourl`) cannot pollute the jar.
  BilibiliCookies _cookiesFromQrLogin({
    required List<String> setCookieHeaders,
    required String? redirectUrl,
  }) {
    final fromHeaders = BilibiliCookies.fromSetCookieHeaders(setCookieHeaders);
    final fromUrl = _cookiesFromRedirectUrl(redirectUrl);
    // merge() lets its argument win, so headers are merged last and stay
    // authoritative. An empty source contributes nothing either way.
    return fromUrl.merge(fromHeaders);
  }

  BilibiliCookies _cookiesFromRedirectUrl(String? url) {
    if (url == null || url.isEmpty) {
      return BilibiliCookies.empty;
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return BilibiliCookies.empty;
    }

    final values = <String, String>{};
    for (final name in _redirectCookieNames) {
      final value = parsed.queryParameters[name];
      if (value != null && value.isNotEmpty) {
        values[name] = value;
      }
    }
    return BilibiliCookies(values);
  }

  static const Set<String> _redirectCookieNames = <String>{
    BilibiliCookies.sessDataName,
    BilibiliCookies.csrfName,
    BilibiliCookies.userIdName,
    BilibiliCookies.userIdCheckName,
    BilibiliCookies.sessionIdName,
  };

  /// Parses `x/space/myinfo` into the current account profile.
  ///
  /// Requires a signed-in session; an expired session surfaces as
  /// [BilibiliAuthenticationException].
  BilibiliAccountInfo parseMyInfoResponse(String body) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili myinfo API',
    );

    final account = _parseAccountInfo(data);
    if (account == null) {
      throw const BilibiliParseException(
        'Bilibili myinfo API returned no usable mid.',
      );
    }
    return account;
  }

  /// Parses `x/v3/fav/folder/created/list-all`.
  List<BilibiliFavoriteFolder> parseCreatedFolderListResponse(String body) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili favorite folder list API',
    );

    final rawList =
        BilibiliApiResponse.asList(data['list']) ??
        BilibiliApiResponse.asList(data['folders']) ??
        const <Object?>[];

    final folders = <BilibiliFavoriteFolder>[];
    for (final raw in rawList) {
      final folder = _parseFolder(raw);
      if (folder != null) {
        folders.add(folder);
      }
    }
    return List<BilibiliFavoriteFolder>.unmodifiable(folders);
  }

  /// Parses `x/v3/fav/folder/info`.
  BilibiliFavoriteFolder parseFolderInfoResponse(String body) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili favorite folder info API',
    );

    final folder = _parseFolder(data);
    if (folder == null) {
      throw const BilibiliParseException(
        'Bilibili favorite folder info API returned no folder id.',
      );
    }
    return folder;
  }

  /// Parses one page of `x/v3/fav/resource/list`.
  ///
  /// [hasMore] falls back to "the page was full" when the platform omits the
  /// flag, which keeps pagination from stopping early.
  BilibiliFavoritePage parseFavoriteResourceListResponse(
    String body, {
    required int folderId,
    required int page,
    required int pageSize,
  }) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili favorite resource list API',
    );

    final rawList =
        BilibiliApiResponse.asList(data['medias']) ??
        BilibiliApiResponse.asList(data['list']) ??
        const <Object?>[];

    final entries = <BilibiliFavoriteItem>[];
    for (final raw in rawList) {
      final item = _parseFavoriteItem(raw);
      if (item != null) {
        entries.add(item);
      }
    }

    final folder = _parseFolder(data['info']);
    final hasMore =
        BilibiliApiResponse.asBool(data['has_more']) ??
        (entries.length >= pageSize && pageSize > 0);

    return BilibiliFavoritePage(
      entries: entries,
      media: toOnlineMediaList(entries, folderId: folderId),
      folderId: folder?.mediaId ?? folderId,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
      totalCount: folder?.mediaCount,
      folder: folder,
    );
  }

  /// Parses the `x/v3/fav/resource/deal` write response.
  ///
  /// The write endpoints answer with `code: 0` and no `data` object, so this
  /// validates the envelope instead of requiring data.
  void parseFavoriteDealResponse(
    String body, {
    required BilibiliFavoriteAction action,
  }) {
    final envelope = BilibiliApiResponse.decodeEnvelope(
      body,
      operation: 'Bilibili favorite ${action.name} API',
    );

    if (envelope.isOk) {
      return;
    }

    throw BilibiliApiResponse.exceptionForApiCode(
      code: envelope.code!,
      message: envelope.message,
    );
  }

  /// Maps one favorite entry to a provider-neutral [OnlineMedia].
  ///
  /// The result carries a BVID but no part/CID: the favorite list API does not
  /// expose CIDs. Resolve the item through `BilibiliProvider.resolveById` before
  /// requesting playback.
  OnlineMedia toOnlineMedia(BilibiliFavoriteItem item, {int? folderId}) {
    final owner = item.owner;
    return OnlineMedia(
      id: OnlineMediaId(provider: providerId, id: item.bvid),
      title: item.title,
      artist: owner?.name,
      thumbnail: item.cover,
      duration: item.duration,
      description: item.intro,
      extra: <String, Object?>{
        'aid': item.aid,
        if (owner?.mid != null) 'ownerMid': owner!.mid,
        if (folderId != null) 'favoriteFolderId': folderId,
        'favoriteTime': item.favoriteTime?.toIso8601String(),
        'publishTime': item.publishTime?.toIso8601String(),
        'invalid': item.isInvalid,
      },
    );
  }

  /// Maps favorite entries, skipping resources the platform marked invalid.
  List<OnlineMedia> toOnlineMediaList(
    Iterable<BilibiliFavoriteItem> items, {
    int? folderId,
  }) {
    return List<OnlineMedia>.unmodifiable(<OnlineMedia>[
      for (final item in items)
        if (item.isPlayable) toOnlineMedia(item, folderId: folderId),
    ]);
  }

  BilibiliSessionState _navStateForCode(int code) {
    switch (code) {
      case -101:
        return BilibiliSessionState.expired;
      case -111:
        return BilibiliSessionState.csrfInvalid;
      default:
        return BilibiliSessionState.unknown;
    }
  }

  BilibiliAccountInfo? _parseAccountInfo(Map<String, Object?> data) {
    final mid = BilibiliApiResponse.asInt(data['mid']);
    if (mid == null || mid <= 0) {
      return null;
    }

    final levelInfo = BilibiliApiResponse.asMap(data['level_info']);
    final vip = BilibiliApiResponse.asMap(data['vip']);

    final level =
        BilibiliApiResponse.asInt(data['level']) ??
        BilibiliApiResponse.asInt(levelInfo?['current_level']);

    final vipStatus =
        BilibiliApiResponse.asInt(data['vipStatus']) ??
        BilibiliApiResponse.asInt(vip?['status']) ??
        0;
    final vipType =
        BilibiliApiResponse.asInt(data['vipType']) ??
        BilibiliApiResponse.asInt(vip?['type']) ??
        0;

    final name =
        BilibiliApiResponse.asString(data['uname']) ??
        BilibiliApiResponse.asString(data['name']);
    if (name == null || name.isEmpty) {
      return null;
    }

    return BilibiliAccountInfo(
      mid: mid,
      name: name,
      avatar: _asImageUri(data['face']),
      sign: BilibiliApiResponse.asString(data['sign']),
      level: level,
      coins:
          BilibiliApiResponse.asDouble(data['coins']) ??
          BilibiliApiResponse.asDouble(data['money']) ??
          BilibiliApiResponse.asDouble(data['coins_num']),
      followingCount: BilibiliApiResponse.asInt(data['following']),
      followerCount: BilibiliApiResponse.asInt(data['follower']),
      birthday: BilibiliApiResponse.asString(data['birthday']),
      isVip: vipStatus != 0 || vipType != 0,
      vipLabel:
          BilibiliApiResponse.asString(vip?['label']) ??
          BilibiliApiResponse.asString(
            BilibiliApiResponse.asMap(vip?['label'])?['text'],
          ),
    );
  }

  BilibiliFavoriteFolder? _parseFolder(Object? raw) {
    final map = BilibiliApiResponse.asMap(raw);
    if (map == null) {
      return null;
    }

    final mediaId =
        BilibiliApiResponse.asInt(map['id']) ??
        BilibiliApiResponse.asInt(map['fid']) ??
        BilibiliApiResponse.asInt(map['media_id']);
    if (mediaId == null || mediaId <= 0) {
      return null;
    }

    final attr = BilibiliApiResponse.asInt(map['attr']) ?? 0;
    final title =
        BilibiliApiResponse.asString(map['title']) ??
        BilibiliApiResponse.asString(map['name']) ??
        '';

    return BilibiliFavoriteFolder(
      mediaId: mediaId,
      title: title,
      ownerMid:
          BilibiliApiResponse.asInt(map['mid']) ??
          BilibiliApiResponse.asInt(map['upper_mid']),
      mediaCount: BilibiliApiResponse.asInt(map['media_count']) ?? 0,
      cover: _asImageUri(map['cover']),
      intro: BilibiliApiResponse.asString(map['intro']),
      isPublic: (attr & 1) == 0,
    );
  }

  BilibiliFavoriteItem? _parseFavoriteItem(Object? raw) {
    final map = BilibiliApiResponse.asMap(raw);
    if (map == null) {
      return null;
    }

    final aid =
        BilibiliApiResponse.asInt(map['id']) ??
        BilibiliApiResponse.asInt(map['aid']);
    if (aid == null || aid <= 0) {
      return null;
    }

    final title = BilibiliApiResponse.asString(map['title']) ?? '';

    return BilibiliFavoriteItem(
      aid: aid,
      bvid: BilibiliApiResponse.asString(map['bvid']) ?? '',
      title: title,
      intro: BilibiliApiResponse.asString(map['intro']),
      cover: _asImageUri(map['cover']),
      duration: BilibiliApiResponse.asDurationSeconds(map['duration']),
      owner: _parseOwner(map['upper'] ?? map['owner']),
      favoriteTime: BilibiliApiResponse.asDateTimeSeconds(map['fav_time']),
      publishTime: BilibiliApiResponse.asDateTimeSeconds(map['pubtime']),
      attr: BilibiliApiResponse.asInt(map['attr']) ?? 0,
    );
  }

  BilibiliOwner? _parseOwner(Object? raw) {
    final owner = BilibiliApiResponse.asMap(raw);
    if (owner == null) {
      return null;
    }
    return BilibiliOwner(
      mid: BilibiliApiResponse.asInt(owner['mid']),
      name: BilibiliApiResponse.asString(owner['name']),
      avatar: _asImageUri(owner['face']),
    );
  }

  /// Accepts absolute and scheme-relative (`//host/path`) image URLs.
  Uri? _asImageUri(Object? value) {
    final raw = BilibiliApiResponse.asString(value);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final normalized = raw.startsWith('//') ? 'https:$raw' : raw;
    final parsed = Uri.tryParse(normalized);
    if (parsed == null || !parsed.hasScheme) {
      return null;
    }
    return parsed;
  }
}
