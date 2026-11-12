import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/database/database.dart';
import '../../core/database/database_config.dart';
import '../../core/database/database_exception.dart';
import '../../core/database/database_factory.dart';
import '../../features/backup/data/backup_service.dart';
import '../../features/presets/data/preset_exchange_service.dart';
import '../../features/presets/data/preset_repository.dart';
import '../../features/presets/data/sqlite_preset_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../platform/files/preset_file_gateway.dart';

/// Composition root for the local data subsystem.
///
/// Owns the single database connection and the repositories built on top of it.
/// Constructed once during `bootstrap()` and injected into the widget tree, so
/// there is no global mutable singleton and no silent in-memory fallback in
/// production: if initialization fails, the caller renders an explicit error
/// state instead of continuing with volatile storage.
final class UamServices {
  UamServices._({
    required this.database,
    required this.presets,
    required this.settings,
    required this.exchange,
    required this.backup,
    required this.fileGateway,
  });

  final UamDatabase database;
  final PresetRepository presets;
  final SettingsRepository settings;
  final PresetExchangeService exchange;
  final BackupService backup;
  final PresetFileGateway fileGateway;

  /// Open the production database and build the repositories.
  ///
  /// Throws [UamDataException] when the database cannot be opened, migrated, or
  /// verified. Callers must surface that failure instead of hiding it.
  static Future<UamServices> initialize({
    AppDirectoryProvider? directoryProvider,
    PresetFileGateway? fileGateway,
    DatabaseFactory? databaseFactory,
    DateTime Function()? clock,
  }) {
    return _build(
      directoryProvider:
          directoryProvider ?? const PlatformAppDirectoryProvider(),
      fileGateway: fileGateway ?? const NativePresetFileGateway(),
      databaseFactory: databaseFactory,
      clock: clock,
      inMemory: false,
    );
  }

  /// Build a services bundle backed by a temporary file database.
  ///
  /// Used by tests and by the integration smoke test. It is still a real
  /// on-disk SQLite database, never an in-memory stand-in.
  static Future<UamServices> forTesting({
    Directory? directory,
    PresetFileGateway? fileGateway,
    DatabaseFactory? databaseFactory,
    DateTime Function()? clock,
  }) async {
    final root =
        directory ?? await Directory.systemTemp.createTemp('uam-test-db-');
    return _build(
      directoryProvider: _TestDirectoryProvider(root),
      fileGateway: fileGateway ?? const _UnavailableFileGateway(),
      databaseFactory: databaseFactory,
      clock: clock,
      inMemory: false,
    );
  }

  /// Test-only in-memory services for widget tests.
  ///
  /// Production never calls this constructor. It uses the isolate-free FFI
  /// factory because Flutter widget tests run in a fake event loop. Repository
  /// and migration behaviour remains SQLite-backed.
  static Future<UamServices> inMemoryForWidgetTests({
    PresetFileGateway? fileGateway,
    DateTime Function()? clock,
  }) async {
    final root = await Directory.systemTemp.createTemp('uam-widget-db-');
    return _build(
      directoryProvider: _TestDirectoryProvider(root),
      fileGateway: fileGateway ?? const _UnavailableFileGateway(),
      databaseFactory: UamDatabaseFactory.resolveNoIsolate(),
      clock: clock,
      inMemory: true,
    );
  }

  static Future<UamServices> _build({
    required AppDirectoryProvider directoryProvider,
    required PresetFileGateway fileGateway,
    required DatabaseFactory? databaseFactory,
    required DateTime Function()? clock,
    required bool inMemory,
  }) async {
    final factory = databaseFactory ?? UamDatabaseFactory.resolve();
    final directory = await directoryProvider.databaseDirectory();
    final path = inMemory
        ? inMemoryDatabasePath
        : p.join(directory.path, DatabaseConfig.fileName);
    final UamDatabase database;
    try {
      database = await UamDatabase.open(
        factory: factory,
        path: path,
        isInMemory: inMemory,
      );
    } on UamDataException {
      rethrow;
    } catch (error) {
      throw UamDataException(
        UamDataErrorCode.databaseUnavailable,
        'The UAM local database could not be initialized.',
        cause: error,
      );
    }

    final presetRepository = SqlitePresetRepository(database, clock: clock);
    final settingsRepository = SqliteSettingsRepository(database, clock: clock);
    final exchange = PresetExchangeService(repository: presetRepository);
    final backup = BackupService(
      database: database,
      presets: presetRepository,
      settings: settingsRepository,
      directoryProvider: directoryProvider.backupDirectory,
      clock: clock,
    );
    return UamServices._(
      database: database,
      presets: presetRepository,
      settings: settingsRepository,
      exchange: exchange,
      backup: backup,
      fileGateway: fileGateway,
    );
  }

  Future<void> dispose() => database.close();
}

/// Directory provider rooted at an explicit directory (tests).
final class _TestDirectoryProvider implements AppDirectoryProvider {
  const _TestDirectoryProvider(this._root);

  final Directory _root;

  @override
  Future<Directory> databaseDirectory() => _ensure(_root);

  @override
  Future<Directory> backupDirectory() =>
      _ensure(Directory(p.join(_root.path, 'backups')));

  Future<Directory> _ensure(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}

/// File gateway used in tests unless one is injected. It never touches a
/// platform channel; tests that need files inject a fake.
final class _UnavailableFileGateway implements PresetFileGateway {
  const _UnavailableFileGateway();

  @override
  Future<PickedFile?> pickPresetFile() async => null;

  @override
  Future<PickedFile?> pickBackupFile() async => null;

  @override
  Future<String?> savePresetFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async => null;

  @override
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async => null;
}
