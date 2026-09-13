/// Formats a media duration the way the player UI shows it.
///
/// Returns `unknown` for a null duration and `m:ss` / `h:mm:ss` otherwise.
String formatDuration(Duration? duration) {
  if (duration == null) {
    return 'unknown';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
