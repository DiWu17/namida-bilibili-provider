import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

/// Distinctive value that must never surface in a log-safe string.
const String _secret = 'fixture-sessdata-secret-9f3a';
const String _csrfSecret = 'fixture-csrf-secret-4c1b';

BilibiliCookies _fixtureCookies() {
  return BilibiliCookies(<String, String>{
    'SESSDATA': _secret,
    'bili_jct': _csrfSecret,
    'DedeUserID': '100000001',
    'DedeUserID__ckMd5': 'fixture-check-md5',
    'sid': 'fixture-sid',
  });
}

void main() {
  group('BilibiliCookies.parse', () {
    test('parses a Cookie header into named values', () {
      final cookies = BilibiliCookies.parse(
        'SESSDATA=$_secret; bili_jct=$_csrfSecret; DedeUserID=100000001',
      );

      expect(cookies.length, 3);
      expect(cookies.sessData, _secret);
      expect(cookies.csrfToken, _csrfSecret);
      expect(cookies.userId, 100000001);
      expect(cookies.hasSessionToken, isTrue);
      expect(cookies.hasCsrfToken, isTrue);
    });

    test('tolerates missing, blank and malformed input', () {
      expect(BilibiliCookies.parse(null).isEmpty, isTrue);
      expect(BilibiliCookies.parse('   ').isEmpty, isTrue);
      expect(BilibiliCookies.parse('; ; = ; novalue; =empty').isEmpty, isTrue);
      expect(BilibiliCookies.parse('SESSDATA=').isEmpty, isTrue);
      expect(BilibiliCookies.parse('SESSDATA').isEmpty, isTrue);
    });

    test('trims surrounding whitespace', () {
      final cookies = BilibiliCookies.parse('  SESSDATA = $_secret ;  ');

      expect(cookies.sessData, _secret);
      expect(cookies.cookieHeader, 'SESSDATA=$_secret');
    });

    test('ignores Set-Cookie attributes pasted into the header field', () {
      final cookies = BilibiliCookies.parse(
        'SESSDATA=$_secret; Path=/; Domain=.bilibili.com; '
        'Expires=Wed, 01 Jan 2025 00:00:00 GMT; HttpOnly; Secure; SameSite=None',
      );

      expect(cookies.length, 1);
      expect(cookies.sessData, _secret);
    });

    test('keeps insertion order for a deterministic Cookie header', () {
      final cookies = BilibiliCookies.parse('b=2; a=1; c=3');

      expect(cookies.cookieHeader, 'b=2; a=1; c=3');
    });

    test('fromSetCookieHeaders keeps only the first pair of each header', () {
      final cookies = BilibiliCookies.fromSetCookieHeaders(const <String>[
        'SESSDATA=$_secret; Path=/; HttpOnly',
        'bili_jct=$_csrfSecret; Path=/',
      ]);

      expect(cookies.length, 2);
      expect(cookies.sessData, _secret);
      expect(cookies.csrfToken, _csrfSecret);
    });

    test('merge, withValues and without produce new jars', () {
      final base = BilibiliCookies(<String, String>{'a': '1', 'b': '2'});

      expect(base.merge(BilibiliCookies(<String, String>{'b': '9'})).values, {
        'a': '1',
        'b': '9',
      });
      expect(base.withValues(<String, String>{'c': '3'}).length, 3);
      expect(base.without(<String>['a']).values, {'b': '2'});
      expect(base.length, 2, reason: 'the original jar must stay unchanged');
    });

    test('equality and hashCode follow the cookie set', () {
      final a = BilibiliCookies(<String, String>{'x': '1'});
      final b = BilibiliCookies(<String, String>{'x': '1'});
      final c = BilibiliCookies(<String, String>{'x': '2'});

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('reports a missing session token without one', () {
      final cookies = BilibiliCookies(<String, String>{'buvid3': 'device'});

      expect(cookies.hasSessionToken, isFalse);
      expect(cookies.hasCsrfToken, isFalse);
      expect(cookies.userId, isNull);
      expect(cookies.isEmpty, isFalse);
    });
  });

  group('BilibiliCookies.fromUserInput', () {
    test('accepts a raw Cookie header', () {
      final cookies = BilibiliCookies.fromUserInput(
        'SESSDATA=$_secret; bili_jct=$_csrfSecret; DedeUserID=100000001',
      );

      expect(cookies.sessData, _secret);
      expect(cookies.userId, 100000001);
    });

    test('strips a leading label and surrounding whitespace', () {
      final cookies = BilibiliCookies.fromUserInput(
        '  Cookie: SESSDATA=$_secret ; bili_jct=$_csrfSecret  ',
      );

      expect(cookies.length, 2);
      expect(cookies.csrfToken, _csrfSecret);
    });

    test('accepts one cookie per line', () {
      final cookies = BilibiliCookies.fromUserInput(
        'SESSDATA=$_secret\nbili_jct=$_csrfSecret\r\nDedeUserID=100000001\t',
      );

      expect(cookies.length, 3);
      expect(cookies.sessData, _secret);
      expect(cookies.csrfToken, _csrfSecret);
      expect(cookies.userId, 100000001);
    });

    test('unwraps a quoted value', () {
      expect(
        BilibiliCookies.fromUserInput('"SESSDATA=$_secret"').sessData,
        _secret,
      );
      expect(
        BilibiliCookies.fromUserInput("'SESSDATA=$_secret'").sessData,
        _secret,
      );
    });

    test('discards Set-Cookie attribute noise', () {
      final cookies = BilibiliCookies.fromUserInput(
        'SESSDATA=$_secret; Path=/; Domain=.bilibili.com; HttpOnly; Secure',
      );

      expect(cookies.length, 1);
      expect(cookies.sessData, _secret);
    });

    test('handles an empty or unusable paste', () {
      expect(BilibiliCookies.fromUserInput('').isEmpty, isTrue);
      expect(BilibiliCookies.fromUserInput('   \n  ').isEmpty, isTrue);
      expect(BilibiliCookies.fromUserInput('Cookie:').isEmpty, isTrue);
      expect(BilibiliCookies.fromUserInput('just some text').isEmpty, isTrue);
    });
  });

  group('credential redaction', () {
    test('no log-safe string contains a cookie value', () {
      final cookies = _fixtureCookies();
      final session = BilibiliAccountSession(
        accountId: '100000001',
        cookies: cookies,
        name: 'Example Account',
      );
      final auth = BilibiliAccountAuthProvider(session);
      final state = BilibiliCookieStoreState(
        accounts: <String, BilibiliCookies>{'100000001': cookies},
        activeAccountKey: '100000001',
      );
      final store = InMemoryBilibiliCookieStore();
      final validity = BilibiliCookieValidity(
        state: BilibiliSessionState.expired,
        platformErrorCode: -101,
        message: 'Account not logged in',
      );

      final surfaces = <String, String>{
        'BilibiliCookies': cookies.toString(),
        'BilibiliCookies.redactedSummary': cookies.redactedSummary,
        'BilibiliAccountSession': session.toString(),
        'BilibiliAccountAuthProvider': auth.toString(),
        'BilibiliCookieStoreState': state.toString(),
        'InMemoryBilibiliCookieStore': store.toString(),
        'BilibiliCookieValidity': validity.toString(),
      };

      for (final entry in surfaces.entries) {
        expect(
          entry.value,
          isNot(contains(_secret)),
          reason: '${entry.key} leaked SESSDATA',
        );
        expect(
          entry.value,
          isNot(contains(_csrfSecret)),
          reason: '${entry.key} leaked the csrf token',
        );
      }
    });

    test('redacted summary only reports the cookie count', () {
      expect(_fixtureCookies().redactedSummary, '<redacted: 5 cookie(s)>');
    });

    test('the auth provider still exposes the raw header for HTTP use', () {
      final auth = BilibiliAccountAuthProvider(
        BilibiliAccountSession(
          accountId: '100000001',
          cookies: _fixtureCookies(),
        ),
      );

      expect(auth.cookieHeader, contains('SESSDATA=$_secret'));
      expect(auth.requestHeaders['Referer'], 'https://www.bilibili.com/');
      expect(auth.requestHeaders.containsKey('Cookie'), isFalse);
    });

    test('the anonymous session exposes no cookie header', () {
      final auth = BilibiliAccountAuthProvider();

      expect(auth.cookieHeader, isNull);
      expect(auth.toString(), contains('anonymous: true'));
    });
  });
}
