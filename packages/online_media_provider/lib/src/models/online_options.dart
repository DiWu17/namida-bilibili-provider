/// Options for resolving metadata from a URL.
///
/// The MVP may ignore all fields, but they are part of the stable contract so
/// callers do not need a breaking API change later.
class OnlineMediaResolveOptions {
  const OnlineMediaResolveOptions({this.preferredPartIndex});

  /// Zero-based part index to prefer when a URL does not specify a part.
  final int? preferredPartIndex;
}

/// Options for resolving playback streams.
class OnlinePlaybackOptions {
  const OnlinePlaybackOptions({
    this.preferredVideoQualityId,
    this.preferredAudioQualityId,
    this.allowMuxedFallback = false,
  });

  final int? preferredVideoQualityId;
  final int? preferredAudioQualityId;
  final bool allowMuxedFallback;
}
