/// Stable identifier for a provider-specific online media item.
///
/// The [provider] field is deliberately provider-neutral. For Bilibili,
/// [id] is normally a BVID and [subId] normally carries a CID.
class OnlineMediaId {
  const OnlineMediaId({required this.provider, required this.id, this.subId})
    : assert(provider != ''),
      assert(id != '');

  /// Provider identifier, for example `bilibili`.
  final String provider;

  /// Main platform identifier.
  ///
  /// For Bilibili this is normally the BVID, but callers must not depend on
  /// that fact when talking to the provider-neutral API.
  final String id;

  /// Optional platform-specific child/part identifier.
  ///
  /// For Bilibili this can represent a CID.
  final String? subId;

  OnlineMediaId copyWith({String? provider, String? id, String? subId}) {
    return OnlineMediaId(
      provider: provider ?? this.provider,
      id: id ?? this.id,
      subId: subId ?? this.subId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OnlineMediaId &&
        other.provider == provider &&
        other.id == id &&
        other.subId == subId;
  }

  @override
  int get hashCode => Object.hash(provider, id, subId);

  @override
  String toString() {
    final suffix = subId == null ? '' : ':$subId';
    return 'OnlineMediaId($provider:$id$suffix)';
  }
}
