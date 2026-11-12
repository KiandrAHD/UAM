/// Stable, user-presentable failure categories for the local data subsystem.
///
/// These mirror the categories documented in `docs/Architecture.md` §9 and are
/// deliberately independent from raw `sqflite` errors so the UI never renders an
/// SQL statement or a stack trace.
enum UamDataErrorCode {
  /// SQLite could not be located, opened, or initialized.
  databaseUnavailable,

  /// A migration failed and was rolled back.
  migrationFailure,

  /// The on-disk schema is newer than this build understands.
  unsupportedSchema,

  /// A unique or foreign-key constraint was violated.
  constraintViolation,

  /// A record with the same identity already exists.
  duplicateId,

  /// A record does not exist.
  notFound,

  /// The database file failed an integrity check.
  corruptDatabase,

  /// A preset document failed schema or DSP-boundary validation.
  invalidPreset,

  /// A file could not be found or read.
  fileNotFound,

  /// The operating system denied access to a path.
  permissionDenied,

  /// A portable import/export or backup container was malformed.
  corruptData,

  /// A JSON serialization or deserialization step failed.
  serialization,

  /// The user cancelled an operation.
  cancelled,

  /// An unclassified data-layer failure occurred.
  unknown,
}

/// Typed exception raised by the local data subsystem.
///
/// [message] is safe to display. [cause] holds the underlying error for
/// diagnostics and must never be shown verbatim to the user.
final class UamDataException implements Exception {
  const UamDataException(this.code, this.message, {this.cause});

  final UamDataErrorCode code;
  final String message;
  final Object? cause;

  /// Convenience constructor for "this build cannot read a newer schema".
  factory UamDataException.unsupportedSchema({
    required int found,
    required int supported,
  }) {
    return UamDataException(
      UamDataErrorCode.unsupportedSchema,
      'This database was created by a newer UAM version '
      '(schema $found, this build supports up to $supported).',
    );
  }

  @override
  String toString() => 'UamDataException(${code.name}): $message';
}
