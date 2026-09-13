import 'dart:convert';
import 'dart:io';

import 'bilibili_cookie_store.dart';
import 'bilibili_cookies.dart';

/// A [BilibiliCookieStore] that keeps account cookies in one JSON file.
///
/// ## Security
///
/// **The file is plain text.** It relies on the per-user permissions of the
/// application data directory, not on encryption:
///
/// - Windows: `%APPDATA%` is ACL-restricted to the current user;
/// - macOS: `~/Library/Application Support`;
/// - Linux: `$XDG_DATA_HOME` or `~/.local/share`, where the file inherits the
///   process umask, so other local users may be able to read it.
///
/// Prefer an OS keychain / DPAPI / `flutter_secure_storage` backed store in
/// production. This implementation exists so a desktop application can offer
/// "remember my login" without a platform plugin, and so integration tests have a
/// real store to exercise.
///
/// The store never logs file contents, and the payload is only ever written to
/// [file] or read back from it. Nothing is written until [write] is called, so an
/// application that never signs in never creates a file.
class PlainTextFileBilibiliCookieStore implements BilibiliCookieStore {
  /// Creates a store.
  ///
  /// [directory] defaults to [defaultDirectory]. [fileName] can be overridden so
  /// several profiles can coexist.
  PlainTextFileBilibiliCookieStore({
    Directory? directory,
    this.fileName = defaultFileName,
  }) : _directoryOverride = directory;

  /// Default file name inside the application data directory.
  static const String defaultFileName = 'bilibili_account_cookies.json';

  /// Directory name used under the platform application data root.
  static const String appFolderName = 'namida_bilibili_provider';

  /// Current on-disk payload version.
  static const int payloadVersion = 1;

  final String fileName;
  Directory? _directoryOverride;

  /// Directory that holds [file].
  ///
  /// Resolved from the environment on first access when not provided.
  Directory get directory => _directoryOverride ??= defaultDirectory();

  /// The cookie file. Its path is public; its contents are credentials.
  File get file => File('${directory.path}/$fileName');

  /// Whether a cookie file currently exists.
  Future<bool> exists() => file.exists();

  /// Resolves the per-user application data directory for Bilibili cookies.
  ///
  /// [environment] and [operatingSystem] are injectable so the mapping can be
  /// tested without touching the real machine.
  static Directory defaultDirectory({
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;

    if (os == 'windows') {
      final base = _firstNonEmpty(<String?>[
        env['APPDATA'],
        env['LOCALAPPDATA'],
        env['USERPROFILE'] == null
            ? null
            : '${env['USERPROFILE']}/AppData/Roaming',
      ]);
      return Directory(_join(base, appFolderName));
    }

    if (os == 'macos') {
      return Directory(
        _join(_home(env), 'Library/Application Support/$appFolderName'),
      );
    }

    final xdgDataHome = env['XDG_DATA_HOME'];
    final base = xdgDataHome != null && xdgDataHome.isNotEmpty
        ? xdgDataHome
        : _join(_home(env), '.local/share');
    return Directory(_join(base, appFolderName));
  }

  @override
  Future<BilibiliCookieStoreState> read() async {
    final cookieFile = file;
    final String raw;
    try {
      if (!await cookieFile.exists()) {
        return BilibiliCookieStoreState.empty;
      }
      raw = await cookieFile.readAsString();
    } on FileSystemException {
      // An unreadable file must not break startup; the user can sign in again.
      return BilibiliCookieStoreState.empty;
    }

    return decodeState(raw);
  }

  @override
  Future<void> write(BilibiliCookieStoreState state) async {
    await directory.create(recursive: true);

    final payload = jsonEncode(encodeState(state));
    final target = file;
    final temporary = File('${target.path}.tmp');

    try {
      await temporary.writeAsString(payload, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    } on FileSystemException {
      // Fall back to a direct write if the rename dance is not supported.
      await target.writeAsString(payload, flush: true);
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> clear() async {
    final cookieFile = file;
    try {
      if (await cookieFile.exists()) {
        await cookieFile.delete();
      }
    } on FileSystemException {
      // Nothing to do: the file is already unusable.
    }
  }

  /// Builds the JSON payload for [state].
  ///
  /// The returned map contains cookie values, so callers must not log it.
  static Map<String, Object?> encodeState(BilibiliCookieStoreState state) {
    return <String, Object?>{
      'version': payloadVersion,
      'activeAccountKey': state.activeAccountKey,
      'accounts': <String, Object?>{
        for (final entry in state.accounts.entries)
          entry.key: Map<String, String>.of(entry.value.values),
      },
    };
  }

  /// Parses a payload produced by [encodeState].
  ///
  /// Anything unreadable or malformed yields [BilibiliCookieStoreState.empty] and
  /// never throws, so a truncated or hand-edited file just means "sign in again".
  static BilibiliCookieStoreState decodeState(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return BilibiliCookieStoreState.empty;
    }

    if (decoded is! Map<Object?, Object?>) {
      return BilibiliCookieStoreState.empty;
    }

    final rawAccounts = decoded['accounts'];
    if (rawAccounts is! Map<Object?, Object?>) {
      return BilibiliCookieStoreState.empty;
    }

    final accounts = <String, BilibiliCookies>{};
    for (final entry in rawAccounts.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty || value is! Map<Object?, Object?>) {
        continue;
      }

      final values = <String, String>{};
      for (final cookie in value.entries) {
        final name = cookie.key;
        final cookieValue = cookie.value;
        if (name is! String || cookieValue is! String) {
          continue;
        }
        values[name] = cookieValue;
      }

      final cookies = BilibiliCookies(values);
      if (cookies.isEmpty) {
        continue;
      }
      accounts[key] = cookies;
    }

    if (accounts.isEmpty) {
      return BilibiliCookieStoreState.empty;
    }

    final rawActive = decoded['activeAccountKey'];
    final activeKey = rawActive is String && accounts.containsKey(rawActive)
        ? rawActive
        : null;

    return BilibiliCookieStoreState(
      accounts: accounts,
      activeAccountKey: activeKey,
    );
  }

  static String _home(Map<String, String> environment) {
    final home = _firstNonEmpty(<String?>[
      environment['HOME'],
      environment['USERPROFILE'],
    ]);
    return home;
  }

  /// Joins [base] and [child] with `/`, normalizing Windows separators so the
  /// stored and displayed path looks the same everywhere.
  ///
  /// A UNC prefix (`\\server\share`) keeps backslashes, because that form is not
  /// interchangeable on Windows.
  static String _join(String base, String child) {
    if (base.startsWith(r'\\')) {
      final trimmed = base.endsWith(r'\')
          ? base.substring(0, base.length - 1)
          : base;
      return '$trimmed\\$child';
    }

    var normalized = base.replaceAll(r'\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return '$normalized/$child';
  }

  static String _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return '.';
  }

  /// Redacted representation: the path is shown, the payload never is.
  @override
  String toString() => 'PlainTextFileBilibiliCookieStore(${file.path})';
}
