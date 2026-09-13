import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_media_provider/online_media_provider.dart';
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

BilibiliProvider _providerWith(HttpClientHandler handler) {
  return BilibiliProvider(
    client: BilibiliClient(httpClient: MockClient(handler)),
  );
}

typedef HttpClientHandler =
    Future<http.Response> Function(http.Request request);

void main() {
  test('resolve maps a canonical BVID to OnlineMedia', () async {
    final provider = _providerWith((request) async {
      expect(request.url.queryParameters['bvid'], 'BV1xx411c7mD');
      return _jsonFixture('video_info.json');
    });

    final media = await provider.resolve(
      Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
    );

    expect(media.id.provider, 'bilibili');
    expect(media.id.id, 'BV1xx411c7mD');
    expect(media.id.subId, '987654321');
    expect(media.artist, 'Example UP');
    expect(media.parts, hasLength(1));
  });

  test('resolve honors ?p= for multi-part videos', () async {
    final provider = _providerWith((request) async {
      return _jsonFixture('multi_part_video.json');
    });

    final media = await provider.resolve(
      Uri.parse('https://www.bilibili.com/video/BV1yy411c7mE?p=2'),
    );

    expect(media.id.id, 'BV1yy411c7mE');
    expect(media.id.subId, '222222222');
    expect(media.parts, hasLength(3));
    expect(media.parts[1].title, 'P2 - Main Topic');
  });

  test('resolve honors preferredPartIndex when URL has no p', () async {
    final provider = _providerWith((request) async {
      return _jsonFixture('multi_part_video.json');
    });

    final media = await provider.resolve(
      Uri.parse('https://www.bilibili.com/video/BV1yy411c7mE'),
      options: const OnlineMediaResolveOptions(preferredPartIndex: 2),
    );

    expect(media.id.subId, '333333333');
  });

  test(
    'resolve resolves b23.tv short links before fetching metadata',
    () async {
      var shortLinkRequests = 0;
      final provider = _providerWith((request) async {
        if (request.url.host == 'b23.tv') {
          shortLinkRequests++;
          return http.Response(
            '',
            302,
            headers: const <String, String>{
              'location': 'https://www.bilibili.com/video/BV1xx411c7mD',
            },
          );
        }
        if (request.url.host == 'www.bilibili.com') {
          return http.Response('', 200);
        }
        expect(request.url.host, 'api.bilibili.com');
        expect(request.url.queryParameters['bvid'], 'BV1xx411c7mD');
        return _jsonFixture('video_info.json');
      });

      final media = await provider.resolve(Uri.parse('https://b23.tv/abc123'));

      expect(shortLinkRequests, 1);
      expect(media.id.id, 'BV1xx411c7mD');
      expect(media.id.subId, '987654321');
    },
  );

  test('resolve rejects a page that is outside the available parts', () async {
    final provider = _providerWith((request) async {
      return _jsonFixture('multi_part_video.json');
    });

    expect(
      () => provider.resolve(
        Uri.parse('https://www.bilibili.com/video/BV1yy411c7mE?p=99'),
      ),
      throwsA(isA<BilibiliNotFoundException>()),
    );
  });
}
