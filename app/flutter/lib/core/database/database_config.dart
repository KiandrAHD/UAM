/// Database location and format constants.
///
/// No machine-specific path is hardcoded. The directory is always resolved at
/// runtime through the platform application-support directory, and tests inject
/// their own temporary directory.
abstract final class DatabaseConfig {
  /// Database file name created inside [directoryName].
  static const String fileName = 'uam.db';

  /// Application data subdirectory created under the platform support root.
  static const String directoryName = 'UAM';

  /// Current schema version understood by this build.
  ///
  /// This value is authoritative through `PRAGMA user_version`; there is no
  /// second migration registry table that could disagree with it.
  static const int schemaVersion = 1;

  /// Milliseconds a writer waits for a lock before reporting `SQLITE_BUSY`.
  static const int busyTimeoutMs = 5000;

  /// Built-in seed policy version. Increase to re-apply updated built-ins
  /// without duplicating or overwriting user data.
  static const int builtinSeedVersion = 1;
}
