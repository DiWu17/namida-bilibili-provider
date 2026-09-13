import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

void main() {
  group('parseFrameRate', () {
    test('parses integer values', () {
      expect(parseFrameRate('60'), 60);
      expect(parseFrameRate('30'), 30);
      expect(parseFrameRate(' 24 '), 24);
    });

    test('parses rational values', () {
      expect(parseFrameRate('30000/1001'), closeTo(29.97002997, 0.000001));
      expect(parseFrameRate('24000/1001'), closeTo(23.97602398, 0.000001));
    });

    test('returns null for invalid values', () {
      expect(parseFrameRate(null), isNull);
      expect(parseFrameRate(''), isNull);
      expect(parseFrameRate('   '), isNull);
      expect(parseFrameRate('abc'), isNull);
      expect(parseFrameRate('30000/'), isNull);
      expect(parseFrameRate('30000/0'), isNull);
      expect(parseFrameRate('-1'), isNull);
    });
  });
}
