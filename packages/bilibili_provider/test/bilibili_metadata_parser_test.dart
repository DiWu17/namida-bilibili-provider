import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

String _fixture(String name) {
  return File('test/fixtures/$name').readAsStringSync();
}

void main() {
  const parser = BilibiliMetadataParser();

  group('BilibiliMetadataParser.parseVideoInfoResponse', () {
    test('parses a single-part video fixture', () {
      final info = parser.parseVideoInfoResponse(_fixture('video_info.json'));

      expect(info.bvid, 'BV1xx411c7mD');
      expect(info.aid, 170001);
      expect(info.title, 'Example Public Bilibili Video');
      expect(info.description, contains('offline metadata'));
      expect(info.thumbnail, isNotNull);
      expect(info.thumbnail!.host, 'i0.hdslb.com');
      expect(info.duration, const Duration(seconds: 212));
      expect(info.owner?.mid, 123456);
      expect(info.owner?.name, 'Example UP');
      expect(info.parts, hasLength(1));
      expect(info.parts.single.cid, '987654321');
      expect(info.parts.single.page, 1);
    });

    test('parses a multi-part video fixture and sorts parts by page', () {
      final info = parser.parseVideoInfoResponse(
        _fixture('multi_part_video.json'),
      );

      expect(info.bvid, 'BV1yy411c7mE');
      expect(info.parts, hasLength(3));
      expect(
        info.parts.map((part) => part.page).toList(),
        orderedEquals(<int>[1, 2, 3]),
      );
      expect(info.parts[1].cid, '222222222');
      expect(info.parts[1].title, 'P2 - Main Topic');
      expect(info.parts[1].duration, const Duration(seconds: 130));
    });

    test('tolerates missing optional fields and stringly typed values', () {
      final info = parser.parseVideoInfoResponse(
        _fixture('video_info_missing_optional.json'),
      );

      expect(info.bvid, 'BV1zz411c7mF');
      expect(info.aid, 170003);
      expect(info.title, 'Minimal Metadata Fixture');
      expect(info.description, isNull);
      expect(info.thumbnail, isNull);
      expect(info.duration, isNull);
      expect(info.owner, isNull);
      expect(info.parts, hasLength(1));
      expect(info.parts.single.cid, '444444444');
      expect(info.parts.single.page, 1);
    });

    test('throws a structured parse error for invalid JSON', () {
      expect(
        () => parser.parseVideoInfoResponse('{not-json'),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('maps non-zero API code to BilibiliNotFoundException', () {
      expect(
        () => parser.parseVideoInfoResponse(_fixture('api_not_found.json')),
        throwsA(isA<BilibiliNotFoundException>()),
      );
    });

    test('maps access-denied API code to BilibiliAccessDeniedException', () {
      expect(
        () => parser.parseVideoInfoResponse(_fixture('api_access_denied.json')),
        throwsA(isA<BilibiliAccessDeniedException>()),
      );
    });
  });

  group('BilibiliMetadataParser.toOnlineMedia', () {
    test('maps internal metadata to provider-neutral OnlineMedia', () {
      final info = parser.parseVideoInfoResponse(_fixture('video_info.json'));
      final media = parser.toOnlineMedia(info);

      expect(media.id.provider, 'bilibili');
      expect(media.id.id, 'BV1xx411c7mD');
      expect(media.id.subId, '987654321');
      expect(media.title, 'Example Public Bilibili Video');
      expect(media.artist, 'Example UP');
      expect(media.thumbnail, isNotNull);
      expect(media.duration, const Duration(seconds: 212));
      expect(media.parts, hasLength(1));
      expect(media.parts.single.id, '987654321');
      expect(media.parts.single.index, 0);
      expect(media.extra['aid'], 170001);
    });

    test('selects a 1-based page and stores its CID as subId', () {
      final info = parser.parseVideoInfoResponse(
        _fixture('multi_part_video.json'),
      );
      final media = parser.toOnlineMedia(info, selectedPage: 2);

      expect(media.id.id, 'BV1yy411c7mE');
      expect(media.id.subId, '222222222');
      expect(media.parts[1].index, 1);
      expect(media.parts[1].title, 'P2 - Main Topic');
    });

    test('throws when the requested page does not exist', () {
      final info = parser.parseVideoInfoResponse(
        _fixture('multi_part_video.json'),
      );

      expect(
        () => parser.toOnlineMedia(info, selectedPage: 99),
        throwsA(isA<BilibiliNotFoundException>()),
      );
    });
  });
}
