import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

void main() {
  const parser = BilibiliUrlParser();

  group('BilibiliUrlParser.canHandle', () {
    test('accepts canonical BV, av and b23 URLs', () {
      expect(
        parser.canHandle(
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
        ),
        isTrue,
      );
      expect(
        parser.canHandle(Uri.parse('https://www.bilibili.com/video/av170001')),
        isTrue,
      );
      expect(parser.canHandle(Uri.parse('https://b23.tv/abc123')), isTrue);
    });

    test('rejects unsupported or malformed URLs', () {
      final uris = <Uri>[
        Uri.parse('https://example.com/video/BV1xx411c7mD'),
        Uri.parse('https://www.bilibili.com/'),
        Uri.parse('https://www.bilibili.com/video/not-an-id'),
        Uri.parse('ftp://www.bilibili.com/video/BV1xx411c7mD'),
        Uri.parse('/video/BV1xx411c7mD'),
      ];

      for (final uri in uris) {
        expect(parser.canHandle(uri), isFalse, reason: uri.toString());
      }
    });
  });

  group('BilibiliUrlParser.parse', () {
    test('parses a BVID URL', () {
      final ref = parser.parse(
        Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
      );

      expect(ref.kind, BilibiliMediaIdKind.bvid);
      expect(ref.id, 'BV1xx411c7mD');
      expect(ref.page, isNull);
      expect(ref.platformVideoId, 'BV1xx411c7mD');
      expect(ref.isShortLink, isFalse);
    });

    test('parses a page parameter and preserves the original URL', () {
      final uri = Uri.parse(
        'https://www.bilibili.com/video/BV1xx411c7mD?p=2&spm_id_from=x',
      );
      final ref = parser.parse(uri);

      expect(ref.kind, BilibiliMediaIdKind.bvid);
      expect(ref.id, 'BV1xx411c7mD');
      expect(ref.page, 2);
      expect(ref.source, uri);
    });

    test('parses an av URL and strips the av prefix', () {
      final ref = parser.parse(
        Uri.parse('https://www.bilibili.com/video/AV170001?p=3'),
      );

      expect(ref.kind, BilibiliMediaIdKind.aid);
      expect(ref.id, '170001');
      expect(ref.page, 3);
      expect(ref.platformVideoId, 'av170001');
    });

    test('parses a b23.tv short-link token', () {
      final ref = parser.parse(Uri.parse('https://b23.tv/abc123?p=2'));

      expect(ref.kind, BilibiliMediaIdKind.shortLink);
      expect(ref.id, 'abc123');
      expect(ref.page, 2);
      expect(ref.isShortLink, isTrue);
    });

    test('recognizes BV/av tokens directly under b23.tv', () {
      final bvRef = parser.parse(Uri.parse('https://b23.tv/BV1xx411c7mD'));
      final avRef = parser.parse(Uri.parse('https://b23.tv/av170001'));

      expect(bvRef.kind, BilibiliMediaIdKind.bvid);
      expect(bvRef.id, 'BV1xx411c7mD');
      expect(avRef.kind, BilibiliMediaIdKind.aid);
      expect(avRef.id, '170001');
    });

    test('rejects invalid p values', () {
      expect(
        () => parser.parse(
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD?p=0'),
        ),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(
        () => parser.parse(
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD?p=abc'),
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('rejects malformed video ids', () {
      expect(
        () => parser.parse(Uri.parse('https://www.bilibili.com/video/BV123')),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(
        () => parser.parse(Uri.parse('https://www.bilibili.com/video/av')),
        throwsA(isA<BilibiliParseException>()),
      );
    });
  });
}
