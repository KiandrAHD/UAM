import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_config.dart';

/// Resolves platform application directories.
///
/// The production implementation uses `path_provider`; tests inject a fake so
/// no platform channel is required and no developer machine path is hardcoded.
abstract interface class AppDirectoryProvider {
  /// Directory holding `uam.db`; created on demand.
  Future<Directory> databaseDirectory();

  /// Directory holding automatic pre-restore backups; created on demand.
  Future<Directory> backupDirectory();
}

/// Default provider backed by the OS application support directory.
final class PlatformAppDirectoryProvider implements AppDirectoryProvider {
  const PlatformAppDirectoryProvider();

  @override
  Future<Directory> databaseDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, DatabaseConfig.directoryName),
    );
    return _ensure(directory);
  }

  @override
  Future<Directory> backupDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, DatabaseConfig.directoryName, 'backups'),
    );
    return _ensure(directory);
  }

  Future<Directory> _ensure(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}

/// Resolves the SQLite factory used by the application.
///
/// UAM uses `sqflite_common_ffi`, which drives a real on-disk SQLite database on
/// Windows, Linux, macOS, Android, and iOS through the platform's SQLite library
/// (`sqlite3_flutter_libs` bundles it for mobile and desktop release builds).
/// This is a mature, widely used package that supports all five target
/// platforms with a single API, unlike the `sqflite` plugin, which omits
/// desktop.
abstract final class UamDatabaseFactory {
  static DatabaseFactory? _override;
  static bool _initialized = false;

  /// Force a specific factory (used by tests).
  static void overrideWith(DatabaseFactory factory) {
    _override = factory;
  }

  /// Restore the default factory after a test override.
  static void resetOverride() {
    _override = null;
  }

  /// The factory to use for opening databases.
  static DatabaseFactory resolve() {
    final override = _override;
    if (override != null) {
      return override;
    }
    if (!_initialized) {
      sqfliteFfiInit();
      _initialized = true;
    }
    return databaseFactoryFfi;
  }

  /// Isolate-free factory safe for widget tests.
  ///
  /// Widget tests run inside a fake asynchronous event loop. This factory
  /// avoids the background isolate used by the normal FFI factory while still
  /// operating on a real SQLite file.
  static DatabaseFactory resolveNoIsolate() {
    final override = _override;
    if (override != null) {
      return override;
    }
    if (!_initialized) {
      sqfliteFfiInit();
      _initialized = true;
    }
    return databaseFactoryFfiNoIsolate;
  }
}
