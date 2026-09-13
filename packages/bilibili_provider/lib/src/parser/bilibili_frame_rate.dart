/// Parses Bilibili DASH frame-rate strings.
///
/// Examples:
/// - `"60"` -> `60.0`
/// - `"30"` -> `30.0`
/// - `"30000/1001"` -> approximately `29.97`
/// - invalid/empty values -> `null`
double? parseFrameRate(String? value) {
  if (value == null) {
    return null;
  }

  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  if (trimmed.contains('/')) {
    final parts = trimmed.split('/');
    if (parts.length != 2) {
      return null;
    }

    final numerator = double.tryParse(parts[0].trim());
    final denominator = double.tryParse(parts[1].trim());
    if (numerator == null ||
        denominator == null ||
        denominator == 0 ||
        numerator < 0 ||
        denominator < 0) {
      return null;
    }

    final result = numerator / denominator;
    if (!result.isFinite || result <= 0) {
      return null;
    }
    return result;
  }

  final result = double.tryParse(trimmed);
  if (result == null || !result.isFinite || result <= 0) {
    return null;
  }
  return result;
}
