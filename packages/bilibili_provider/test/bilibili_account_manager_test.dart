import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _sessOne = 'fixture-sessdata-secret-one-9f3a';
const String _sessTwo = 'fixture-sessdata-secret-two-7d21';
const String _csrfOne = 'fixture-csrf-secret-one-4c1b';
const String _csrfTwo = 'fixture-csrf-secret-two-8e0d';

const String _cookieOne =
    'SESSDATA=$_sessOne; bili_jct=$_csrfOne; DedeUserID=100000001';
const String _cookieTwo =
    'SESSDATA=$_sessTwo; bili_jct=$_csrfTwo; DedeUserID=100000002';

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

/// Test harness that answers `nav` according to the cookie that was sent.
class _Harness {
  /// When true, account one's cookie is answered with "not logged in".
  bool rejectAccountOne = false;

  /// Every nav request that carried a Cookie header.
  final List<String?> navCookies = <String?>[];
  int navRequests = 0;

  final InMemoryBilibiliCookieStore store = InMemoryBilibiliCookieStore();
  final BilibiliAccountAuthProvider auth = BilibiliAccountAuthProvider();
  late final BilibiliAccountManager manager = BilibiliAccountManager(
    authProvider: auth,
    cookieStore: store,
    client: BilibiliAccountClient(
      auth: auth,
      httpClient: MockClient((request) async {
        if (request.url.path == '/x/web-interface/nav') {
          navRequests++;
          final cookie = request.headers['Cookie'];
          navCookies.add(cookie);

          if (cookie != null && cookie.contains('SESSDATA=$_sessTwo')) {
            return _jsonFixture('nav_logged_in_second.json');
          }
          if (cookie != null && cookie.contains('SESSDATA=$_sessOne')) {
            return rejectAccountOne
                ? _jsonFixture('nav_not_logged_in.json')
                : _jsonFixture('nav_logged_in.json');
          }
          return _jsonFixture('nav_not_logged_in.json');
        }

        if (request.url.path == '/x/space/myinfo') {
          return _jsonFixture('space_myinfo.json');
        }

        throw StateError(
          'unexpected request: ${request.method} '
          '${request.url.path}',
        );
      }),
    ),
  );
}

void main() {
  group('anonymous defaults', () {
    test(
      'starts anonymous and never calls the network for the profile',
      () async {
        final harness = _Harness();

        expect(harness.manager.isAnonymous, isTrue);
        expect(harness.manager.activeAccountKey, isNull);
        expect(harness.manager.signedInAccounts, isEmpty);
        expect(harness.manager.activeAccountDetails, isNull);
        expect(harness.manager.authProvider.cookieHeader, isNull);

        expect(await harness.manager.getCurrentAccount(), isNull);
        expect(harness.navRequests, 0);
      },
    );

    test('reports the anonymous validity state locally', () async {
      final harness = _Harness();

      final validity = await harness.manager.validateActiveCookies();

      expect(validity.state, BilibiliSessionState.anonymous);
      expect(validity.isAnonymous, isTrue);
      expect(harness.navRequests, 0);
    });
  });

  group('signIn', () {
    test('validates the cookies and adopts the account', () async {
      final harness = _Harness();

      final session = await harness.manager.signIn(_cookieOne);

      expect(session.accountId, '100000001');
      expect(session.mid, 100000001);
      expect(session.name, 'Example Account');
      expect(session.avatar?.host, 'i0.hdslb.com');
      expect(harness.manager.isAnonymous, isFalse);
      expect(harness.manager.activeAccountDetails?.mid, 100000001);
      expect(harness.manager.cookieValidity.isAuthenticated, isTrue);
      expect(harness.manager.activeSession.hasSessionToken, isTrue);
      expect(harness.navRequests, 1);

      // The candidate cookie is validated through the override, then adopted.
      expect(harness.navCookies.single, contains('SESSDATA=$_sessOne'));
      expect(harness.auth.cookieHeader, contains('SESSDATA=$_sessOne'));
    });

    test('persists only cookies plus the active key', () async {
      final harness = _Harness();

      await harness.manager.signIn(_cookieOne);

      final state = await harness.store.read();
      expect(state.accounts.keys, <String>['100000001']);
      expect(state.accounts['100000001']?.csrfToken, _csrfOne);
      expect(state.activeAccountKey, '100000001');
      expect(state.toString(), isNot(contains(_sessOne)));
    });

    test('rejects a blank cookie header without a request', () async {
      final harness = _Harness();

      await expectLater(
        () => harness.manager.signIn('   '),
        throwsA(isA<BilibiliAuthenticationException>()),
      );
      await expectLater(
        () => harness.manager.signIn('buvid3=device-only'),
        throwsA(isA<BilibiliAuthenticationException>()),
      );
      expect(harness.navRequests, 0);
      expect(harness.manager.isAnonymous, isTrue);
    });

    test('keeps the previous session when cookies are rejected', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);
      harness.rejectAccountOne = true;

      try {
        await harness.manager.signIn(_cookieTwo.replaceAll(_sessTwo, 'nope'));
        fail('expected an authentication failure');
      } on BilibiliAuthenticationException catch (error) {
        expect(error.platformErrorCode, -101);
        expect(error.message, isNot(contains('nope')));
        expect(error.toString(), isNot(contains('nope')));
      }

      expect(harness.manager.activeSession.accountId, '100000001');
      expect(harness.auth.cookieHeader, contains('SESSDATA=$_sessOne'));
      expect((await harness.store.read()).accounts.keys, <String>['100000001']);
    });

    test('caches the profile for repeated getCurrentAccount calls', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);

      final account = await harness.manager.getCurrentAccount();

      expect(account?.name, 'Example Account');
      expect(harness.navRequests, 1, reason: 'the cached profile was reused');
    });
  });

  group('cookie expiry handling', () {
    test('reports an expired session instead of throwing', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);
      harness.rejectAccountOne = true;

      final account = await harness.manager.getCurrentAccount(
        forceRefresh: true,
      );

      expect(account, isNull);
      expect(
        harness.manager.cookieValidity.state,
        BilibiliSessionState.expired,
      );
      expect(harness.manager.cookieValidity.requiresSignIn, isTrue);
      expect(harness.manager.activeAccountDetails, isNull);
      expect(
        harness.manager.activeSession.accountId,
        '100000001',
        reason: 'the session is kept so the UI can offer a re-login',
      );
    });

    test(
      'refreshing recovers the profile once cookies are accepted again',
      () async {
        final harness = _Harness();
        await harness.manager.signIn(_cookieOne);
        harness.rejectAccountOne = true;
        await harness.manager.getCurrentAccount(forceRefresh: true);

        harness.rejectAccountOne = false;
        final account = await harness.manager.getCurrentAccount(
          forceRefresh: true,
        );

        expect(account?.mid, 100000001);
        expect(harness.manager.cookieValidity.isAuthenticated, isTrue);
      },
    );
  });

  group('account switching', () {
    test('keeps multiple accounts and switches between them', () async {
      final harness = _Harness();
      final events = <String>[];
      final subscription = harness.manager.onAccountChanged.listen(
        (session) => events.add(session.accountId),
      );
      addTearDown(subscription.cancel);

      await harness.manager.signIn(_cookieOne);
      await harness.manager.signIn(_cookieTwo);

      expect(harness.manager.signedInAccounts, hasLength(2));
      expect(harness.manager.activeSession.accountId, '100000002');
      expect(harness.auth.cookieHeader, contains('SESSDATA=$_sessTwo'));

      final switched = await harness.manager.switchAccount('100000001');

      expect(switched.name, 'Example Account');
      expect(harness.manager.activeSession.accountId, '100000001');
      expect(harness.auth.cookieHeader, contains('SESSDATA=$_sessOne'));
      expect((await harness.store.read()).activeAccountKey, '100000001');

      await pumpEventQueue();
      expect(events, <String>['100000001', '100000002', '100000001']);
    });

    test('refuses to switch to an unknown account', () async {
      final harness = _Harness();

      expect(
        () => harness.manager.switchAccount('404404'),
        throwsA(isA<BilibiliNotFoundException>()),
      );
    });

    test('enforces maxAccounts', () async {
      final auth = BilibiliAccountAuthProvider();
      final manager = BilibiliAccountManager(
        authProvider: auth,
        maxAccounts: 1,
        client: BilibiliAccountClient(
          auth: auth,
          httpClient: MockClient((request) async {
            final cookie = request.headers['Cookie'] ?? '';
            return cookie.contains('SESSDATA=$_sessTwo')
                ? _jsonFixture('nav_logged_in_second.json')
                : _jsonFixture('nav_logged_in.json');
          }),
        ),
      );

      await manager.signIn(_cookieOne);
      await expectLater(
        () => manager.signIn(_cookieTwo),
        throwsA(isA<BilibiliAuthenticationException>()),
      );

      expect(manager.signedInAccounts, hasLength(1));
      expect(manager.activeSession.accountId, '100000001');

      await manager.dispose();
    });

    test('can be restricted to a single account', () async {
      final auth = BilibiliAccountAuthProvider();
      final manager = BilibiliAccountManager(
        authProvider: auth,
        allowMultipleAccounts: false,
        client: BilibiliAccountClient(
          auth: auth,
          httpClient: MockClient((request) async {
            final cookie = request.headers['Cookie'] ?? '';
            return cookie.contains('SESSDATA=$_sessTwo')
                ? _jsonFixture('nav_logged_in_second.json')
                : _jsonFixture('nav_logged_in.json');
          }),
        ),
      );

      expect(manager.canAddMultipleAccounts, isFalse);
      await manager.signIn(_cookieOne);
      await expectLater(
        () => manager.signIn(_cookieTwo),
        throwsA(isA<BilibiliAuthenticationException>()),
      );

      // Re-signing the same account is allowed and refreshes it.
      final refreshed = await manager.signIn(_cookieOne);
      expect(refreshed.accountId, '100000001');

      await manager.dispose();
    });
  });

  group('signOut and setAnonymous', () {
    test('signOut falls back to another stored account', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);
      await harness.manager.signIn(_cookieTwo);

      await harness.manager.signOut();

      expect(harness.manager.signedInAccounts, hasLength(1));
      expect(harness.manager.activeSession.accountId, '100000001');
      expect(harness.auth.cookieHeader, contains('SESSDATA=$_sessOne'));
    });

    test('signing out the last account returns to anonymous', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);

      await harness.manager.signOut('100000001');

      expect(harness.manager.isAnonymous, isTrue);
      expect(harness.manager.signedInAccounts, isEmpty);
      expect(harness.auth.cookieHeader, isNull);
      expect((await harness.store.read()).isEmpty, isTrue);
    });

    test('signOut of an unknown key is a no-op', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);

      await harness.manager.signOut('404404');

      expect(harness.manager.activeSession.accountId, '100000001');
    });

    test('setAnonymous keeps accounts but stops sending cookies', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);

      await harness.manager.setAnonymous();

      expect(harness.manager.isAnonymous, isTrue);
      expect(harness.manager.signedInAccounts, hasLength(1));
      expect(harness.auth.cookieHeader, isNull);
      expect((await harness.store.read()).activeAccountKey, isNull);
    });

    test('signOutAll clears the store', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);

      await harness.manager.signOutAll();

      expect(harness.manager.signedInAccounts, isEmpty);
      expect(harness.manager.isAnonymous, isTrue);
      expect((await harness.store.read()).isEmpty, isTrue);
    });
  });

  group('restore', () {
    test('restores stored accounts and the previously active one', () async {
      final harness = _Harness();
      await harness.store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{
            '100000001': BilibiliCookies.parse(_cookieOne),
            '100000002': BilibiliCookies.parse(_cookieTwo),
          },
          activeAccountKey: '100000002',
        ),
      );

      await harness.manager.restore();

      expect(harness.manager.signedInAccounts, hasLength(2));
      expect(harness.manager.activeSession.accountId, '100000002');
      expect(harness.auth.cookieHeader, contains('SESSDATA=$_sessTwo'));
      expect(
        harness.manager.activeAccountDetails,
        isNull,
        reason: 'the profile is fetched on demand, not during restore',
      );
      expect(harness.navRequests, 0);

      final account = await harness.manager.getCurrentAccount();
      expect(account?.name, 'Second Account');
    });

    test('falls back to anonymous when the active key is gone', () async {
      final harness = _Harness();
      await harness.store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{
            '100000001': BilibiliCookies.parse(_cookieOne),
          },
          activeAccountKey: '100000099',
        ),
      );

      await harness.manager.restore();

      expect(harness.manager.isAnonymous, isTrue);
      expect(harness.manager.signedInAccounts, hasLength(1));
    });

    test('drops stored entries without a session token', () async {
      final harness = _Harness();
      await harness.store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{
            '100000001': BilibiliCookies(<String, String>{'buvid3': 'device'}),
          },
          activeAccountKey: '100000001',
        ),
      );

      await harness.manager.restore();

      expect(harness.manager.signedInAccounts, isEmpty);
      expect(harness.manager.isAnonymous, isTrue);
    });
  });

  group('createMediaProvider', () {
    test('shares the active session with playback requests', () async {
      final harness = _Harness();
      await harness.manager.signIn(_cookieOne);

      final provider = harness.manager.createMediaProvider();

      expect(provider.client.auth.cookieHeader, contains('SESSDATA=$_sessOne'));
      expect(provider.providerId, 'bilibili');
    });

    test('stays anonymous while signed out', () async {
      final harness = _Harness();

      expect(
        harness.manager.createMediaProvider().client.auth.cookieHeader,
        isNull,
      );
    });
  });

  group('dispose', () {
    test('closes the account change stream', () async {
      final harness = _Harness();
      await harness.manager.dispose();

      await expectLater(
        harness.manager.onAccountChanged.toList(),
        completion(isEmpty),
      );
    });
  });
}
