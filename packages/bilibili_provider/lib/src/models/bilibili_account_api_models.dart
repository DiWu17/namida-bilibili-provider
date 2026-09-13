import 'package:online_media_provider/online_media_provider.dart';

import '../account/bilibili_account_session.dart';
import 'bilibili_api_models.dart';

/// Internal model for `x/web-interface/nav` and `x/space/myinfo`.
///
/// Only the account layer consumes this type; callers receive provider-neutral
/// media or the account-layer DTOs.
class BilibiliAccountInfo {
  const BilibiliAccountInfo({
    required this.mid,
    required this.name,
    this.avatar,
    this.sign,
    this.level,
    this.coins,
    this.followingCount,
    this.followerCount,
    this.birthday,
    this.isVip = false,
    this.vipLabel,
  });

  /// Numeric Bilibili user id.
  final int mid;

  /// Display name.
  final String name;

  final Uri? avatar;

  /// Profile signature.
  final String? sign;

  /// Account level, as reported by the platform.
  final int? level;

  /// B coin balance, when the endpoint reports it.
  final double? coins;

  final int? followingCount;

  final int? followerCount;

  /// Birthday string as reported by `x/space/myinfo`.
  final String? birthday;

  /// Whether the platform reports an active VIP/membership badge.
  ///
  /// This is informational only. This package does not use it to unlock any
  /// restricted content or quality.
  final bool isVip;

  /// VIP label text, when present.
  final String? vipLabel;

  @override
  String toString() => 'BilibiliAccountInfo($mid, $name)';
}

/// Internal result of `x/web-interface/nav`.
///
/// `nav` reports "not signed in" as a non-zero platform code, so the raw [code]
/// is preserved next to the parsed [validity] instead of being thrown.
class BilibiliNavResult {
  const BilibiliNavResult({
    required this.code,
    required this.message,
    required this.validity,
    this.account,
  });

  /// Raw platform code, or null when the response had no usable code.
  final int? code;

  /// Platform message. Never contains cookie material.
  final String message;

  final BilibiliCookieValidity validity;

  /// Parsed profile when the server reports a signed-in account.
  final BilibiliAccountInfo? account;

  /// Whether the server reports a signed-in account.
  bool get isLogin => account != null;

  @override
  String toString() => 'BilibiliNavResult(code: $code, login: $isLogin)';
}

/// Internal model for a favorite folder (`x/v3/fav/folder/...`).
class BilibiliFavoriteFolder {
  const BilibiliFavoriteFolder({
    required this.mediaId,
    required this.title,
    this.ownerMid,
    this.mediaCount = 0,
    this.cover,
    this.intro,
    this.isPublic = true,
  });

  /// Folder id used as `media_id` by the resource endpoints.
  final int mediaId;

  final String title;

  /// Owner mid, when the endpoint reports it.
  final int? ownerMid;

  /// Number of resources the folder claims to contain.
  final int mediaCount;

  final Uri? cover;

  final String? intro;

  /// Whether the folder is public. Private folders still only ever expose the
  /// signed-in user's own content.
  final bool isPublic;

  @override
  String toString() =>
      'BilibiliFavoriteFolder($mediaId, $title, count: $mediaCount)';
}

/// Internal model for one resource inside a favorite folder.
class BilibiliFavoriteItem {
  const BilibiliFavoriteItem({
    required this.aid,
    required this.bvid,
    required this.title,
    this.intro,
    this.cover,
    this.duration,
    this.owner,
    this.favoriteTime,
    this.publishTime,
    this.attr = 0,
  });

  /// Numeric archive id. Favorite write APIs use this as `rid`.
  final int aid;

  /// BVID. Empty when the platform did not report one.
  final String bvid;

  final String title;
  final String? intro;
  final Uri? cover;
  final Duration? duration;
  final BilibiliOwner? owner;

  /// When the resource was added to the folder.
  final DateTime? favoriteTime;

  /// When the resource was published.
  final DateTime? publishTime;

  /// Raw platform `attr` bitfield.
  final int attr;

  /// Whether the platform marks this resource as deleted, private, or
  /// otherwise unavailable.
  bool get isInvalid {
    return (attr & 1) != 0 || title == '已失效视频' || title == '已失效稿件';
  }

  /// Whether the item has enough information for playback resolution.
  bool get isPlayable => !isInvalid && bvid.isNotEmpty;

  @override
  String toString() => 'BilibiliFavoriteItem($bvid, $title)';
}

/// One page of a favorite folder.
class BilibiliFavoritePage {
  BilibiliFavoritePage({
    required List<BilibiliFavoriteItem> entries,
    required List<OnlineMedia> media,
    required this.folderId,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.totalCount,
    this.folder,
  }) : entries = List<BilibiliFavoriteItem>.unmodifiable(entries),
       media = List<OnlineMedia>.unmodifiable(media);

  /// Raw platform entries, including resources that are no longer playable.
  final List<BilibiliFavoriteItem> entries;

  /// Provider-neutral items mapped from [entries]. Invalid resources are
  /// excluded because they cannot be resolved or played.
  ///
  /// These items carry a BVID but no CID; use
  /// `BilibiliProvider.resolveById` before `getPlayback`.
  final List<OnlineMedia> media;

  /// Folder id this page was read from.
  final int folderId;

  /// 1-based page number.
  final int page;

  final int pageSize;

  /// Whether the platform reports another page.
  final bool hasMore;

  /// Total resource count reported for the folder, when available.
  final int? totalCount;

  /// Folder metadata returned alongside the resource list, when available.
  final BilibiliFavoriteFolder? folder;

  bool get isEmpty => entries.isEmpty;

  @override
  String toString() {
    return 'BilibiliFavoritePage(folder: $folderId, page: $page, '
        'entries: ${entries.length}, hasMore: $hasMore)';
  }
}

/// Sort order accepted by `x/v3/fav/resource/list`.
enum BilibiliFavoriteOrder {
  /// Sort by the time the resource was added to the folder.
  favoriteTime('mtime'),

  /// Sort by play count.
  viewCount('view');

  const BilibiliFavoriteOrder(this.platformValue);

  /// Value sent as the `order` query parameter.
  final String platformValue;
}

/// Write action for `x/v3/fav/resource/deal`.
enum BilibiliFavoriteAction {
  /// Add the archive to one or more folders.
  add('add_media_ids'),

  /// Remove the archive from one or more folders.
  remove('del_media_ids');

  const BilibiliFavoriteAction(this.platformField);

  /// Form field that carries the folder ids.
  final String platformField;
}
