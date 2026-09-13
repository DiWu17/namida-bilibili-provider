import 'dart:collection';

/// Immutable, redaction-safe container for Bilibili authentication cookies.
///
/// Security contract (enforced by tests in this package):
///
/// - [toString] and [redactedSummary] never contain a cookie value, so the type
///   is safe to interpolate into logs and diagnostics;
/// - cookie values are only exposed through [values] / [cookieHeader], which
///   are the explicit request-building surfaces;
/// - no exception in this package ever embeds a cookie value.
///
/// Instance is created by the caller from user-supplied or login-flow cookies.
/// This package never reads cookies from a browser profile or any other
/// implicit source.
class BilibiliCookies {
  /// Creates a jar from already-parsed [values].
  ///
  /// Empty names and empty values are dropped. Insertion order is preserved so
  /// the emitted `Cookie` header is deterministic.
  BilibiliCookies([Map<String, String> values = const <String, String>{}])
    : values = UnmodifiableMapView<String, String>(_sanitize(values));

  /// Parses a `Cookie` request header such as `a=1; b=2`.
  ///
  /// Attribute tokens that only appear in `Set-Cookie` responses (`Path`,
  /// `Domain`, `Expires`, `HttpOnly`, ...) are ignored, so pasting a
  /// `Set-Cookie` string does not create bogus cookies.
  factory BilibiliCookies.parse(String? rawCookieHeader) {
    if (rawCookieHeader == null || rawCookieHeader.trim().isEmpty) {
      return BilibiliCookies.empty;
    }

    final parsed = LinkedHashMap<String, String>();
    for (final part in rawCookieHeader.split(';')) {
      final pair = _splitPair(part);
      if (pair == null) {
        continue;
      }
      if (_attributeNames.contains(pair.$1.toLowerCase())) {
        continue;
      }
      parsed[pair.$1] = pair.$2;
    }
    return BilibiliCookies(parsed);
  }

  /// Parses whatever a user pasted into a sign-in form.
  ///
  /// Accepts the shapes people actually paste:
  ///
  /// - a raw `Cookie` header: `SESSDATA=...; bili_jct=...`;
  /// - the same value with a leading label: `Cookie: SESSDATA=...; ...`;
  /// - one pair per line (DevTools "copy value" and multi-line selections);
  /// - a value quoted out of a JSON string;
  /// - whole `Set-Cookie` lines, whose attributes are discarded.
  ///
  /// The input is never logged, and the result is still subject to the normal
  /// rules in [BilibiliCookies.parse]: only `name=value` pairs with non-empty
  /// parts survive.
  factory BilibiliCookies.fromUserInput(String raw) {
    var normalized = raw.trim();

    if (normalized.toLowerCase().startsWith('cookie:')) {
      normalized = normalized.substring('cookie:'.length).trim();
    }

    if (normalized.length >= 2) {
      final first = normalized[0];
      final last = normalized[normalized.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        normalized = normalized.substring(1, normalized.length - 1);
      }
    }

    // Line breaks and tabs separate cookies when they are pasted one per line.
    normalized = normalized.replaceAll(RegExp(r'[\r\n\t]+'), '; ');

    return BilibiliCookies.parse(normalized);
  }

  /// Merges a sequence of `Set-Cookie` response headers into one jar.
  ///
  /// Only the first `name=value` pair of each header is used; attributes are
  /// discarded. Intended for a future explicit login flow.
  factory BilibiliCookies.fromSetCookieHeaders(
    Iterable<String> setCookieHeaders,
  ) {
    final parsed = LinkedHashMap<String, String>();
    for (final header in setCookieHeaders) {
      final pair = _splitPair(header.split(';').first);
      if (pair == null) {
        continue;
      }
      parsed[pair.$1] = pair.$2;
    }
    return BilibiliCookies(parsed);
  }

  /// An empty jar, equivalent to anonymous access.
  static final BilibiliCookies empty = BilibiliCookies();

  /// Session token cookie name.
  static const String sessDataName = 'SESSDATA';

  /// csrf token cookie name, sent as the `csrf` field on write requests.
  static const String csrfName = 'bili_jct';

  /// Numeric user id cookie name.
  static const String userIdName = 'DedeUserID';

  /// Secondary user id cookie name.
  static const String userIdCheckName = 'DedeUserID__ckMd5';

  /// Session id cookie name.
  static const String sessionIdName = 'sid';

  static const Set<String> _attributeNames = <String>{
    'path',
    'domain',
    'expires',
    'max-age',
    'httponly',
    'secure',
    'samesite',
    'version',
    'comment',
    'priority',
  };

  /// Cookie name/value pairs, in insertion order.
  final Map<String, String> values;

  bool get isEmpty => values.isEmpty;

  bool get isNotEmpty => values.isNotEmpty;

  int get length => values.length;

  /// Returns the raw value for [name], or null.
  ///
  /// Callers must not log the result.
  String? operator [](String name) => values[name];

  /// `SESSDATA` value, or null. Never log this value.
  String? get sessData => values[sessDataName];

  /// `bili_jct` csrf token, or null. Never log this value.
  String? get csrfToken => values[csrfName];

  /// Numeric mid from `DedeUserID`, or null when absent/malformed.
  int? get userId {
    final raw = values[userIdName];
    if (raw == null) {
      return null;
    }
    return int.tryParse(raw);
  }

  /// Whether a session token is present. This says nothing about whether the
  /// token is still accepted by the server; use the account layer to check.
  bool get hasSessionToken {
    final token = sessData;
    return token != null && token.isNotEmpty;
  }

  /// Whether a csrf token is present, which write requests require.
  bool get hasCsrfToken {
    final token = csrfToken;
    return token != null && token.isNotEmpty;
  }

  /// Serializes to a `Cookie` request header value.
  ///
  /// The result is a credential. It must only be handed to an HTTP client.
  String get cookieHeader {
    return values.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Returns a new jar where [overrides] replace or add individual cookies.
  BilibiliCookies withValues(Map<String, String> overrides) {
    return BilibiliCookies(<String, String>{...values, ...overrides});
  }

  /// Returns a new jar that also contains every cookie from [other].
  ///
  /// Cookies in [other] win on conflict, which matches server-side refresh
  /// semantics.
  BilibiliCookies merge(BilibiliCookies other) {
    if (other.isEmpty) {
      return this;
    }
    return BilibiliCookies(<String, String>{...values, ...other.values});
  }

  /// Returns a new jar without the named cookies.
  BilibiliCookies without(Iterable<String> names) {
    final removed = names.toSet();
    return BilibiliCookies(<String, String>{
      for (final entry in values.entries)
        if (!removed.contains(entry.key)) entry.key: entry.value,
    });
  }

  /// Safe diagnostic summary. Contains no cookie values.
  String get redactedSummary => '<redacted: $length cookie(s)>';

  static LinkedHashMap<String, String> _sanitize(Map<String, String> values) {
    final sanitized = LinkedHashMap<String, String>();
    for (final entry in values.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (name.isEmpty || value.isEmpty) {
        continue;
      }
      sanitized[name] = value;
    }
    return sanitized;
  }

  static (String, String)? _splitPair(String raw) {
    final separator = raw.indexOf('=');
    if (separator <= 0) {
      return null;
    }
    final name = raw.substring(0, separator).trim();
    final value = raw.substring(separator + 1).trim();
    if (name.isEmpty || value.isEmpty) {
      return null;
    }
    return (name, value);
  }

  @override
  bool operator ==(Object other) {
    if (other is! BilibiliCookies || other.values.length != values.length) {
      return false;
    }
    for (final entry in values.entries) {
      if (other.values[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll(values.entries.map((e) => Object.hash(e.key, e.value)));

  /// Redacted representation. Never contains a cookie value.
  @override
  String toString() {
    final names = values.keys.join(', ');
    return 'BilibiliCookies(<redacted: $length cookie(s)> names: [$names])';
  }
}
