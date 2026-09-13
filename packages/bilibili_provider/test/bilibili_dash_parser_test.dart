import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:online_media_provider/online_media_provider.dart';
import 'package:test/test.dart';

String _fixture(String name) {
  return File('test/fixtures/$name').readAsStringSync();
}

OnlineMedia _media() {
  return OnlineMedia(
    id: const OnlineMediaId(
      provider: 'bilibili',
      id: 'BV1xx411c7mD',
      subId: '987654321',
    ),
    title: 'Example Public Bilibili Video',
  );
}

void main() {
  const parser = BilibiliDashParser();

  group('BilibiliDashParser.parsePlaybackResponse', () {
    test('parses DASH video and audio streams', () {
      final response = parser.parsePlaybackResponse(
        _fixture('dash_playurl.json'),
        headers: const <String, String>{'Referer': 'https://www.bilibili.com/'},
      );

      expect(response.duration, const Duration(seconds: 212));
      expect(response.videoStreams, hasLength(2));
      expect(response.audioStreams, hasLength(2));
      expect(response.muxedStreams, isEmpty);

      final video = response.videoStreams.first;
      expect(video.qualityId, 80);
      expect(video.qualityLabel, '1080P 高清');
      expect(video.width, 1920);
      expect(video.height, 1080);
      expect(video.fps, 30);
      expect(video.codec, 'avc1.640028');
      expect(video.bitrate, 2000000);
      expect(video.backupUrls, hasLength(1));
      expect(video.expiresAt?.year, 2030);

      final secondVideo = response.videoStreams[1];
      expect(secondVideo.qualityId, 64);
      expect(secondVideo.codec, 'hev1.1.6.L120');
      expect(secondVideo.fps, closeTo(29.97002997, 0.000001));

      final audio = response.audioStreams.first;
      expect(audio.qualityId, 30280);
      expect(audio.qualityLabel, '192K');
      expect(audio.codec, 'mp4a.40.2');
      expect(audio.bitrate, 192000);
      expect(audio.backupUrls, hasLength(1));
      expect(audio.expiresAt, isNotNull);

      expect(response.headers['Referer'], 'https://www.bilibili.com/');
      expect(response.expiresAt?.year, 2030);
    });

    test('tolerates missing optional DASH fields', () {
      final response = parser.parsePlaybackResponse(
        _fixture('dash_playurl_minimal.json'),
      );

      expect(response.duration, const Duration(seconds: 90));
      expect(response.videoStreams, hasLength(1));
      expect(response.audioStreams, isEmpty);

      final video = response.videoStreams.single;
      expect(video.qualityId, 32);
      expect(video.qualityLabel, '480P');
      expect(video.width, isNull);
      expect(video.height, isNull);
      expect(video.fps, isNull);
      expect(video.mimeType, 'video/mp4');
      expect(video.expiresAt, isNull);
    });

    test('parses muxed fallback durl data', () {
      final response = parser.parsePlaybackResponse(
        _fixture('playurl_muxed.json'),
      );

      expect(response.videoStreams, isEmpty);
      expect(response.audioStreams, isEmpty);
      expect(response.muxedStreams, hasLength(1));

      final muxed = response.muxedStreams.single;
      expect(muxed.qualityId, 32);
      expect(muxed.qualityLabel, '480P 清晰');
      expect(muxed.sizeInBytes, 5120000);
      expect(muxed.duration, const Duration(seconds: 100));
      expect(muxed.backupUrls, hasLength(1));
      expect(muxed.expiresAt?.year, 2030);
    });
  });

  group('BilibiliDashParser.toOnlinePlaybackData', () {
    test('maps separate DASH streams and preserves headers/backups', () {
      final response = parser.parsePlaybackResponse(
        _fixture('dash_playurl.json'),
        headers: const <String, String>{
          'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'fixture-agent',
        },
      );

      final playback = parser.toOnlinePlaybackData(response, _media());

      expect(playback.media.id.provider, 'bilibili');
      expect(playback.videoStreams, hasLength(2));
      expect(playback.audioStreams, hasLength(2));
      expect(playback.muxedStreams, isEmpty);
      expect(playback.expiresAt?.year, 2030);

      final video = playback.videoStreams.first;
      expect(video.id, 'video_80');
      expect(video.qualityLabel, '1080P 高清');
      expect(video.width, 1920);
      expect(video.height, 1080);
      expect(video.fps, 30);
      expect(video.rawCodec, 'avc1.640028');
      expect(video.codecFamily, OnlineCodecFamily.avc);
      expect(video.headers['Referer'], 'https://www.bilibili.com/');
      expect(video.headers['User-Agent'], 'fixture-agent');
      expect(video.backupUrls, hasLength(1));
      expect(video.duration, const Duration(seconds: 212));

      final audio = playback.audioStreams.first;
      expect(audio.id, 'audio_30280');
      expect(audio.rawCodec, 'mp4a.40.2');
      expect(audio.codecFamily, OnlineCodecFamily.aac);
      expect(audio.bitrate, 192000);
    });

    test('maps muxed streams with duration and size', () {
      final response = parser.parsePlaybackResponse(
        _fixture('playurl_muxed.json'),
      );
      final playback = parser.toOnlinePlaybackData(response, _media());

      expect(playback.muxedStreams, hasLength(1));
      final muxed = playback.muxedStreams.single;
      expect(muxed.qualityId, 32);
      expect(muxed.sizeInBytes, 5120000);
      expect(muxed.duration, const Duration(seconds: 100));
      expect(muxed.backupUrls, hasLength(1));
    });
  });
}
