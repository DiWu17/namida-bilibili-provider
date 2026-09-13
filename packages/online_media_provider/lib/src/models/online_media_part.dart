/// A selectable child part of an online media item.
///
/// For Bilibili, [id] is the CID and [index] is the 1-based page number.
class OnlineMediaPart {
  const OnlineMediaPart({
    required this.id,
    required this.title,
    required this.index,
    this.duration,
  }) : assert(id != ''),
       assert(index >= 0);

  /// Provider-specific part identifier. For Bilibili this is the CID.
  final String id;

  /// Human-readable part title.
  final String title;

  /// Zero-based index in a provider list.
  ///
  /// This is intentionally zero-based; user-facing `?p=` values are 1-based
  /// and are converted by the provider.
  final int index;

  /// Optional part duration. Bilibili exposes this on some responses.
  final Duration? duration;

  OnlineMediaPart copyWith({
    String? id,
    String? title,
    int? index,
    Duration? duration,
  }) {
    return OnlineMediaPart(
      id: id ?? this.id,
      title: title ?? this.title,
      index: index ?? this.index,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OnlineMediaPart &&
        other.id == id &&
        other.title == title &&
        other.index == index &&
        other.duration == duration;
  }

  @override
  int get hashCode => Object.hash(id, title, index, duration);

  @override
  String toString() => 'OnlineMediaPart($index:$title, id=$id)';
}
