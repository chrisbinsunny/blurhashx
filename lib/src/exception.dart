/// Base exception thrown when BlurHash encoding, decoding, or validation fails.
class BlurHashException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// The invalid hash string or relevant context, if applicable.
  final String? invalidHash;

  /// Creates a [BlurHashException] with the provided [message] and optional [invalidHash].
  const BlurHashException(this.message, [this.invalidHash]);

  @override
  String toString() {
    if (invalidHash != null) {
      return 'BlurHashException: $message (hash: "$invalidHash")';
    }
    return 'BlurHashException: $message';
  }
}

/// Validation result returned when checking a BlurHash string.
class BlurHashValidationResult {
  /// Whether the string is a valid BlurHash.
  final bool isValid;

  /// An error reason if [isValid] is `false`, or `null` if valid.
  final String? errorReason;

  /// Creates a [BlurHashValidationResult].
  const BlurHashValidationResult._({required this.isValid, this.errorReason});

  /// Represents a successful validation.
  static const BlurHashValidationResult valid =
      BlurHashValidationResult._(isValid: true);

  /// Creates a failed validation result with the given [errorReason].
  factory BlurHashValidationResult.invalid(String errorReason) =>
      BlurHashValidationResult._(isValid: false, errorReason: errorReason);

  @override
  String toString() => isValid
      ? 'BlurHashValidationResult(valid)'
      : 'BlurHashValidationResult(invalid: $errorReason)';
}
