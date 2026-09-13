import 'package:online_media_provider/online_media_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OnlineMediaId', () {
    test('compares all provider-neutral fields', () {
      const a = OnlineMediaId(
        provider: 'bilibili',
        id: 'BV1xx411c7mD',
        subId: '123',
      );
      const b = OnlineMediaId(
        provider: 'bilibili',
        id: 'BV1xx411c7mD',
        subId: '123',
      );
      const c = OnlineMediaId(
        provider: 'bilibili',
        id: 'BV1xx411c7mD',
        subId: '456',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('BV1xx411c7mD'));
      expect(a.toString(), contains('123'));
    });
  });

  group('OnlineMedia', () {
    test('selects a part by subId and by default', () {
      final media = OnlineMedia(
        id: const OnlineMediaId(provider: 'bilibili', id: 'BV1'),
        title: 'Example',
        parts: const [
          OnlineMediaPart(id: 'cid-1', title: 'P1', index: 0),
          OnlineMediaPart(id: 'cid-2', title: 'P2', index: 1),
        ],
      );

      expect(media.partForSubId('cid-2')?.title, 'P2');
      expect(media.partForSubId(null)?.id, 'cid-1');
      expect(media.partForSubId('missing'), isNull);
    });

    test('defensively copies parts and extra metadata', () {
      final parts = <OnlineMediaPart>[
        const OnlineMediaPart(id: 'cid-1', title: 'P1', index: 0),
      ];
      final extra = <String, Object?>{'key': 'value'};
      final media = OnlineMedia(
        id: const OnlineMediaId(provider: 'bilibili', id: 'BV1'),
        title: 'Example',
        parts: parts,
        extra: extra,
      );

      parts.clear();
      extra['key'] = 'changed';

      expect(media.parts, hasLength(1));
      expect(media.extra['key'], 'value');
    });
  });

  group('OnlineCodecFamily', () {
    test('maps raw codec strings without discarding raw value', () {
      final stream = OnlineVideoStream(
        id: 'video-1',
        url: Uri.parse('https://example.invalid/video.m4s'),
        mimeType: 'video/mp4',
        codec: 'avc1.640028',
        backupUrls: const [],
        headers: const {'Referer': 'https://www.bilibili.com/'},
      );

      expect(stream.codec, 'avc1.640028');
      expect(stream.rawCodec, 'avc1.640028');
      expect(stream.codecFamily, OnlineCodecFamily.avc);
      expect(stream.headers, hasLength(1));
      expect(stream.backupUrls, isEmpty);
    });

    test('parses common families', () {
      expect(OnlineCodecFamily.fromCodec('avc1.4d401f'), OnlineCodecFamily.avc);
      expect(
        OnlineCodecFamily.fromCodec('hev1.1.6.L93'),
        OnlineCodecFamily.hevc,
      );
      expect(OnlineCodecFamily.fromCodec('av01.0.08M'), OnlineCodecFamily.av1);
      expect(OnlineCodecFamily.fromCodec('mp4a.40.2'), OnlineCodecFamily.aac);
      expect(OnlineCodecFamily.fromCodec('opus'), OnlineCodecFamily.opus);
      expect(OnlineCodecFamily.fromCodec('unknown'), OnlineCodecFamily.unknown);
      expect(OnlineCodecFamily.fromCodec(null), OnlineCodecFamily.unknown);
    });
  });

  group('OnlinePlaybackData', () {
    test('reports whether playback streams exist', () {
      final media = OnlineMedia(
        id: const OnlineMediaId(provider: 'bilibili', id: 'BV1'),
        title: 'Example',
      );
      final audio = OnlineAudioStream(
        id: 'audio-1',
        url: Uri.parse('https://example.invalid/audio.m4s'),
        mimeType: 'audio/mp4',
        codec: 'mp4a.40.2',
      );
      final playback = OnlinePlaybackData(media: media, audioStreams: [audio]);

      expect(playback.hasStreams, isTrue);
      expect(playback.audioStreams, hasLength(1));
      expect(playback.toString(), contains('audio=1'));
    });
  });

  test('stream expiry helper does not guess an expiry when null', () {
    final stream = OnlineAudioStream(
      id: 'audio-1',
      url: Uri.parse('https://example.invalid/audio.m4s'),
      mimeType: 'audio/mp4',
    );
    expect(stream.expiresAt, isNull);
    expect(stream.isExpired, isFalse);
  });
}
