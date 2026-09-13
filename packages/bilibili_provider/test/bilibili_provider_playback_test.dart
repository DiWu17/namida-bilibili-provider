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

BilibiliProvider _providerWith(BilibiliFixtureHandler handler) {
  return BilibiliProvider(
    client: BilibiliClient(httpClient: MockClient(handler)),
  );
}

typedef BilibiliFixtureHandler =
    Future<http.Response> Function(http.Request request);

void main() {
  test('getPlayback maps DASH streams to OnlinePlaybackData', () async {
    final provider = _providerWith((request) async {
      if (request.url.path == '/x/web-interface/view') {
        return _jsonFixture('video_info.json');
      }
      if (request.url.path == '/x/player/playurl') {
        expect(request.url.queryParameters['bvid'], 'BV1xx411c7mD');
        expect(request.url.queryParameters['cid'], '987654321');
        return _jsonFixture('dash_playurl.json');
      }
      return http.Response('', 404);
    });

    final media = await provider.resolve(
      Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
    );
    final playback = await provider.getPlayback(media.id);

    expect(playback.media.id.id, 'BV1xx411c7mD');
    expect(playback.videoStreams, hasLength(2));
    expect(playback.audioStreams, hasLength(2));
    expect(playback.muxedStreams, isEmpty);
    expect(playback.expiresAt?.year, 2030);

    final video = playback.videoStreams.first;
    expect(video.qualityId, 80);
    expect(video.qualityLabel, '1080P 高清');
    expect(video.rawCodec, 'avc1.640028');
    expect(video.codecFamily, OnlineCodecFamily.avc);
    expect(video.width, 1920);
    expect(video.height, 1080);
    expect(video.fps, 30);
    expect(video.headers['Referer'], 'https://www.bilibili.com/');
    expect(video.backupUrls, hasLength(1));

    final audio = playback.audioStreams.first;
    expect(audio.qualityLabel, '192K');
    expect(audio.codecFamily, OnlineCodecFamily.aac);
  });

  test('getPlayback can fetch metadata when resolve was not called', () async {
    final provider = _providerWith((request) async {
      if (request.url.path == '/x/web-interface/view') {
        return _jsonFixture('video_info.json');
      }
      return _jsonFixture('dash_playurl.json');
    });

    final playback = await provider.getPlayback(
      const OnlineMediaId(
        provider: 'bilibili',
        id: 'BV1xx411c7mD',
        subId: '987654321',
      ),
    );

    expect(playback.media.title, 'Example Public Bilibili Video');
    expect(playback.videoStreams, hasLength(2));
  });

  test('getPlayback rejects a CID that is not in the video metadata', () async {
    final provider = _providerWith((request) async {
      return _jsonFixture('video_info.json');
    });

    expect(
      () => provider.getPlayback(
        const OnlineMediaId(
          provider: 'bilibili',
          id: 'BV1xx411c7mD',
          subId: '000000000',
        ),
      ),
      throwsA(isA<BilibiliNotFoundException>()),
    );
  });

  test('muxed fallback requires explicit opt-in', () async {
    final provider = _providerWith((request) async {
      if (request.url.path == '/x/web-interface/view') {
        return _jsonFixture('video_info.json');
      }
      return _jsonFixture('playurl_muxed.json');
    });

    expect(
      () => provider.getPlayback(
        const OnlineMediaId(
          provider: 'bilibili',
          id: 'BV1xx411c7mD',
          subId: '987654321',
        ),
      ),
      throwsA(isA<BilibiliUnsupportedContentException>()),
    );

    final playback = await provider.getPlayback(
      const OnlineMediaId(
        provider: 'bilibili',
        id: 'BV1xx411c7mD',
        subId: '987654321',
      ),
      options: const OnlinePlaybackOptions(allowMuxedFallback: true),
    );

    expect(playback.muxedStreams, hasLength(1));
    expect(playback.audioStreams, isEmpty);
    expect(playback.videoStreams, isEmpty);
  });
}
