import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String _fixture(String name) {
  return File('test/fixtures/$name').readAsStringSync();
}

http.Response _jsonFixture(String name) {
  return http.Response(
    _fixture(name),
    200,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

void main() {
  group('BilibiliClient.getVideoInfo', () {
    test('requests the BVID endpoint and parses metadata', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.bilibili.com');
          expect(request.url.path, '/x/web-interface/view');
          expect(request.url.queryParameters['bvid'], 'BV1xx411c7mD');
          expect(request.url.queryParameters['aid'], isNull);
          return _jsonFixture('video_info.json');
        }),
      );

      final info = await client.getVideoInfo(id: 'BV1xx411c7mD');

      expect(info.bvid, 'BV1xx411c7mD');
      expect(info.parts, hasLength(1));
    });

    test('requests the aid endpoint for av ids', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['aid'], '170001');
          expect(request.url.queryParameters['bvid'], isNull);
          return _jsonFixture('video_info.json');
        }),
      );

      final info = await client.getVideoInfo(id: 'av170001');

      expect(info.aid, 170001);
    });

    test(
      'maps an access-denied HTTP response to a structured exception',
      () async {
        final client = BilibiliClient(
          httpClient: MockClient((request) async => http.Response('', 403)),
        );

        expect(
          () => client.getVideoInfo(id: 'BV1xx411c7mD'),
          throwsA(isA<BilibiliAccessDeniedException>()),
        );
      },
    );
  });

  group('BilibiliClient.resolveShortUrl', () {
    test('follows one safe redirect to a canonical Bilibili URL', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          if (request.url.host == 'b23.tv') {
            return http.Response(
              '',
              302,
              headers: const <String, String>{
                'location':
                    'https://www.bilibili.com/video/BV1xx411c7mD?spm_id_from=333.999',
              },
            );
          }
          return _jsonFixture('video_info.json');
        }),
      );

      final resolved = await client.resolveShortUrl(
        Uri.parse('https://b23.tv/abc123'),
      );

      expect(resolved.host, 'www.bilibili.com');
      expect(resolved.path, '/video/BV1xx411c7mD');
    });

    test('rejects a redirect to an unsupported host', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          return http.Response(
            '',
            302,
            headers: const <String, String>{
              'location': 'https://evil.example/video/BV1xx411c7mD',
            },
          );
        }),
      );

      expect(
        () => client.resolveShortUrl(Uri.parse('https://b23.tv/abc123')),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
    });

    test('enforces the configured redirect limit', () async {
      final client = BilibiliClient(
        maxShortLinkRedirects: 2,
        httpClient: MockClient((request) async {
          return http.Response(
            '',
            302,
            headers: const <String, String>{'location': 'https://b23.tv/loop'},
          );
        }),
      );

      expect(
        () => client.resolveShortUrl(Uri.parse('https://b23.tv/loop')),
        throwsA(isA<BilibiliNetworkException>()),
      );
    });
  });

  group('BilibiliClient request headers', () {
    test('forwards explicit auth cookie without logging it', () async {
      Map<String, String>? capturedHeaders;
      final client = BilibiliClient(
        auth: SessionBilibiliAuthProvider(
          const BilibiliSession(cookie: 'SESSDATA=fixture-cookie'),
        ),
        httpClient: MockClient((request) async {
          capturedHeaders = request.headers;
          return _jsonFixture('video_info.json');
        }),
      );

      await client.getVideoInfo(id: 'BV1xx411c7mD');

      expect(capturedHeaders?['Referer'], 'https://www.bilibili.com/');
      expect(capturedHeaders?['User-Agent'], isNotEmpty);
      expect(capturedHeaders?['Cookie'], 'SESSDATA=fixture-cookie');
    });
  });
}
