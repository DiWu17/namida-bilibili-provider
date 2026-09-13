import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _secret = 'fixture-sessdata-secret-9f3a';
const String _csrfSecret = 'fixture-csrf-secret-4c1b';

String _fixture(String name) {
  return File('test/fixtures/$name').readAsStringSync();
}

http.Response _jsonFixture(String name, [int statusCode = 200]) {
  return http.Response(
    _fixture(name),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

BilibiliAccountAuthProvider _signedInAuth() {
  return BilibiliAccountAuthProvider(
    BilibiliAccountSession(
      accountId: '100000001',
      cookies: BilibiliCookies(<String, String>{
        'SESSDATA': _secret,
        'bili_jct': _csrfSecret,
        'DedeUserID': '100000001',
      }),
      name: 'Example Account',
    ),
  );
}

void main() {
  group('BilibiliAccountClient.getNav', () {
    test('requests the nav endpoint and attaches the session cookie', () async {
      Map<String, String>? capturedHeaders;
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          capturedHeaders = request.headers;
          expect(request.method, 'GET');
          expect(request.url.host, 'api.bilibili.com');
          expect(request.url.path, '/x/web-interface/nav');
          return _jsonFixture('nav_logged_in.json');
        }),
      );

      final nav = await client.getNav();

      expect(nav.isLogin, isTrue);
      expect(nav.account?.mid, 100000001);
      expect(capturedHeaders?['Cookie'], contains('SESSDATA=$_secret'));
      expect(capturedHeaders?['Referer'], 'https://www.bilibili.com/');
    });

    test('reports anonymous when no cookie is available', () async {
      final client = BilibiliAccountClient(
        httpClient: MockClient((request) async {
          expect(request.headers.containsKey('Cookie'), isFalse);
          return _jsonFixture('nav_not_logged_in.json');
        }),
      );

      final nav = await client.getNav();

      expect(nav.validity.state, BilibiliSessionState.anonymous);
      expect(nav.validity.requiresSignIn, isFalse);
    });

    test('validates a candidate cookie jar through the override', () async {
      Map<String, String>? capturedHeaders;
      final client = BilibiliAccountClient(
        auth: const AnonymousBilibiliAuthProvider(),
        httpClient: MockClient((request) async {
          capturedHeaders = request.headers;
          return _jsonFixture('nav_logged_in.json');
        }),
      );

      final candidate = BilibiliCookies(<String, String>{
        'SESSDATA': 'candidate-$_secret',
        'DedeUserID': '100000001',
      });
      final nav = await client.getNav(cookies: candidate);

      expect(nav.isLogin, isTrue);
      expect(
        capturedHeaders?['Cookie'],
        contains('SESSDATA=candidate-$_secret'),
      );
      expect(client.auth.cookieHeader, isNull);
    });

    test('maps an HTTP denial without leaking the cookie', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async => http.Response('', 403)),
      );

      try {
        await client.getNav();
        fail('expected an access-denied failure');
      } on BilibiliAccessDeniedException catch (error) {
        expect(error.httpStatusCode, 403);
        expect(error.message, isNot(contains(_secret)));
        expect(error.toString(), isNot(contains(_secret)));
      }
    });
  });

  group('BilibiliAccountClient.getMyInfo', () {
    test('requests myinfo and parses the profile', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/x/space/myinfo');
          expect(request.url.queryParameters['web_location'], isNotNull);
          expect(request.url.queryParameters['mid'], isNull);
          return _jsonFixture('space_myinfo.json');
        }),
      );

      final account = await client.getMyInfo();

      expect(account.mid, 100000001);
      expect(account.followingCount, 42);
    });

    test('forwards an explicit mid when provided', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['mid'], '200000002');
          return _jsonFixture('space_myinfo.json');
        }),
      );

      await client.getMyInfo(mid: 200000002);
    });

    test('maps an expired session to an authentication failure', () async {
      final client = BilibiliAccountClient(
        httpClient: MockClient(
          (request) async => _jsonFixture('fav_folder_list_unauthorized.json'),
        ),
      );

      expect(
        () => client.getMyInfo(),
        throwsA(isA<BilibiliAuthenticationException>()),
      );
    });
  });

  group('BilibiliAccountClient favorite folders', () {
    test('requests the created folder list for a mid', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/x/v3/fav/folder/created/list-all');
          expect(request.url.queryParameters['up_mid'], '100000001');
          return _jsonFixture('fav_folder_list.json');
        }),
      );

      final folders = await client.getCreatedFavoriteFolders(mid: 100000001);

      expect(folders, hasLength(3));
      expect(folders.first.mediaId, 200000001);
    });

    test('rejects a non-positive mid before any request', () async {
      var requests = 0;
      final client = BilibiliAccountClient(
        httpClient: MockClient((request) async {
          requests++;
          return _jsonFixture('fav_folder_list.json');
        }),
      );

      await expectLater(
        () => client.getCreatedFavoriteFolders(mid: 0),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(requests, 0);
    });

    test('maps an unauthorized folder listing to an auth failure', () async {
      final client = BilibiliAccountClient(
        httpClient: MockClient(
          (request) async => _jsonFixture('fav_folder_list_unauthorized.json'),
        ),
      );

      expect(
        () => client.getCreatedFavoriteFolders(mid: 100000001),
        throwsA(isA<BilibiliAuthenticationException>()),
      );
    });

    test('parses folder info including metadata requests', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/x/v3/fav/folder/info');
          expect(request.url.queryParameters['media_id'], '200000001');
          return _jsonFixture('fav_folder_info.json');
        }),
      );

      final folder = await client.getFavoriteFolderInfo(mediaId: 200000001);

      expect(folder.title, 'Default favorites');
      expect(folder.cover?.scheme, 'https');
    });
  });

  group('BilibiliAccountClient favorite resources', () {
    test('sends pagination and ordering parameters', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/x/v3/fav/resource/list');
          final query = request.url.queryParameters;
          expect(query['media_id'], '200000001');
          expect(query['pn'], '2');
          expect(query['ps'], '5');
          expect(query['order'], 'view');
          expect(query['platform'], 'web');
          expect(query['keyword'], 'fixture');
          return _jsonFixture('fav_resource_list_page1.json');
        }),
      );

      final page = await client.getFavoriteResources(
        mediaId: 200000001,
        page: 2,
        pageSize: 5,
        order: BilibiliFavoriteOrder.viewCount,
        keyword: '  fixture  ',
      );

      expect(page.page, 2);
      expect(page.pageSize, 5);
      expect(page.media, hasLength(2));
    });

    test('omits an empty keyword', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters.containsKey('keyword'), isFalse);
          return _jsonFixture('fav_resource_list_page1.json');
        }),
      );

      await client.getFavoriteResources(mediaId: 200000001, keyword: '   ');
    });

    test('rejects invalid pagination before any request', () async {
      var requests = 0;
      final client = BilibiliAccountClient(
        httpClient: MockClient((request) async {
          requests++;
          return _jsonFixture('fav_resource_list_page1.json');
        }),
      );

      await expectLater(
        () => client.getFavoriteResources(mediaId: 200000001, page: 0),
        throwsA(isA<BilibiliParseException>()),
      );
      await expectLater(
        () => client.getFavoriteResources(mediaId: 200000001, pageSize: 0),
        throwsA(isA<BilibiliParseException>()),
      );
      await expectLater(
        () => client.getFavoriteResources(mediaId: 200000001, pageSize: 21),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(requests, 0);
    });

    test('paginates until the platform reports the last page', () async {
      final requestedPages = <String>[];
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          final page = request.url.queryParameters['pn']!;
          requestedPages.add(page);
          return _jsonFixture(
            page == '1'
                ? 'fav_resource_list_page1.json'
                : 'fav_resource_list_page2.json',
          );
        }),
      );

      final pages = await client
          .paginateFavoriteResources(mediaId: 200000001, pageSize: 20)
          .toList();

      expect(requestedPages, <String>['1', '2']);
      expect(pages, hasLength(2));
      expect(pages.first.hasMore, isTrue);
      expect(pages.last.hasMore, isFalse);
    });

    test('honors the maxPages safety bound', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient(
          (request) async => _jsonFixture('fav_resource_list_page1.json'),
        ),
      );

      final pages = await client
          .paginateFavoriteResources(
            mediaId: 200000001,
            pageSize: 20,
            maxPages: 3,
          )
          .toList();

      expect(pages, hasLength(3));
    });

    test('collects and deduplicates every playable item', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          final page = request.url.queryParameters['pn']!;
          return _jsonFixture(
            page == '1'
                ? 'fav_resource_list_page1.json'
                : 'fav_resource_list_page2.json',
          );
        }),
      );

      final media = await client.getAllFavoriteMedia(mediaId: 200000001);

      expect(media.map((m) => m.id.id), <String>[
        'BV1xx411c7mD',
        'BV1yy411c7mE',
        'BV1zz411c7mF',
      ]);
    });

    test('accepts a favlist link directly', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['media_id'], '200000001');
          return _jsonFixture('fav_resource_list_page1.json');
        }),
      );

      final page = await client.getFavoriteResourcesFromUri(
        Uri.parse(
          'https://space.bilibili.com/100000001/favlist'
          '?fid=200000001&ftype=create',
        ),
      );

      expect(page.folderId, 200000001);
      expect(page.media, hasLength(2));
    });
  });

  group('BilibiliAccountClient favorite writes', () {
    test('posts an add request with the csrf token from the session', () async {
      http.Request? captured;
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          captured = request;
          return _jsonFixture('fav_resource_deal_ok.json');
        }),
      );

      await client.addFavorite(
        aid: 170001,
        folderIds: <int>[200000001, 200000002],
      );

      expect(captured?.method, 'POST');
      expect(captured?.url.path, '/x/v3/fav/resource/deal');
      expect(
        captured?.headers['content-type'],
        contains('application/x-www-form-urlencoded'),
      );

      final form = Uri.splitQueryString(captured!.body);
      expect(form['rid'], '170001');
      expect(form['type'], '2');
      expect(form['add_media_ids'], '200000001,200000002');
      expect(form['csrf'], _csrfSecret);
      expect(form.containsKey('del_media_ids'), isFalse);
    });

    test('posts a remove request with del_media_ids', () async {
      http.Request? captured;
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          captured = request;
          return _jsonFixture('fav_resource_deal_ok.json');
        }),
      );

      await client.removeFavorite(aid: 170001, folderIds: <int>[200000001]);

      final form = Uri.splitQueryString(captured!.body);
      expect(form['del_media_ids'], '200000001');
      expect(form.containsKey('add_media_ids'), isFalse);
    });

    test(
      'refuses to write without a csrf token, without any request',
      () async {
        var requests = 0;
        final client = BilibiliAccountClient(
          auth: BilibiliAccountAuthProvider(
            BilibiliAccountSession(
              accountId: '100000001',
              cookies: BilibiliCookies(<String, String>{'SESSDATA': _secret}),
            ),
          ),
          httpClient: MockClient((request) async {
            requests++;
            return _jsonFixture('fav_resource_deal_ok.json');
          }),
        );

        try {
          await client.addFavorite(aid: 170001, folderIds: <int>[200000001]);
          fail('expected an authentication failure');
        } on BilibiliAuthenticationException catch (error) {
          expect(error.message, isNot(contains(_secret)));
          expect(error.toString(), isNot(contains(_secret)));
        }
        expect(requests, 0);
      },
    );

    test('maps a rejected csrf token without leaking it', () async {
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient(
          (request) async =>
              _jsonFixture('fav_resource_deal_csrf_invalid.json'),
        ),
      );

      try {
        await client.addFavorite(aid: 170001, folderIds: <int>[200000001]);
        fail('expected an authentication failure');
      } on BilibiliAuthenticationException catch (error) {
        expect(error.platformErrorCode, -111);
        expect(error.toString(), isNot(contains(_csrfSecret)));
        expect(error.toString(), isNot(contains(_secret)));
      }
    });

    test('validates write arguments before any request', () async {
      var requests = 0;
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          requests++;
          return _jsonFixture('fav_resource_deal_ok.json');
        }),
      );

      await expectLater(
        () => client.addFavorite(aid: 0, folderIds: <int>[1]),
        throwsA(isA<BilibiliParseException>()),
      );
      await expectLater(
        () => client.addFavorite(aid: 1, folderIds: <int>[]),
        throwsA(isA<BilibiliParseException>()),
      );
      await expectLater(
        () => client.addFavorite(aid: 1, folderIds: <int>[0]),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(requests, 0);
    });

    test('deduplicates repeated folder ids', () async {
      http.Request? captured;
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        httpClient: MockClient((request) async {
          captured = request;
          return _jsonFixture('fav_resource_deal_ok.json');
        }),
      );

      await client.addFavorite(
        aid: 170001,
        folderIds: <int>[200000001, 200000001, 200000002],
      );

      expect(
        Uri.splitQueryString(captured!.body)['add_media_ids'],
        '200000001,200000002',
      );
    });
  });

  group('debug logging', () {
    test('is off by default', () async {
      final logs = <String>[];
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        debug: false,
        onDebugLog: logs.add,
        httpClient: MockClient(
          (request) async => _jsonFixture('nav_logged_in.json'),
        ),
      );

      await client.getNav();

      expect(logs, isEmpty);
    });

    test('never contains cookies, query strings, or bodies', () async {
      final logs = <String>[];
      final client = BilibiliAccountClient(
        auth: _signedInAuth(),
        debug: true,
        onDebugLog: logs.add,
        httpClient: MockClient((request) async {
          return request.method == 'POST'
              ? _jsonFixture('fav_resource_deal_ok.json')
              : _jsonFixture('nav_logged_in.json');
        }),
      );

      await client.getNav();
      await client.addFavorite(aid: 170001, folderIds: <int>[200000001]);

      expect(logs, hasLength(2));
      expect(logs.first, 'GET api.bilibili.com/x/web-interface/nav -> 200');
      expect(logs.last, 'POST api.bilibili.com/x/v3/fav/resource/deal -> 200');
      for (final line in logs) {
        expect(line, isNot(contains(_secret)));
        expect(line, isNot(contains(_csrfSecret)));
        expect(line, isNot(contains('csrf')));
        expect(line, isNot(contains('?')));
      }
    });
  });
}
