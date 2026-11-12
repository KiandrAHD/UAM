import 'dart:io';

import 'package:uam/app/services/uam_services.dart';
import 'package:uam/features/backup/data/backup_service.dart';
import 'package:uam/features/presets/data/preset_exchange_service.dart';
import 'package:uam/features/presets/data/preset_repository.dart';
import 'package:uam/features/presets/data/sqlite_preset_repository.dart';
import 'package:uam/features/settings/data/settings_repository.dart';

import 'fake_preset_file_gateway.dart';

/// A real, isolated data stack for tests.
///
/// Every test gets its own temporary directory and its own SQLite file, so
/// tests never share state and never touch the developer's real `uam.db`.
/// Nothing here is an in-memory stub: the repositories, migrations, and
/// transactions under test are the production implementations.
final class TestDataStack {
  TestDataStack._({
    required this.services,
    required this.directory,
    required this.files,
  });

  final UamServices services;
  final Directory directory;
  final FakePresetFileGateway files;

  PresetRepository get presets => services.presets;
  SettingsRepository get settings => services.settings;
  PresetExchangeService get exchange => services.exchange;
  BackupService get backup => services.backup;

  /// Path of the SQLite file backing this stack.
  String get databasePath => services.database.path;

  static Future<TestDataStack> create({
    Directory? directory,
    FakePresetFileGateway? files,
  }) async {
    final root =
        directory ?? await Directory.systemTemp.createTemp('uam-test-');
    final gateway = files ?? FakePresetFileGateway();
    final services = await UamServices.forTesting(
      directory: root,
      fileGateway: gateway,
    );
    return TestDataStack._(services: services, directory: root, files: gateway);
  }

  /// Close the connection without deleting the data directory.
  ///
  /// Used to prove that data survives a process restart: the same file is
  /// reopened by [reopen].
  Future<TestDataStack> reopen() async {
    await services.dispose();
    final reopened = await UamServices.forTesting(
      directory: directory,
      fileGateway: files,
    );
    return TestDataStack._(
      services: reopened,
      directory: directory,
      files: files,
    );
  }

  /// Close the connection and delete the temporary directory.
  Future<void> dispose({bool deleteDirectory = true}) async {
    await services.dispose();
    if (deleteDirectory && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

/// Build a fresh SQLite repository over a new temporary database.
Future<({SqlitePresetRepository repository, TestDataStack stack})>
createPresetRepository() async {
  final stack = await TestDataStack.create();
  return (repository: stack.presets as SqlitePresetRepository, stack: stack);
}
