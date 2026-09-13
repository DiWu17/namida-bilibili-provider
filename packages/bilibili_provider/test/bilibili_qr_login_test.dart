import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _sess = 'fixture-sessdata-secret-9f3a';
const String _csrf = 'fixture-csrf-secret-4c1b';
const String _refresh = 'fixture-refresh-token-77aa';

String _fixture(String name) {
  return File('test/fixtures/$name').readAsStringSync();
}

http.Response _jsonFixture(String name, {Map<String, String>? headers}) {
  return http.Response(
    _fixture(name),
    200,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    },
  );
}

void main() {
  const parser = BilibiliAccountParser();

  group('parseQrLoginGenerateResponse', () {
    test('returns the ticket and the QR content', () {
      final login = parser.parseQrLoginGenerateResponse(
        _fixture('qr_login_generate.json'),
      );

      expect(login.qrcodeKey, 'fixture-qrcode-key-8f21c4');
      expect(login.uri.scheme, 'https');
      expect(login.uri.host, 'account.bilibili.com');
      expect(login.uri.queryParameters['qrcode_key'], login.qrcodeKey);
    });

    test(
      'redacts the ticket, because the QR content is a login credential',
      () {
        final login = parser.parseQrLoginGenerateResponse(
          _fixture('qr_login_generate.json'),
        );

        expect(login.toString(), 'BilibiliQrLogin(<redacted>)');
        expect(login.toString(), isNot(contains('8f21c4')));
      },
    );

    test('throws when the key or URL is missing', () {
      expect(
        () => parser.parseQrLoginGenerateResponse(
          '{"code":0,"message":"OK","data":{"url":"https://x.example/y"}}',
        ),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(
        () => parser.parseQrLoginGenerateResponse(
          '{"code":0,"message":"OK","data":{"qrcode_key":"k"}}',
        ),
        throwsA(isA<BilibiliParseException>()),
      );
    });

    test('maps a platform failure through the envelope', () {
      expect(
        () => parser.parseQrLoginGenerateResponse(
          '{"code":-412,"message":"request blocked"}',
        ),
        throwsA(isA<BilibiliApiException>()),
      );
    });
  });

  group('parseQrLoginPollResponse stages', () {
    test('maps 86101 to pending', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_pending.json'),
      );

      expect(status.stage, BilibiliQrLoginStage.pending);
      expect(status.isTerminal, isFalse);
      expect(status.cookies, isNull);
      expect(status.message, '未扫码');
    });

    test('maps 86090 to scanned', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_scanned.json'),
      );

      expect(status.stage, BilibiliQrLoginStage.scanned);
      expect(status.isTerminal, isFalse);
    });

    test('maps 86038 to expired', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_expired.json'),
      );

      expect(status.stage, BilibiliQrLoginStage.expired);
      expect(status.isTerminal, isTrue);
    });

    test('maps an unknown state to failed', () {
      final status = parser.parseQrLoginPollResponse(
        '{"code":0,"message":"0","data":{"code":-1,"message":"unknown"}}',
      );

      expect(status.stage, BilibiliQrLoginStage.failed);
      expect(status.message, 'unknown');
    });

    test('maps a non-zero envelope code to failed', () {
      final status = parser.parseQrLoginPollResponse(
        '{"code":-352,"message":"risk control"}',
      );

      expect(status.stage, BilibiliQrLoginStage.failed);
      expect(status.message, 'risk control');
    });
  });

  group('parseQrLoginPollResponse cookies', () {
    test('extracts the session from the cross-domain URL', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_confirmed.json'),
      );

      expect(status.stage, BilibiliQrLoginStage.confirmed);
      expect(status.isConfirmed, isTrue);

      final cookies = status.cookies!;
      expect(cookies.sessData, _sess);
      expect(cookies.csrfToken, _csrf);
      expect(cookies.userId, 100000001);
      expect(cookies['DedeUserID__ckMd5'], 'fixture-check-md5');
      expect(
        cookies.values.containsKey('gourl'),
        isFalse,
        reason: 'redirect parameters must not become cookies',
      );
      expect(status.refreshToken, _refresh);
    });

    test('extracts the session from Set-Cookie headers', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_confirmed_headers_only.json'),
        setCookieHeaders: const <String>[
          'SESSDATA=$_sess; Path=/; Domain=.bilibili.com; HttpOnly',
          'bili_jct=$_csrf; Path=/',
          'DedeUserID=100000001; Path=/',
        ],
      );

      expect(status.stage, BilibiliQrLoginStage.confirmed);
      expect(status.cookies?.sessData, _sess);
      expect(status.cookies?.csrfToken, _csrf);
      expect(status.cookies?.userId, 100000001);
    });

    test('merges both sources, letting the URL fill in missing names', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_confirmed.json'),
        setCookieHeaders: const <String>[
          'SESSDATA=header-wins; Path=/',
          'buvid3=fixture-device; Path=/',
        ],
      );

      expect(status.cookies?.sessData, 'header-wins');
      expect(status.cookies?.csrfToken, _csrf, reason: 'filled from the URL');
      expect(status.cookies?['buvid3'], 'fixture-device');
    });

    test('fails when confirmation carries no usable session cookie', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_confirmed_headers_only.json'),
      );

      expect(status.stage, BilibiliQrLoginStage.failed);
      expect(status.message, contains('no usable session cookie'));
      expect(status.cookies, isNull);
    });

    test('redacts cookies and the refresh token in toString', () {
      final status = parser.parseQrLoginPollResponse(
        _fixture('qr_login_poll_confirmed.json'),
      );

      final text = status.toString();

      expect(text, contains('confirmed'));
      expect(text, isNot(contains(_sess)));
      expect(text, isNot(contains(_csrf)));
      expect(text, isNot(contains(_refresh)));
    });

    test('flags a confirmed session that cannot perform writes', () {
      final status = parser.parseQrLoginPollResponse(
        '{"code":0,"message":"0","data":{"code":0,"url":'
        '"https://passport.biligame.com/crossDomain?SESSDATA=$_sess"}}',
      );

      expect(status.isConfirmed, isTrue);
      expect(status.toString(), contains('no csrf token'));
    });
  });

  group('BilibiliAccountClient QR endpoints', () {
    test('generate requests the passport host and parses the ticket', () async {
      final client = BilibiliAccountClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.host, 'passport.bilibili.com');
          expect(request.url.path, '/x/passport-login/web/qrcode/generate');
          return _jsonFixture('qr_login_generate.json');
        }),
      );

      final login = await client.generateQrLogin();

      expect(login.qrcodeKey, 'fixture-qrcode-key-8f21c4');
    });

    test('poll sends the key and reads Set-Cookie', () async {
      final client = BilibiliAccountClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/x/passport-login/web/qrcode/poll');
          expect(request.url.queryParameters['qrcode_key'], 'fixture-key');
          return _jsonFixture(
            'qr_login_poll_confirmed_headers_only.json',
            headers: <String, String>{
              'set-cookie':
                  'SESSDATA=$_sess; Path=/; HttpOnly, '
                  'bili_jct=$_csrf; Path=/',
            },
          );
        }),
      );

      final status = await client.pollQrLogin(
        BilibiliQrLogin(
          qrcodeKey: 'fixture-key',
          uri: Uri.parse('https://account.bilibili.com/x'),
        ),
      );

      expect(status.isConfirmed, isTrue);
      expect(status.cookies?.sessData, _sess);
      expect(status.cookies?.csrfToken, _csrf);
    });

    test('poll rejects an empty key before any request', () async {
      var requests = 0;
      final client = BilibiliAccountClient(
        httpClient: MockClient((request) async {
          requests++;
          return _jsonFixture('qr_login_poll_pending.json');
        }),
      );

      await expectLater(
        () => client.pollQrLogin(
          BilibiliQrLogin(
            qrcodeKey: '',
            uri: Uri.parse('https://account.bilibili.com/x'),
          ),
        ),
        throwsA(isA<BilibiliParseException>()),
      );
      expect(requests, 0);
    });
  });

  group('BilibiliAccountManager.signInWithQrCode', () {
    /// Serves a scripted sequence of poll responses.
    BilibiliAccountManager managerWith(
      List<String> pollFixtures, {
      Map<String, String>? pollHeaders,
    }) {
      var pollIndex = 0;
      final auth = BilibiliAccountAuthProvider();
      return BilibiliAccountManager(
        authProvider: auth,
        client: BilibiliAccountClient(
          auth: auth,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/qrcode/generate')) {
              return _jsonFixture('qr_login_generate.json');
            }
            if (request.url.path.endsWith('/qrcode/poll')) {
              final fixture =
                  pollFixtures[pollIndex < pollFixtures.length
                      ? pollIndex
                      : pollFixtures.length - 1];
              pollIndex++;
              return _jsonFixture(fixture, headers: pollHeaders);
            }
            if (request.url.path == '/x/web-interface/nav') {
              return _jsonFixture('nav_logged_in.json');
            }
            throw StateError('unexpected request ${request.url.path}');
          }),
        ),
      );
    }

    test(
      'drives pending -> scanned -> confirmed and adopts the account',
      () async {
        final manager = managerWith(<String>[
          'qr_login_poll_pending.json',
          'qr_login_poll_scanned.json',
          'qr_login_poll_confirmed.json',
        ]);
        final seen = <BilibiliQrLoginStage>[];

        final session = await manager.signInWithQrCode(
          pollInterval: const Duration(milliseconds: 1),
          timeout: const Duration(seconds: 5),
          onProgress: (status) => seen.add(status.stage),
        );

        expect(seen, <BilibiliQrLoginStage>[
          BilibiliQrLoginStage.pending,
          BilibiliQrLoginStage.pending,
          BilibiliQrLoginStage.scanned,
          BilibiliQrLoginStage.confirmed,
        ]);
        expect(session?.accountId, '100000001');
        expect(session?.name, 'Example Account');
        expect(manager.isAnonymous, isFalse);
        expect(manager.cookieValidity.isAuthenticated, isTrue);
        expect(manager.authProvider.cookieHeader, contains('SESSDATA=$_sess'));

        await manager.dispose();
      },
    );

    test('returns null when the ticket expires', () async {
      final manager = managerWith(<String>['qr_login_poll_expired.json']);
      final seen = <BilibiliQrLoginStage>[];

      final session = await manager.signInWithQrCode(
        pollInterval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
        onProgress: (status) => seen.add(status.stage),
      );

      expect(session, isNull);
      expect(seen.last, BilibiliQrLoginStage.expired);
      expect(manager.isAnonymous, isTrue);

      await manager.dispose();
    });

    test('returns null when the caller cancels', () async {
      final manager = managerWith(<String>['qr_login_poll_pending.json']);
      var cancelled = false;

      final session = await manager.signInWithQrCode(
        pollInterval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
        isCancelled: () => cancelled,
        onProgress: (status) {
          if (status.stage == BilibiliQrLoginStage.pending) {
            cancelled = true;
          }
        },
      );

      expect(session, isNull);
      expect(manager.isAnonymous, isTrue);

      await manager.dispose();
    });

    test('gives up after the timeout and reports it', () async {
      final manager = managerWith(<String>['qr_login_poll_pending.json']);
      final seen = <BilibiliQrLoginStatus>[];

      final session = await manager.signInWithQrCode(
        pollInterval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 20),
        onProgress: seen.add,
      );

      expect(session, isNull);
      expect(seen.first.stage, BilibiliQrLoginStage.pending);
      expect(seen.last.stage, BilibiliQrLoginStage.expired);
      expect(seen.last.message, contains('timed out'));

      await manager.dispose();
    });

    test('reports a confirmation without cookies as a failure', () async {
      final manager = managerWith(<String>[
        'qr_login_poll_confirmed_headers_only.json',
      ]);
      final seen = <BilibiliQrLoginStatus>[];

      final session = await manager.signInWithQrCode(
        pollInterval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
        onProgress: seen.add,
      );

      expect(session, isNull);
      expect(seen.last.stage, BilibiliQrLoginStage.failed);
      expect(seen.last.message, contains('no usable session cookie'));
      expect(manager.isAnonymous, isTrue);

      await manager.dispose();
    });

    test('validates the delivered cookies through nav', () async {
      var navRequests = 0;
      final auth = BilibiliAccountAuthProvider();
      final manager = BilibiliAccountManager(
        authProvider: auth,
        client: BilibiliAccountClient(
          auth: auth,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/qrcode/generate')) {
              return _jsonFixture('qr_login_generate.json');
            }
            if (request.url.path.endsWith('/qrcode/poll')) {
              return _jsonFixture('qr_login_poll_confirmed.json');
            }
            navRequests++;
            expect(request.headers['Cookie'], contains('SESSDATA=$_sess'));
            return _jsonFixture('nav_logged_in.json');
          }),
        ),
      );

      await manager.signInWithQrCode(
        pollInterval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      );

      expect(navRequests, 1, reason: 'the QR session is validated once');
      await manager.dispose();
    });

    test('rejects invalid polling parameters', () async {
      final manager = BilibiliAccountManager(
        client: BilibiliAccountClient(
          httpClient: MockClient(
            (request) async => throw StateError('no request expected'),
          ),
        ),
      );

      await expectLater(
        () => manager.signInWithQrCode(pollInterval: Duration.zero),
        throwsA(isA<BilibiliParseException>()),
      );
      await expectLater(
        () => manager.signInWithQrCode(timeout: Duration.zero),
        throwsA(isA<BilibiliParseException>()),
      );

      await manager.dispose();
    });
  });
}
