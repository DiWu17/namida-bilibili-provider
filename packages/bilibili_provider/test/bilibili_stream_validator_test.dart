import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_media_provider/online_media_provider.dart';
import 'package:test/test.dart';

OnlineVideoStream _stream({Map<String, String>? headers}) {
  return OnlineVideoStream(
    id: 'video_80',
    url: Uri.parse('https://cdn.example.invalid/video.m4s'),
    mimeType: 'video/mp4',
    codec: 'avc1.640028',
    headers:
        headers ??
        const <String, String>{
          'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'fixture-agent',
        },
  );
}

void main() {
  group('BilibiliStreamValidator', () {
    test('accepts HTTP 206 and requests the configured byte range', () async {
      http.Request? capturedRequest;
      final validator = BilibiliStreamValidator(
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response.bytes(
            const <int>[1, 2, 3, 4, 5, 6, 7, 8],
            206,
            headers: const <String, String>{
              'content-type': 'video/mp4',
              'content-range': 'bytes 0-7/1024000',
            },
          );
        }),
      );

      final result = await validator.validate(_stream(), maxBytes: 8);

      expect(capturedRequest?.headers['Range'], 'bytes=0-7');
      expect(capturedRequest?.headers['Referer'], 'https://www.bilibili.com/');
      expect(capturedRequest?.headers['User-Agent'], 'fixture-agent');
      expect(result.isPlayable, isTrue);
      expect(result.statusCode, 206);
      expect(result.bytesRead, 8);
      expect(result.rangeSupported, isTrue);
      expect(result.reason, isNull);
    });

    test('accepts a limited HTTP 200 fallback when range is ignored', () async {
      final validator = BilibiliStreamValidator(
        httpClient: MockClient((request) async {
          return http.Response.bytes(
            List<int>.generate(100, (index) => index),
            200,
            headers: const <String, String>{'content-type': 'video/mp4'},
          );
        }),
      );

      final result = await validator.validate(_stream(), maxBytes: 10);

      expect(result.isPlayable, isTrue);
      expect(result.statusCode, 200);
      expect(result.bytesRead, 10);
      expect(result.rangeSupported, isFalse);
    });

    test(
      'retries without Range after HTTP 416 and accepts the fallback',
      () async {
        var attempt = 0;
        final validator = BilibiliStreamValidator(
          httpClient: MockClient((request) async {
            attempt++;
            if (attempt == 1) {
              expect(request.headers['Range'], 'bytes=0-9');
              return http.Response('', 416);
            }
            expect(request.headers['Range'], isNull);
            return http.Response.bytes(
              const <int>[1, 2, 3, 4],
              200,
              headers: const <String, String>{'content-type': 'video/mp4'},
            );
          }),
        );

        final result = await validator.validate(_stream(), maxBytes: 10);

        expect(attempt, 2);
        expect(result.isPlayable, isTrue);
        expect(result.statusCode, 200);
        expect(result.bytesRead, 4);
        expect(result.rangeSupported, isFalse);
      },
    );

    test('rejects empty media bodies', () async {
      final validator = BilibiliStreamValidator(
        httpClient: MockClient((request) async {
          return http.Response('', 200);
        }),
      );

      final result = await validator.validate(_stream());

      expect(result.isPlayable, isFalse);
      expect(result.statusCode, 200);
      expect(result.bytesRead, 0);
      expect(result.reason, contains('no media bytes'));
    });

    test('reports unexpected HTTP statuses without exposing URLs', () async {
      final validator = BilibiliStreamValidator(
        httpClient: MockClient((request) async {
          return http.Response('', 403);
        }),
      );

      final result = await validator.validate(_stream());

      expect(result.isPlayable, isFalse);
      expect(result.statusCode, 403);
      expect(result.reason, 'Unexpected HTTP 403 response.');
      expect(result.reason, isNot(contains('http')));
    });

    test('rejects non-positive maxBytes', () {
      final validator = BilibiliStreamValidator(
        httpClient: MockClient((request) async {
          fail('HTTP request should not be made');
        }),
      );

      expect(
        () => validator.validate(_stream(), maxBytes: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
