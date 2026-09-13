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
  group('BilibiliClient.getPlayback', () {
    test('requests playurl with DASH flags and parses the response', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.bilibili.com');
          expect(request.url.path, '/x/player/playurl');
          expect(request.url.queryParameters['bvid'], 'BV1xx411c7mD');
          expect(request.url.queryParameters['cid'], '987654321');
          expect(request.url.queryParameters['qn'], '80');
          expect(request.url.queryParameters['fnval'], '4048');
          expect(request.url.queryParameters['fourk'], '1');
          return _jsonFixture('dash_playurl.json');
        }),
      );

      final response = await client.getPlayback(
        bvid: 'BV1xx411c7mD',
        cid: '987654321',
        qn: 80,
      );

      expect(response.videoStreams, hasLength(2));
      expect(response.audioStreams, hasLength(2));
      expect(response.videoStreams.first.qualityId, 80);
      expect(response.videoStreams.first.codec, 'avc1.640028');
      expect(response.headers['Referer'], 'https://www.bilibili.com/');
    });

    test('rejects an invalid BVID before making a request', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          fail('HTTP request should not be made');
        }),
      );

      expect(
        () => client.getPlayback(bvid: 'not-a-bvid', cid: '123'),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('rejects an invalid CID before making a request', () async {
      final client = BilibiliClient(
        httpClient: MockClient((request) async {
          fail('HTTP request should not be made');
        }),
      );

      expect(
        () => client.getPlayback(bvid: 'BV1xx411c7mD', cid: 'abc'),
        throwsA(isA<BilibiliParseException>()),
      );
    });
  });
}
