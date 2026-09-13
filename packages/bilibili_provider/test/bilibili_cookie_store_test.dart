import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

const String _secret = 'fixture-sessdata-secret-9f3a';

BilibiliCookies _cookies(String mid) {
  return BilibiliCookies(<String, String>{
    'SESSDATA': '$_secret-$mid',
    'bili_jct': 'fixture-csrf-$mid',
    'DedeUserID': mid,
  });
}

void main() {
  group('BilibiliCookieStoreState', () {
    test('starts empty', () {
      final state = BilibiliCookieStoreState.empty;

      expect(state.isEmpty, isTrue);
      expect(state.activeAccountKey, isNull);
    });

    test('rejects external mutation of the account map', () {
      final state = BilibiliCookieStoreState(
        accounts: <String, BilibiliCookies>{'1': _cookies('1')},
      );

      expect(() => state.accounts['2'] = _cookies('2'), throwsUnsupportedError);
    });

    test('copyWith can clear the active account key', () {
      final state = BilibiliCookieStoreState(
        accounts: <String, BilibiliCookies>{'1': _cookies('1')},
        activeAccountKey: '1',
      );

      expect(state.copyWith(clearActiveAccount: true).activeAccountKey, isNull);
      expect(state.copyWith().activeAccountKey, '1');
    });

    test('toString is redacted', () {
      final state = BilibiliCookieStoreState(
        accounts: <String, BilibiliCookies>{'100000001': _cookies('100000001')},
        activeAccountKey: '100000001',
      );

      expect(state.toString(), isNot(contains(_secret)));
      expect(state.toString(), contains('active: 100000001'));
    });
  });

  group('InMemoryBilibiliCookieStore', () {
    test('reads empty before anything is written', () async {
      final store = InMemoryBilibiliCookieStore();

      expect((await store.read()).isEmpty, isTrue);
    });

    test('round-trips accounts and the active key', () async {
      final store = InMemoryBilibiliCookieStore();
      await store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{
            '100000001': _cookies('100000001'),
            '100000002': _cookies('100000002'),
          },
          activeAccountKey: '100000002',
        ),
      );

      final restored = await store.read();

      expect(restored.accounts.keys, <String>['100000001', '100000002']);
      expect(restored.activeAccountKey, '100000002');
      expect(restored.accounts['100000001']?.sessData, '$_secret-100000001');
    });

    test('clear removes every cookie', () async {
      final store = InMemoryBilibiliCookieStore();
      await store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{'1': _cookies('1')},
          activeAccountKey: '1',
        ),
      );

      await store.clear();

      expect((await store.read()).isEmpty, isTrue);
    });

    test('stays in memory: nothing is written to a file', () async {
      final store = InMemoryBilibiliCookieStore();
      await store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{'1': _cookies('1')},
        ),
      );

      expect(
        store.toString(),
        'InMemoryBilibiliCookieStore('
        'BilibiliCookieStoreState(accounts: [1], active: null))',
      );
      expect(store.toString(), isNot(contains(_secret)));
    });
  });
}
