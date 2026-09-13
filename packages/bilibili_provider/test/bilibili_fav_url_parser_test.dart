import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

void main() {
  const parser = BilibiliFavListUrlParser();

  group('BilibiliFavListUrlParser.parse', () {
    test('parses the canonical create-type favlist link', () {
      final ref = parser.parse(
        Uri.parse(
          'https://space.bilibili.com/100000001/favlist'
          '?fid=200000001&ftype=create',
        ),
      );

      expect(ref.mid, 100000001);
      expect(ref.mediaId, 200000001);
      expect(ref.type, BilibiliFavListType.created);
    });

    test('defaults ftype to create when the parameter is absent', () {
      final ref = parser.parse(
        Uri.parse('https://space.bilibili.com/100000001/favlist?fid=42'),
      );

      expect(ref.type, BilibiliFavListType.created);
      expect(ref.mediaId, 42);
    });

    test('parses ftype=collect', () {
      final ref = parser.parse(
        Uri.parse(
          'https://space.bilibili.com/100000001/favlist'
          '?fid=99&ftype=collect',
        ),
      );

      expect(ref.type, BilibiliFavListType.collected);
    });

    test('parses a legacy hash route that carries the query', () {
      final ref = parser.parse(
        Uri.parse(
          'https://space.bilibili.com/100000001/favlist'
          '#/default?fid=7&ftype=collect',
        ),
      );

      expect(ref.mediaId, 7);
      expect(ref.type, BilibiliFavListType.collected);
    });

    test('tolerates unrelated and trailing query parameters', () {
      final ref = parser.parse(
        Uri.parse(
          'https://space.bilibili.com/100000001/favlist'
          '?tid=0&fid=200000001&ftype=create&keyword=',
        ),
      );

      expect(ref.mediaId, 200000001);
    });

    test('ignores the trailing slash and extra empty path segments', () {
      final ref = parser.parse(
        Uri.parse('https://space.bilibili.com/100000001/favlist/?fid=5'),
      );

      expect(ref.mediaId, 5);
    });

    test('rejects a video URL', () {
      expect(
        () => parser.parse(
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
        ),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
    });

    test('rejects a favlist link without a fid', () {
      expect(
        () => parser.parse(
          Uri.parse('https://space.bilibili.com/100000001/favlist'),
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('rejects a non-numeric mid', () {
      expect(
        () => parser.parse(
          Uri.parse('https://space.bilibili.com/not-a-mid/favlist?fid=5'),
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('rejects a non-positive fid', () {
      expect(
        () => parser.parse(
          Uri.parse('https://space.bilibili.com/100000001/favlist?fid=0'),
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('rejects an unsupported ftype', () {
      expect(
        () => parser.parse(
          Uri.parse(
            'https://space.bilibili.com/100000001/favlist'
            '?fid=5&ftype=unknown',
          ),
        ),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
    });

    test('rejects a foreign host and a non-http scheme', () {
      expect(
        () => parser.parse(Uri.parse('https://evil.example/1/favlist?fid=5')),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
      expect(
        () =>
            parser.parse(Uri.parse('ftp://space.bilibili.com/1/favlist?fid=5')),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
    });

    test('canHandle mirrors parse', () {
      expect(
        parser.canHandle(
          Uri.parse('https://space.bilibili.com/100000001/favlist?fid=5'),
        ),
        isTrue,
      );
      expect(
        parser.canHandle(
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
        ),
        isFalse,
      );
    });

    test('buildUri round-trips a parsed reference', () {
      final ref = parser.parse(
        Uri.parse(
          'https://space.bilibili.com/100000001/favlist'
          '?fid=200000001&ftype=collect',
        ),
      );

      final rebuilt = parser.parse(parser.buildUri(ref));

      expect(rebuilt.mid, ref.mid);
      expect(rebuilt.mediaId, ref.mediaId);
      expect(rebuilt.type, ref.type);
    });
  });

  group('video parser separation', () {
    test('BilibiliUrlParser keeps rejecting favlist links', () {
      const videoParser = BilibiliUrlParser();

      expect(
        videoParser.canHandle(
          Uri.parse(
            'https://space.bilibili.com/100000001/favlist'
            '?fid=200000001&ftype=create',
          ),
        ),
        isFalse,
      );
      expect(
        () => videoParser.parse(
          Uri.parse('https://space.bilibili.com/100000001/favlist?fid=1'),
        ),
        throwsA(isA<BilibiliUnsupportedContentException>()),
      );
    });

    test('BilibiliProvider.canHandle stays a video-only contract', () {
      final provider = BilibiliProvider.anonymous();

      expect(
        provider.canHandle(
          Uri.parse('https://space.bilibili.com/100000001/favlist?fid=1'),
        ),
        isFalse,
      );
    });
  });
}
