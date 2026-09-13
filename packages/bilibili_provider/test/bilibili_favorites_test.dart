import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_media_provider/online_media_provider.dart';
import 'package:test/test.dart';

const String _sess = 'fixture-sessdata-secret-9f3a';
const String _csrf = 'fixture-csrf-secret-4c1b';

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

BilibiliAccountAuthProvider _auth() {
  return BilibiliAccountAuthProvider(
    BilibiliAccountSession(
      accountId: '100000001',
      cookies: BilibiliCookies(<String, String>{
        'SESSDATA': _sess,
        'bili_jct': _csrf,
        'DedeUserID': '100000001',
      }),
    ),
  );
}

void main() {
  group('favorite folder browsing', () {
    test('lists folders and then reads the selected folder', () async {
      final client = BilibiliAccountClient(
        auth: _auth(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/x/v3/fav/folder/created/list-all') {
            return _jsonFixture('fav_folder_list.json');
          }
          if (request.url.path == '/x/v3/fav/resource/list') {
            return _jsonFixture('fav_resource_list_page1.json');
          }
          return http.Response('', 404);
        }),
      );

      final folders = await client.getCreatedFavoriteFolders(mid: 100000001);
      final publicFolders = folders.where((f) => f.isPublic).toList();
      final page = await client.getFavoriteResources(
        mediaId: publicFolders.first.mediaId,
      );

      expect(publicFolders, hasLength(2));
      expect(page.folder?.title, 'Default favorites');
      expect(page.media, hasLength(2));
      expect(page.hasMore, isTrue);
    });

    test('reads every page and reports the provider-neutral items', () async {
      final client = BilibiliAccountClient(
        auth: _auth(),
        httpClient: MockClient((request) async {
          final page = request.url.queryParameters['pn']!;
          return _jsonFixture(
            page == '1'
                ? 'fav_resource_list_page1.json'
                : 'fav_resource_list_page2.json',
          );
        }),
      );

      final media = await client.getAllFavoriteMedia(
        mediaId: 200000001,
        pageSize: 20,
      );

      expect(media, hasLength(3));
      expect(media.every((m) => m.id.provider == 'bilibili'), isTrue);
      expect(media.every((m) => m.id.subId == null), isTrue);
      expect(media.first.extra['favoriteFolderId'], 200000001);
    });
  });

  group('favorites to playback bridge', () {
    test(
      'resolveById fills in the CID that favorites do not provide',
      () async {
        final client = BilibiliAccountClient(
          auth: _auth(),
          httpClient: MockClient((request) async {
            final page = request.url.queryParameters['pn']!;
            return _jsonFixture(
              page == '1'
                  ? 'fav_resource_list_page1.json'
                  : 'fav_resource_list_page2.json',
            );
          }),
        );
        final provider = BilibiliProvider(
          client: BilibiliClient(
            httpClient: MockClient((request) async {
              if (request.url.path == '/x/web-interface/view') {
                return _jsonFixture('video_info.json');
              }
              if (request.url.path == '/x/player/playurl') {
                expect(request.url.queryParameters['cid'], '987654321');
                return _jsonFixture('dash_playurl.json');
              }
              return http.Response('', 404);
            }),
          ),
        );

        final favorite = (await client.getAllFavoriteMedia(
          mediaId: 200000001,
        )).first;
        expect(favorite.id.subId, isNull);
        expect(
          () => provider.getPlayback(favorite.id),
          throwsA(isA<BilibiliNotFoundException>()),
        );

        final resolved = await provider.resolveById(favorite.id);

        expect(resolved.id.id, 'BV1xx411c7mD');
        expect(resolved.id.subId, '987654321');
        expect(resolved.parts, hasLength(1));
        expect(resolved.title, 'Example Public Bilibili Video');

        final playback = await provider.getPlayback(resolved.id);
        expect(playback.videoStreams, isNotEmpty);
        expect(playback.audioStreams, isNotEmpty);
      },
    );

    test('resolveById honors the preferred part index', () async {
      final provider = BilibiliProvider(
        client: BilibiliClient(
          httpClient: MockClient((request) async {
            expect(request.url.queryParameters['bvid'], 'BV1yy411c7mE');
            return _jsonFixture('multi_part_video.json');
          }),
        ),
      );

      final resolved = await provider.resolveById(
        const OnlineMediaId(provider: 'bilibili', id: 'BV1yy411c7mE'),
        options: const OnlineMediaResolveOptions(preferredPartIndex: 2),
      );

      expect(resolved.id.subId, '333333333');
      expect(resolved.parts, hasLength(3));
    });

    test('resolveById keeps an explicit subId', () async {
      final provider = BilibiliProvider(
        client: BilibiliClient(
          httpClient: MockClient(
            (request) async => _jsonFixture('multi_part_video.json'),
          ),
        ),
      );

      final resolved = await provider.resolveById(
        const OnlineMediaId(
          provider: 'bilibili',
          id: 'BV1yy411c7mE',
          subId: '222222222',
        ),
      );

      expect(resolved.id.subId, '222222222');
    });

    test('resolveById rejects a foreign provider id', () async {
      final provider = BilibiliProvider.anonymous();

      expect(
        () => provider.resolveById(
          const OnlineMediaId(provider: 'youtube', id: 'dQw4w9WgXcQ'),
        ),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
    });
  });

  group('favorite writes through the account layer', () {
    test('deals a favorite using the signed-in session cookies', () async {
      final auth = _auth();
      final client = BilibiliAccountClient(
        auth: auth,
        httpClient: MockClient((request) async {
          expect(request.headers['Cookie'], contains('SESSDATA=$_sess'));
          final form = Uri.splitQueryString(request.body);
          expect(form['csrf'], _csrf);
          return _jsonFixture('fav_resource_deal_ok.json');
        }),
      );

      await client.addFavorite(aid: 170001, folderIds: <int>[200000001]);

      expect(auth.toString(), isNot(contains(_sess)));
    });

    test(
      'surfaces an insufficient-permission folder as an API failure',
      () async {
        final client = BilibiliAccountClient(
          auth: _auth(),
          httpClient: MockClient(
            (request) async => http.Response(
              '{"code":62004,"message":"folder not accessible"}',
              200,
            ),
          ),
        );

        expect(
          () => client.addFavorite(aid: 170001, folderIds: <int>[200000001]),
          throwsA(isA<BilibiliAccessDeniedException>()),
        );
      },
    );
  });
}
