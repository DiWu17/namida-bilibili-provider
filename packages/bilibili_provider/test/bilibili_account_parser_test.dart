import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

String _fixture(String name) {
  return File('test/fixtures/$name').readAsStringSync();
}

void main() {
  const parser = BilibiliAccountParser();

  group('BilibiliAccountParser.parseNavResponse', () {
    test('maps a signed-in nav payload to an authenticated profile', () {
      final nav = parser.parseNavResponse(_fixture('nav_logged_in.json'));

      expect(nav.code, 0);
      expect(nav.isLogin, isTrue);
      expect(nav.validity.isAuthenticated, isTrue);
      expect(nav.validity.requiresSignIn, isFalse);

      final account = nav.account!;
      expect(account.mid, 100000001);
      expect(account.name, 'Example Account');
      expect(account.avatar?.host, 'i0.hdslb.com');
      expect(account.level, 4);
      expect(account.coins, 12.34);
      expect(account.isVip, isTrue);
      expect(account.vipLabel, 'Example Membership Label');
    });

    test('maps code 0 with isLogin=false to the anonymous state', () {
      final nav = parser.parseNavResponse(_fixture('nav_anonymous.json'));

      expect(nav.isLogin, isFalse);
      expect(nav.account, isNull);
      expect(nav.validity.state, BilibiliSessionState.anonymous);
      expect(nav.validity.requiresSignIn, isFalse);
    });

    test('maps -101 to anonymous when no session cookie was sent', () {
      final nav = parser.parseNavResponse(_fixture('nav_not_logged_in.json'));

      expect(nav.code, -101);
      expect(nav.validity.state, BilibiliSessionState.anonymous);
      expect(nav.validity.platformErrorCode, -101);
    });

    test('maps -101 to expired when a session cookie was sent', () {
      final nav = parser.parseNavResponse(
        _fixture('nav_not_logged_in.json'),
        sentSessionToken: true,
      );

      expect(nav.validity.state, BilibiliSessionState.expired);
      expect(nav.validity.requiresSignIn, isTrue);
    });

    test('maps -111 to the csrf-invalid state', () {
      final nav = parser.parseNavResponse(
        _fixture('nav_csrf_invalid.json'),
        sentSessionToken: true,
      );

      expect(nav.validity.state, BilibiliSessionState.csrfInvalid);
      expect(nav.validity.requiresSignIn, isTrue);
    });

    test('records the check timestamp from the caller clock', () {
      final now = DateTime.utc(2025, 1, 2, 3, 4, 5);
      final nav = parser.parseNavResponse(
        _fixture('nav_logged_in.json'),
        now: now,
      );

      expect(nav.validity.checkedAt, now);
    });

    test('throws a structured parse error for invalid JSON', () {
      expect(
        () => parser.parseNavResponse('{not-json'),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('rejects an unsigned payload that has no mid', () {
      expect(
        () => parser.parseNavResponse(
          '{"code":0,"message":"0","data":{"isLogin":true}}',
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('does not leak the raw message into the profile', () {
      final nav = parser.parseNavResponse(_fixture('nav_logged_in.json'));

      expect(nav.toString(), isNot(contains('SESSDATA')));
    });
  });

  group('BilibiliAccountParser.parseMyInfoResponse', () {
    test('parses the current profile', () {
      final account = parser.parseMyInfoResponse(_fixture('space_myinfo.json'));

      expect(account.mid, 100000001);
      expect(account.name, 'Example Account');
      expect(account.sign, contains('offline fixture'));
      expect(account.level, 4);
      expect(account.coins, 12.34);
      expect(account.followingCount, 42);
      expect(account.followerCount, 128);
      expect(account.birthday, '1990-01-01');
      expect(account.vipLabel, 'Example Membership Label');
    });

    test('maps an expired session to an authentication failure', () {
      expect(
        () => parser.parseMyInfoResponse(
          _fixture('fav_folder_list_unauthorized.json'),
        ),
        throwsA(isA<BilibiliAuthenticationException>()),
      );
    });
  });

  group('BilibiliAccountParser folder parsing', () {
    test('parses the created folder list, including private folders', () {
      final folders = parser.parseCreatedFolderListResponse(
        _fixture('fav_folder_list.json'),
      );

      expect(folders, hasLength(3));
      expect(folders.first.mediaId, 200000001);
      expect(folders.first.title, 'Default favorites');
      expect(folders.first.mediaCount, 3);
      expect(folders.first.ownerMid, 100000001);
      expect(folders.first.isPublic, isTrue);
      expect(folders.last.isPublic, isFalse);
    });

    test('parses folder info and normalizes a scheme-relative cover', () {
      final folder = parser.parseFolderInfoResponse(
        _fixture('fav_folder_info.json'),
      );

      expect(folder.mediaId, 200000001);
      expect(folder.cover?.scheme, 'https');
      expect(folder.cover?.host, 'i0.hdslb.com');
      expect(folder.mediaCount, 3);
    });

    test('skips folder entries without a usable id', () {
      final folders = parser.parseCreatedFolderListResponse(
        '{"code":0,"message":"0","data":{"list":['
        '{"title":"no id"},'
        '{"id":0,"title":"zero id"},'
        '{"id":12,"title":"kept"}]}}',
      );

      expect(folders, hasLength(1));
      expect(folders.single.mediaId, 12);
    });

    test('throws when folder info carries no folder id', () {
      expect(
        () => parser.parseFolderInfoResponse(
          '{"code":0,"message":"0","data":{"title":"nameless"}}',
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });
  });

  group('BilibiliAccountParser favorite resources', () {
    test('parses entries, maps playable media and keeps has_more', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_page1.json'),
        folderId: 200000001,
        page: 1,
        pageSize: 20,
      );

      expect(page.page, 1);
      expect(page.hasMore, isTrue);
      expect(page.totalCount, 3);
      expect(page.folder?.title, 'Default favorites');
      expect(page.entries, hasLength(3));

      final first = page.entries.first;
      expect(first.aid, 170001);
      expect(first.bvid, 'BV1xx411c7mD');
      expect(first.duration, const Duration(seconds: 212));
      expect(first.owner?.name, 'Example UP');
      expect(first.owner?.mid, 123456);
      expect(
        first.favoriteTime,
        DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );
      expect(first.isInvalid, isFalse);
    });

    test('excludes expired resources from the provider-neutral list', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_page1.json'),
        folderId: 200000001,
        page: 1,
        pageSize: 20,
      );

      expect(page.entries, hasLength(3));
      expect(page.entries.last.isInvalid, isTrue);
      expect(page.media, hasLength(2));
      expect(page.media.map((m) => m.id.id), <String>[
        'BV1xx411c7mD',
        'BV1yy411c7mE',
      ]);
    });

    test('maps a favorite entry to a CID-less OnlineMedia', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_page1.json'),
        folderId: 200000001,
        page: 1,
        pageSize: 20,
      );
      final media = page.media.first;

      expect(media.id.provider, 'bilibili');
      expect(media.id.id, 'BV1xx411c7mD');
      expect(media.id.subId, isNull);
      expect(media.parts, isEmpty);
      expect(media.title, 'Example Public Bilibili Video');
      expect(media.artist, 'Example UP');
      expect(media.duration, const Duration(seconds: 212));
      expect(media.extra['aid'], 170001);
      expect(media.extra['ownerMid'], 123456);
      expect(media.extra['favoriteFolderId'], 200000001);
      expect(media.extra['invalid'], isFalse);
    });

    test('normalizes a scheme-relative cover on a favorite entry', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_page1.json'),
        folderId: 200000001,
        page: 1,
        pageSize: 20,
      );

      expect(page.media[1].thumbnail?.scheme, 'https');
    });

    test('falls back to "page was full" when has_more is missing', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_no_has_more.json'),
        folderId: 200000001,
        page: 1,
        pageSize: 2,
      );

      expect(page.entries, hasLength(2));
      expect(page.hasMore, isTrue);
    });

    test('stops paginating when a short page has no has_more flag', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_no_has_more.json'),
        folderId: 200000001,
        page: 1,
        pageSize: 5,
      );

      expect(page.hasMore, isFalse);
    });

    test('reports no more pages for the last fixture page', () {
      final page = parser.parseFavoriteResourceListResponse(
        _fixture('fav_resource_list_page2.json'),
        folderId: 200000001,
        page: 2,
        pageSize: 20,
      );

      expect(page.hasMore, isFalse);
      expect(page.media.single.id.id, 'BV1zz411c7mF');
    });
  });

  group('BilibiliAccountParser.parseFavoriteDealResponse', () {
    test('accepts a success envelope without a data object', () {
      expect(
        () => parser.parseFavoriteDealResponse(
          _fixture('fav_resource_deal_ok.json'),
          action: BilibiliFavoriteAction.add,
        ),
        returnsNormally,
      );
    });

    test('maps an invalid csrf token to an authentication failure', () {
      expect(
        () => parser.parseFavoriteDealResponse(
          _fixture('fav_resource_deal_csrf_invalid.json'),
          action: BilibiliFavoriteAction.remove,
        ),
        throwsA(isA<BilibiliAuthenticationException>()),
      );
    });

    test('maps an unknown platform code to a generic API failure', () {
      expect(
        () => parser.parseFavoriteDealResponse(
          '{"code":-400,"message":"请求错误"}',
          action: BilibiliFavoriteAction.add,
        ),
        throwsA(isA<BilibiliApiException>()),
      );
    });
  });
}
