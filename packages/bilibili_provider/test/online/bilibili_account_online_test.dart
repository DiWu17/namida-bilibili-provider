@Tags(<String>['online'])
library;

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

/// Credential-free online checks for the account layer.
///
/// These tests never send cookies, so they only verify that anonymous access
/// still works and that the layer refuses to claim a signed-in account without
/// credentials. Tests that need a real Bilibili account are intentionally not
/// part of the suite; supply cookies through `BilibiliAccountManager.signIn` in
/// a local scratch test instead.
///
/// No explicit `timeout` is set: package:test already defaults to 30 seconds for
/// these small requests.
void main() {
  test('nav without cookies reports an unauthenticated session', () async {
    final client = BilibiliAccountClient();

    final nav = await client.getNav();

    expect(nav.isLogin, isFalse);
    expect(nav.account, isNull);
    expect(nav.validity.isAuthenticated, isFalse);
    expect(
      nav.validity.requiresSignIn,
      isFalse,
      reason: 'anonymous access is not an expired session',
    );
  });

  test('account manager stays anonymous and sends no cookies', () async {
    final manager = BilibiliAccountManager();
    addTearDown(manager.dispose);

    expect(manager.isAnonymous, isTrue);
    expect(manager.authProvider.cookieHeader, isNull);

    final validity = await manager.validateActiveCookies();

    expect(validity.isAnonymous, isTrue);
    expect(manager.signedInAccounts, isEmpty);
    expect(manager.activeAccountDetails, isNull);
  });

  test(
    'QR login issues a scannable ticket and reports it as pending',
    () async {
      final client = BilibiliAccountClient();

      final login = await client.generateQrLogin();

      expect(login.qrcodeKey, isNotEmpty);
      expect(login.uri.hasScheme, isTrue);
      expect(login.uri.host, isNotEmpty);
      expect(
        login.uri.queryParameters['qrcode_key'],
        login.qrcodeKey,
        reason: 'the QR content must carry the key that will be polled',
      );
      expect(
        login.toString(),
        isNot(contains(login.qrcodeKey)),
        reason: 'the ticket is a login credential and must stay redacted',
      );

      // A fresh ticket cannot be confirmed, because nobody scanned it.
      final status = await client.pollQrLogin(login);

      expect(status.isConfirmed, isFalse);
      expect(status.stage, BilibiliQrLoginStage.pending);
      expect(status.cookies, isNull);
    },
  );
}
