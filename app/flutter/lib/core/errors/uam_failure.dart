/// Stable failure categories used across application and bridge boundaries.
enum UamFailureCode {
  /// The native library could not be located or loaded.
  bridgeUnavailable,

  /// The native library lacked an expected symbol or returned a null payload.
  bridgeProtocol,

  /// The payload was not the expected JSON shape.
  invalidResponse,

  /// The operation is not implemented in this phase.
  notImplemented,

  /// An unexpected, non-categorised failure occurred.
  unknown,
}

/// Typed application failure with a safe, user-presentable message.
///
/// Messages must never contain secrets, raw audio, private file paths, or
/// device identifiers.
final class UamFailure {
  const UamFailure({required this.code, required this.message, this.detail});

  /// Machine-readable category.
  final UamFailureCode code;

  /// Safe summary suitable for display.
  final String message;

  /// Optional diagnostic detail that contains no sensitive data.
  final String? detail;

  @override
  String toString() => 'UamFailure(${code.name}): $message';
}
