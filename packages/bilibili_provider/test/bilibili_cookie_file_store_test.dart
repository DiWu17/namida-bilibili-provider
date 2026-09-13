import 'dart:convert';
import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:bilibili_provider/io.dart';
import 'package:test/test.dart';

const String _secret = 'fixture-sessdata-secret-9f3a';
const String _csrf = 'fixture-csrf-secret-4c1b';

BilibiliCookieStoreState _state({String? activeKey = '100000001'}) {
  return BilibiliCookieStoreState(
    accounts: <String, BilibiliCookies>{
      '100000001': BilibiliCookies(<String, String>{
        'SESSDATA': _secret,
        'bili_jct': _csrf,
        'DedeUserID': '100000001',
      }),
    },
    activeAccountKey: activeKey,
  );
}

void main() {
  late Directory tempDir;
  late PlainTextFileBilibiliCookieStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('bilibili_cookie_store_test');
    store = PlainTextFileBilibiliCookieStore(directory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('read', () {
    test('returns empty when no file exists and creates nothing', () async {
      final state = await store.read();

      expect(state.isEmpty, isTrue);
      expect(await store.exists(), isFalse);
    });

    test('round-trips accounts and the active key', () async {
      await store.write(_state());

      final restored = await PlainTextFileBilibiliCookieStore(
        directory: tempDir,
      ).read();

      expect(restored.accounts.keys, <String>['100000001']);
      expect(restored.accounts['100000001']?.sessData, _secret);
      expect(restored.accounts['100000001']?.csrfToken, _csrf);
      expect(restored.activeAccountKey, '100000001');
    });

    test('creates the directory on demand', () async {
      final nested = Directory('${tempDir.path}/a/b');
      final nestedStore = PlainTextFileBilibiliCookieStore(directory: nested);

      await nestedStore.write(_state());

      expect(await nestedStore.exists(), isTrue);
      expect((await nestedStore.read()).accounts, hasLength(1));
    });

    test('treats a corrupt file as empty instead of throwing', () async {
      await store.file.writeAsString('{"accounts": ');

      expect((await store.read()).isEmpty, isTrue);
    });

    test('treats a non-object payload as empty', () async {
      await store.file.writeAsString('[1, 2, 3]');

      expect((await store.read()).isEmpty, isTrue);
    });

    test('skips unusable entries but keeps the rest', () async {
      await store.file.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'activeAccountKey': 'missing',
          'accounts': <String, Object?>{
            '100000001': <String, Object?>{'SESSDATA': _secret},
            'bad-empty': <String, Object?>{},
            'bad-types': <String, Object?>{'SESSDATA': 42},
            'bad-value': 'not-a-map',
          },
        }),
      );

      final state = await store.read();

      expect(state.accounts.keys, <String>['100000001']);
      expect(
        state.activeAccountKey,
        isNull,
        reason: 'an active key that is not present must not be restored',
      );
    });
  });

  group('write', () {
    test('leaves no temporary file behind', () async {
      await store.write(_state());

      final leftovers = tempDir
          .listSync()
          .where((entity) => entity.path.endsWith('.tmp'))
          .toList();

      expect(leftovers, isEmpty);
      expect(tempDir.listSync(), hasLength(1));
    });

    test('replaces previous contents completely', () async {
      await store.write(_state());
      await store.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{
            '100000002': BilibiliCookies(<String, String>{'SESSDATA': 'other'}),
          },
        ),
      );

      final restored = await store.read();

      expect(restored.accounts.keys, <String>['100000002']);
      expect(restored.activeAccountKey, isNull);
    });

    test('clear removes the file', () async {
      await store.write(_state());
      expect(await store.exists(), isTrue);

      await store.clear();

      expect(await store.exists(), isFalse);
      expect((await store.read()).isEmpty, isTrue);
    });

    test('clear on a missing file is a no-op', () async {
      await expectLater(store.clear(), completes);
    });
  });

  group('payload helpers', () {
    test('encodeState produces a versioned payload with raw cookies', () {
      final payload = PlainTextFileBilibiliCookieStore.encodeState(_state());

      expect(
        payload['version'],
        PlainTextFileBilibiliCookieStore.payloadVersion,
      );
      expect(payload['activeAccountKey'], '100000001');
      expect(jsonEncode(payload), contains(_secret));
    });

    test('decodeState returns empty for an empty accounts map', () {
      final state = PlainTextFileBilibiliCookieStore.decodeState(
        jsonEncode(<String, Object?>{
          'version': 1,
          'accounts': <String, Object?>{},
        }),
      );

      expect(state.isEmpty, isTrue);
    });
  });

  group('defaultDirectory', () {
    test('maps Windows to APPDATA and normalizes separators', () {
      final directory = PlainTextFileBilibiliCookieStore.defaultDirectory(
        environment: <String, String>{
          'APPDATA': r'C:\Users\example\AppData\Roaming',
        },
        operatingSystem: 'windows',
      );

      expect(
        directory.path,
        'C:/Users/example/AppData/Roaming/'
        '${PlainTextFileBilibiliCookieStore.appFolderName}',
      );
    });

    test('keeps a UNC APPDATA prefix intact', () {
      final directory = PlainTextFileBilibiliCookieStore.defaultDirectory(
        environment: <String, String>{
          'APPDATA': r'\\fileserver\profiles\example\AppData\Roaming',
        },
        operatingSystem: 'windows',
      );

      expect(directory.path, startsWith(r'\\fileserver\profiles'));
      expect(
        directory.path,
        endsWith('\\${PlainTextFileBilibiliCookieStore.appFolderName}'),
      );
    });

    test('falls back to the user profile when APPDATA is missing', () {
      final directory = PlainTextFileBilibiliCookieStore.defaultDirectory(
        environment: <String, String>{'USERPROFILE': r'C:\Users\example'},
        operatingSystem: 'windows',
      );

      expect(
        directory.path,
        'C:/Users/example/AppData/Roaming/'
        '${PlainTextFileBilibiliCookieStore.appFolderName}',
      );
    });

    test('maps macOS to Application Support', () {
      final directory = PlainTextFileBilibiliCookieStore.defaultDirectory(
        environment: <String, String>{'HOME': '/Users/example'},
        operatingSystem: 'macos',
      );

      expect(
        directory.path,
        '/Users/example/Library/Application Support/'
        '${PlainTextFileBilibiliCookieStore.appFolderName}',
      );
    });

    test('maps Linux to XDG_DATA_HOME when set', () {
      final directory = PlainTextFileBilibiliCookieStore.defaultDirectory(
        environment: <String, String>{
          'HOME': '/home/example',
          'XDG_DATA_HOME': '/home/example/.local/state',
        },
        operatingSystem: 'linux',
      );

      expect(
        directory.path,
        '/home/example/.local/state/'
        '${PlainTextFileBilibiliCookieStore.appFolderName}',
      );
    });

    test('maps Linux to ~/.local/share by default', () {
      final directory = PlainTextFileBilibiliCookieStore.defaultDirectory(
        environment: <String, String>{'HOME': '/home/example'},
        operatingSystem: 'linux',
      );

      expect(
        directory.path,
        '/home/example/.local/share/'
        '${PlainTextFileBilibiliCookieStore.appFolderName}',
      );
    });
  });

  group('redaction', () {
    test('toString shows the path but never the payload', () async {
      await store.write(_state());

      final text = store.toString();

      expect(text, contains(store.file.path));
      expect(text, isNot(contains(_secret)));
      expect(text, isNot(contains(_csrf)));
    });
  });

  group('ConditionalBilibiliCookieStore', () {
    test('drops writes while persistence is disabled', () async {
      final conditional = ConditionalBilibiliCookieStore(store, persist: false);

      await conditional.write(_state());

      expect(await store.exists(), isFalse);
      expect((await conditional.read()).isEmpty, isTrue);
    });

    test('leaves an existing saved login untouched while disabled', () async {
      await store.write(_state());
      final conditional = ConditionalBilibiliCookieStore(store, persist: false);

      await conditional.write(
        BilibiliCookieStoreState(
          accounts: <String, BilibiliCookies>{
            '200000002': BilibiliCookies(<String, String>{'SESSDATA': 'other'}),
          },
        ),
      );

      final restored = await store.read();
      expect(restored.accounts.keys, <String>['100000001']);
      expect(restored.accounts['100000001']?.sessData, _secret);
    });

    test('persists again once re-enabled', () async {
      final conditional = ConditionalBilibiliCookieStore(store, persist: false);
      await conditional.write(_state());
      expect(await store.exists(), isFalse);

      conditional.persist = true;
      await conditional.write(_state());

      expect((await store.read()).accounts, hasLength(1));
    });

    test('clear always reaches the inner store', () async {
      await store.write(_state());
      final conditional = ConditionalBilibiliCookieStore(store, persist: false);

      await conditional.clear();

      expect(await store.exists(), isFalse);
    });

    test('toString is redacted', () async {
      await store.write(_state());
      final conditional = ConditionalBilibiliCookieStore(store);

      expect(conditional.toString(), isNot(contains(_secret)));
      expect(conditional.toString(), contains('persist: true'));
    });
  });

  group('BilibiliAccountManager integration', () {
    test('restores a saved login from the file store', () async {
      await store.write(_state());
      final manager = BilibiliAccountManager(cookieStore: store);

      await manager.restore();

      expect(manager.isAnonymous, isFalse);
      expect(manager.activeAccountKey, '100000001');
      expect(manager.activeSession.cookies.sessData, _secret);
    });

    test('signOutAll deletes the file', () async {
      await store.write(_state());
      final manager = BilibiliAccountManager(cookieStore: store);
      await manager.restore();

      await manager.signOutAll();

      expect(await store.exists(), isFalse);
      expect(manager.isAnonymous, isTrue);
    });

    test(
      'setAnonymous persists an empty state, so no login is restored',
      () async {
        final manager = BilibiliAccountManager(cookieStore: store);

        await manager.restore();
        await manager.setAnonymous();

        expect((await store.read()).isEmpty, isTrue);
        final restored = BilibiliAccountManager(cookieStore: store);
        await restored.restore();
        expect(restored.isAnonymous, isTrue);
      },
    );
  });
}
