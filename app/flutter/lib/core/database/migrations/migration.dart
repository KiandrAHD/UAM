import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_exception.dart';

/// One ordered, deterministic schema migration.
///
/// The migration only receives a [DatabaseExecutor] so it runs identically
/// inside a transaction, on a fresh database, and in unit tests.
final class Migration {
  const Migration({
    required this.version,
    required this.description,
    required this.apply,
  });

  /// Target `PRAGMA user_version` after this migration succeeds.
  final int version;

  /// Human-readable summary used in diagnostics and tests.
  final String description;

  /// Forward-only migration body.
  final Future<void> Function(DatabaseExecutor db) apply;
}

/// Ordered registry of every migration this build ships.
///
/// The registry is the single source of truth for schema evolution; migrations
/// run in ascending [Migration.version] order and each one advances
/// `PRAGMA user_version` so a partially applied schema can never be reported as
/// current.
final class MigrationRegistry {
  MigrationRegistry(List<Migration> migrations)
    : migrations = List<Migration>.unmodifiable(
        List<Migration>.of(migrations)
          ..sort((a, b) => a.version.compareTo(b.version)),
      ) {
    final seen = <int>{};
    var previous = 0;
    for (final migration in this.migrations) {
      if (migration.version < 1) {
        throw ArgumentError.value(
          migration.version,
          'version',
          'Migration versions start at 1.',
        );
      }
      if (!seen.add(migration.version)) {
        throw ArgumentError.value(
          migration.version,
          'version',
          'Duplicate migration version.',
        );
      }
      if (migration.version <= previous) {
        throw ArgumentError(
          'Migrations must increase by version: ${migration.version} '
          'follows $previous.',
        );
      }
      previous = migration.version;
    }
  }

  final List<Migration> migrations;

  /// Highest schema version this build can produce.
  int get latestVersion => migrations.isEmpty ? 0 : migrations.last.version;

  /// Version 1 migration must exist so a fresh database is never empty.
  bool get startsAtOne =>
      migrations.isNotEmpty && migrations.first.version == 1;

  /// Migrations strictly newer than [currentVersion].
  List<Migration> pendingFrom(int currentVersion) => migrations
      .where((migration) => migration.version > currentVersion)
      .toList(growable: false);

  /// Apply every migration in `(from, to]` order.
  ///
  /// Must be called inside a transaction by the caller so a throw rolls back
  /// both the schema change and `PRAGMA user_version`.
  Future<void> migrate(
    DatabaseExecutor db, {
    required int from,
    required int to,
  }) async {
    if (to > latestVersion) {
      throw UamDataException.unsupportedSchema(
        found: to,
        supported: latestVersion,
      );
    }
    for (final migration in pendingFrom(from)) {
      if (migration.version > to) {
        break;
      }
      try {
        await migration.apply(db);
        await db.execute('PRAGMA user_version = ${migration.version}');
      } on UamDataException {
        rethrow;
      } catch (error) {
        throw UamDataException(
          UamDataErrorCode.migrationFailure,
          'Database migration ${migration.version} '
          '(${migration.description}) failed and was rolled back.',
          cause: error,
        );
      }
    }
  }
}
