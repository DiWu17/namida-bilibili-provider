import 'online_media_id.dart';
import 'online_media_part.dart';

/// Provider-neutral metadata for an online video/media item.
class OnlineMedia {
  OnlineMedia({
    required this.id,
    required this.title,
    this.artist,
    this.thumbnail,
    this.duration,
    this.description,
    List<OnlineMediaPart> parts = const <OnlineMediaPart>[],
    Map<String, Object?> extra = const <String, Object?>{},
  }) : parts = List<OnlineMediaPart>.unmodifiable(parts),
       extra = Map<String, Object?>.unmodifiable(extra);

  final OnlineMediaId id;

  /// Media title.
  final String title;

  /// Uploader/artist/channel name. For Bilibili this is the UP name.
  final String? artist;

  final Uri? thumbnail;

  final Duration? duration;

  final String? description;

  final List<OnlineMediaPart> parts;

  /// Provider-specific metadata that is intentionally not part of the core
  /// contract. Adapters should avoid depending on this map.
  final Map<String, Object?> extra;

  /// Returns the part that matches [subId], or the first part when [subId] is
  /// null and the media has at least one part.
  OnlineMediaPart? partForSubId(String? subId) {
    if (parts.isEmpty) {
      return null;
    }
    if (subId == null) {
      return parts.first;
    }
    for (final part in parts) {
      if (part.id == subId) {
        return part;
      }
    }
    return null;
  }

  @override
  String toString() => 'OnlineMedia(id: $id, title: $title)';
}
