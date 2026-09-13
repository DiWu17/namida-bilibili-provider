import 'dart:async';

import '../bilibili_provider.dart';
import '../client/bilibili_account_client.dart';
import '../errors/bilibili_exception.dart';
import '../models/bilibili_account_api_models.dart';
import '../models/bilibili_qr_login_models.dart';
import 'bilibili_account_auth.dart';
import 'bilibili_account_session.dart';
import 'bilibili_cookie_store.dart';
import 'bilibili_cookies.dart';

/// Account layer for Bilibili: cookie storage, current account, account
/// switching, sign-out, and explicit sign-in.
///
/// Security model:
///
/// - the layer starts anonymous and stays anonymous until the caller supplies
///   cookies through [signIn] or [signInWithCookies];
/// - cookies are never read from a browser profile, never written to disk by
///   default ([InMemoryBilibiliCookieStore]), and never logged;
/// - a candidate cookie jar is validated with `x/web-interface/nav` before it is
///   adopted, so a rejected jar cannot silently replace a working session;
/// - only content the signed-in user already has access to is requested.
///
/// This mirrors the shape Namida needs on the YouTube side
/// (`YoutubeAccountController` / `YoutiPie.cookies`) without reusing any YouTube
/// concept: there is no fake YouTube id and no shared DTO.
class BilibiliAccountManager {
  BilibiliAccountManager({
    BilibiliAccountClient? client,
    BilibiliAccountAuthProvider? authProvider,
    BilibiliCookieStore? cookieStore,
    this.allowMultipleAccounts = true,
    this.maxAccounts = 5,
  }) : _auth = authProvider ?? BilibiliAccountAuthProvider(),
       _cookieStore = cookieStore ?? InMemoryBilibiliCookieStore(),
       assert(maxAccounts >= 1) {
    _client = client ?? BilibiliAccountClient(auth: _auth);
  }

  /// Whether more than one account may be kept signed in.
  final bool allowMultipleAccounts;

  /// Upper bound on stored accounts. Signing in beyond it is rejected.
  final int maxAccounts;

  final BilibiliAccountAuthProvider _auth;
  final BilibiliCookieStore _cookieStore;
  final Map<String, BilibiliAccountSession> _sessions =
      <String, BilibiliAccountSession>{};
  final StreamController<BilibiliAccountSession> _changes =
      StreamController<BilibiliAccountSession>.broadcast();

  late final BilibiliAccountClient _client;

  BilibiliAccountSession _active = BilibiliAccountSession.anonymous;
  BilibiliAccountInfo? _activeInfo;
  BilibiliCookieValidity _validity = BilibiliCookieValidity.unchecked;
  bool _disposed = false;

  /// HTTP client used for account requests. It reads the active session through
  /// [authProvider], so it always follows sign-in and account switching.
  BilibiliAccountClient get client => _client;

  /// Auth provider bound to the active session.
  ///
  /// Share it with any other Bilibili client that should act as the signed-in
  /// user.
  BilibiliAccountAuthProvider get authProvider => _auth;

  /// Currently active session. Anonymous when no account is selected.
  BilibiliAccountSession get activeSession => _active;

  /// Active account key, or null while anonymous.
  String? get activeAccountKey =>
      _active.isAnonymous ? null : _active.accountId;

  /// Profile of the active account, when it has been fetched.
  BilibiliAccountInfo? get activeAccountDetails => _activeInfo;

  /// Result of the most recent cookie check.
  BilibiliCookieValidity get cookieValidity => _validity;

  bool get isAnonymous => _active.isAnonymous;

  /// Every kept-signed-in account, in insertion order.
  List<BilibiliAccountSession> get signedInAccounts =>
      List<BilibiliAccountSession>.unmodifiable(_sessions.values);

  /// Whether another account can be added.
  bool get canAddMultipleAccounts => allowMultipleAccounts && maxAccounts > 1;

  /// Emits whenever the active account changes: sign-in, account switch,
  /// sign-out, and [setAnonymous].
  ///
  /// Profile refreshes of the same account do not emit.
  Stream<BilibiliAccountSession> get onAccountChanged => _changes.stream;

  /// Loads persisted cookies and restores the previously active account.
  ///
  /// Profile fields are not fetched here; call [getCurrentAccount] afterwards
  /// when the caller needs them.
  Future<void> restore() async {
    final state = await _cookieStore.read();

    _sessions.clear();
    for (final entry in state.accounts.entries) {
      final cookies = entry.value;
      if (!cookies.hasSessionToken) {
        continue;
      }
      _sessions[entry.key] = BilibiliAccountSession(
        accountId: entry.key,
        cookies: cookies,
      );
    }

    final key = state.activeAccountKey;
    final restored = key == null ? null : _sessions[key];
    await _setActive(
      restored ?? BilibiliAccountSession.anonymous,
      notify: false,
    );
  }

  /// Returns the current account profile, or null when not signed in.
  ///
  /// A cookie that the server no longer accepts is reported through
  /// [cookieValidity] rather than thrown, because "expired" is a normal state
  /// the UI must render. Transport and parse failures still throw.
  Future<BilibiliAccountInfo?> getCurrentAccount({
    bool forceRefresh = false,
  }) async {
    if (_active.isAnonymous) {
      _validity = const BilibiliCookieValidity(
        state: BilibiliSessionState.anonymous,
      );
      return null;
    }

    if (!forceRefresh && _validity.isAuthenticated && _activeInfo != null) {
      return _activeInfo;
    }

    final nav = await _client.getNav();
    _validity = nav.validity;

    final account = nav.account;
    if (account == null) {
      _activeInfo = null;
      return null;
    }

    _activeInfo = account;
    await _applyProfile(account);
    return account;
  }

  /// Checks whether the active cookies are still accepted.
  ///
  /// Anonymous sessions resolve locally without a network request.
  Future<BilibiliCookieValidity> validateActiveCookies({
    bool forceRefresh = true,
  }) async {
    await getCurrentAccount(forceRefresh: forceRefresh);
    return _validity;
  }

  /// Signs in from an explicit `Cookie` header supplied by the user.
  ///
  /// The header is validated against Bilibili before it is adopted. A rejected
  /// header never replaces the current session, and its value never appears in
  /// an exception message or a log.
  Future<BilibiliAccountSession> signIn(String cookieHeader) {
    return signInWithCookies(BilibiliCookies.parse(cookieHeader));
  }

  /// Signs in from an already-parsed cookie jar. See [signIn].
  Future<BilibiliAccountSession> signInWithCookies(
    BilibiliCookies cookies,
  ) async {
    if (cookies.isEmpty) {
      throw const BilibiliAuthenticationException(
        'Bilibili sign-in requires cookies supplied by the user.',
      );
    }
    if (!cookies.hasSessionToken) {
      throw const BilibiliAuthenticationException(
        'Bilibili sign-in requires a session cookie (SESSDATA).',
      );
    }

    final nav = await _client.getNav(cookies: cookies);
    final account = nav.account;
    if (account == null) {
      throw BilibiliAuthenticationException(
        'Bilibili did not accept the provided cookies; '
        'the session is not signed in.',
        platformErrorCode: nav.code,
      );
    }

    final accountId = '${account.mid}';
    if (!_sessions.containsKey(accountId) && !_canAddAccount()) {
      throw BilibiliAuthenticationException(
        allowMultipleAccounts
            ? 'Bilibili account limit of $maxAccounts has been reached.'
            : 'This Bilibili account layer is configured for a single account.',
      );
    }

    final session = BilibiliAccountSession(
      accountId: accountId,
      cookies: cookies,
      name: account.name,
      avatar: account.avatar,
    );
    _sessions[accountId] = session;

    await _setActive(session, account: account, validity: nav.validity);
    await _persist();
    return session;
  }

  /// Signs in with a QR code that the user scans in the official Bilibili app.
  ///
  /// This is the primary login path. It mirrors the shape Namida uses for
  /// YouTube (`YoutiAccountManager.signIn(pageConfig:, onProgress:)`): the caller
  /// supplies a progress callback, and the account layer drives the flow.
  ///
  /// 1. asks Bilibili for a ticket and reports
  ///    [BilibiliQrLoginStage.pending] through [onProgress];
  /// 2. polls every [pollInterval] until the ticket is confirmed, expires, or
  ///    [timeout] elapses;
  /// 3. on confirmation, validates the delivered cookies through `nav` and
  ///    adopts the session through the same path as [signInWithCookies].
  ///
  /// Returns the new session, or null when the attempt expired, timed out, or
  /// was cancelled through [isCancelled]. A rejected session throws, exactly like
  /// [signInWithCookies].
  ///
  /// Credentials never pass through the caller: the user confirms on their own
  /// device, and this package only ever sees the resulting cookies.
  Future<BilibiliAccountSession?> signInWithQrCode({
    void Function(BilibiliQrLoginStatus status)? onProgress,
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
    bool Function()? isCancelled,
  }) async {
    if (pollInterval <= Duration.zero) {
      throw const BilibiliParseException(
        'QR login pollInterval must be positive.',
      );
    }
    if (timeout <= Duration.zero) {
      throw const BilibiliParseException('QR login timeout must be positive.');
    }

    final login = await _client.generateQrLogin();
    onProgress?.call(
      BilibiliQrLoginStatus(stage: BilibiliQrLoginStage.pending, login: login),
    );

    final deadline = DateTime.now().add(timeout);
    var lastStage = BilibiliQrLoginStage.pending;

    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        return null;
      }

      await Future<void>.delayed(pollInterval);

      if (isCancelled?.call() ?? false) {
        return null;
      }

      final status = (await _client.pollQrLogin(login)).withLogin(login);
      lastStage = status.stage;
      onProgress?.call(status);

      switch (status.stage) {
        case BilibiliQrLoginStage.confirmed:
          final cookies = status.cookies;
          if (cookies == null) {
            throw const BilibiliAuthenticationException(
              'Bilibili confirmed the QR login without session cookies.',
            );
          }
          return signInWithCookies(cookies);
        case BilibiliQrLoginStage.expired:
        case BilibiliQrLoginStage.failed:
          return null;
        case BilibiliQrLoginStage.pending:
        case BilibiliQrLoginStage.scanned:
          continue;
      }
    }

    onProgress?.call(
      BilibiliQrLoginStatus(
        stage: BilibiliQrLoginStage.expired,
        login: login,
        message:
            'QR login timed out after ${timeout.inSeconds}s '
            '(last state: ${lastStage.name}).',
      ),
    );
    return null;
  }

  /// Makes a stored account active.
  Future<BilibiliAccountSession> switchAccount(String accountKey) async {
    final session = _sessions[accountKey];
    if (session == null) {
      throw BilibiliNotFoundException(
        'No signed-in Bilibili account is stored under key "$accountKey".',
      );
    }

    await _setActive(session);
    await _persist();
    return session;
  }

  /// Signs out [accountKey], or the active account when omitted.
  ///
  /// The active slot falls back to another stored account, or to anonymous.
  Future<void> signOut([String? accountKey]) async {
    final key = accountKey ?? activeAccountKey;
    if (key == null) {
      await setAnonymous();
      return;
    }

    final removed = _sessions.remove(key);
    if (removed == null) {
      return;
    }

    if (_active.accountId == key) {
      final next = _sessions.isEmpty
          ? BilibiliAccountSession.anonymous
          : _sessions.values.first;
      await _setActive(next);
    }
    await _persist();
  }

  /// Drops every stored account and forgets the persisted cookie state.
  Future<void> signOutAll() async {
    _sessions.clear();
    await _setActive(BilibiliAccountSession.anonymous);
    await _cookieStore.clear();
  }

  /// Keeps stored accounts but stops sending their cookies.
  ///
  /// This is the counterpart of Namida's `YoutiPie.cookies.setAnonymous()`.
  Future<void> setAnonymous() async {
    await _setActive(BilibiliAccountSession.anonymous);
    await _persist();
  }

  /// Creates a media provider that acts as the currently active account.
  ///
  /// Ordinary public playback behaves exactly like `BilibiliProvider()`;
  /// sharing the session only means requests carry the user's own cookies.
  BilibiliProvider createMediaProvider({bool debug = false}) {
    return BilibiliProvider(auth: _auth, debug: debug);
  }

  /// Releases the change stream. The manager must not be used afterwards.
  Future<void> dispose() async {
    _disposed = true;
    await _changes.close();
  }

  bool _canAddAccount() {
    if (!allowMultipleAccounts) {
      return _sessions.isEmpty;
    }
    return _sessions.length < maxAccounts;
  }

  Future<void> _setActive(
    BilibiliAccountSession session, {
    BilibiliAccountInfo? account,
    BilibiliCookieValidity? validity,
    bool notify = true,
  }) async {
    _active = session;
    _activeInfo = account;
    _validity =
        validity ??
        (session.isAnonymous
            ? const BilibiliCookieValidity(
                state: BilibiliSessionState.anonymous,
              )
            : BilibiliCookieValidity.unchecked);
    _auth.setSession(session);

    if (notify && !_disposed && !_changes.isClosed) {
      _changes.add(session);
    }
  }

  /// Stores the profile fetched from `nav` on the active session.
  Future<void> _applyProfile(BilibiliAccountInfo account) async {
    final updated = _active.copyWith(
      name: account.name,
      avatar: account.avatar,
    );
    _active = updated;
    _sessions[updated.accountId] = updated;
    _auth.setSession(updated);
    await _persist();
  }

  Future<void> _persist() async {
    await _cookieStore.write(
      BilibiliCookieStoreState(
        accounts: <String, BilibiliCookies>{
          for (final entry in _sessions.entries) entry.key: entry.value.cookies,
        },
        activeAccountKey: activeAccountKey,
      ),
    );
  }

  /// Redacted representation, safe to log. Never contains a cookie value.
  @override
  String toString() {
    return 'BilibiliAccountManager(active: $activeAccountKey, '
        'accounts: ${_sessions.length}, anonymous: $isAnonymous, '
        'validity: ${_validity.state.name})';
  }
}
