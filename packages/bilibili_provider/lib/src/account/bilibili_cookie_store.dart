import 'dart:collection';

import 'bilibili_cookies.dart';

/// Persisted account-layer state: one cookie jar per account plus the key of the
/// account that was active when the state was written.
///
/// This type only holds credentials. Profile fields such as name and avatar are
/// re-derived from `x/web-interface/nav` after [BilibiliCookieStore.read].
class BilibiliCookieStoreState {
  BilibiliCookieStoreState({
    Map<String, BilibiliCookies> accounts = const <String, BilibiliCookies>{},
    this.activeAccountKey,
  }) : accounts = UnmodifiableMapView<String, BilibiliCookies>(
         LinkedHashMap<String, BilibiliCookies>.of(accounts),
       );

  /// Empty state.
  static final BilibiliCookieStoreState empty = BilibiliCookieStoreState();

  /// Cookie jars keyed by account key (the numeric mid as a string).
  final Map<String, BilibiliCookies> accounts;

  /// Account key that should become active after restore, when still present.
  final String? activeAccountKey;

  bool get isEmpty => accounts.isEmpty;

  BilibiliCookieStoreState copyWith({
    Map<String, BilibiliCookies>? accounts,
    String? activeAccountKey,
    bool clearActiveAccount = false,
  }) {
    return BilibiliCookieStoreState(
      accounts: accounts ?? this.accounts,
      activeAccountKey: clearActiveAccount
          ? null
          : (activeAccountKey ?? this.activeAccountKey),
    );
  }

  /// Redacted representation. Never contains a cookie value.
  @override
  String toString() {
    return 'BilibiliCookieStoreState(accounts: ${accounts.keys.toList()}, '
        'active: $activeAccountKey)';
  }
}

/// Persistence boundary for Bilibili account cookies.
///
/// Implementations supplied by an application (for example Namida, which already
/// has encrypted storage) are responsible for protecting the values at rest.
/// This package only ships [InMemoryBilibiliCookieStore], so nothing is written
/// to disk by default and cookies cannot end up committed to a repository.
///
/// Implementations must never log cookie values.
abstract interface class BilibiliCookieStore {
  /// Reads the persisted state. Returns [BilibiliCookieStoreState.empty] when
  /// nothing has been stored yet.
  Future<BilibiliCookieStoreState> read();

  /// Replaces the persisted state.
  Future<void> write(BilibiliCookieStoreState state);

  /// Removes all persisted account cookies.
  Future<void> clear();
}

/// Process-local cookie store. Default for [BilibiliAccountManager].
///
/// Nothing is written to disk, so cookies stay in memory for the lifetime of the
/// process.
final class InMemoryBilibiliCookieStore implements BilibiliCookieStore {
  BilibiliCookieStoreState _state = BilibiliCookieStoreState.empty;

  @override
  Future<BilibiliCookieStoreState> read() async => _state;

  @override
  Future<void> write(BilibiliCookieStoreState state) async {
    _state = state;
  }

  @override
  Future<void> clear() async {
    _state = BilibiliCookieStoreState.empty;
  }

  /// Redacted representation. Never contains a cookie value.
  @override
  String toString() => 'InMemoryBilibiliCookieStore($_state)';
}

/// Wraps another store and lets an application disable persistence at runtime.
///
/// Useful for a "do not remember this login" choice in a sign-in form:
///
/// ```dart
/// final store = ConditionalBilibiliCookieStore(PlainTextFileBilibiliCookieStore());
/// final manager = BilibiliAccountManager(cookieStore: store);
/// ...
/// store.persist = rememberMe;   // false -> writes are dropped
/// await manager.signIn(pastedCookies);
/// ```
///
/// While [persist] is false, [write] is dropped and the inner store is left
/// exactly as it was, so an existing saved login is neither overwritten nor
/// deleted. [read] and [clear] still delegate, so [clear] always works.
final class ConditionalBilibiliCookieStore implements BilibiliCookieStore {
  ConditionalBilibiliCookieStore(this.inner, {this.persist = true});

  /// Store that receives writes while [persist] is true.
  final BilibiliCookieStore inner;

  /// Whether [write] is forwarded to [inner].
  bool persist;

  @override
  Future<BilibiliCookieStoreState> read() => inner.read();

  @override
  Future<void> write(BilibiliCookieStoreState state) async {
    if (!persist) {
      return;
    }
    await inner.write(state);
  }

  @override
  Future<void> clear() => inner.clear();

  /// Redacted representation. Never contains a cookie value.
  @override
  String toString() {
    return 'ConditionalBilibiliCookieStore(persist: $persist, inner: $inner)';
  }
}
