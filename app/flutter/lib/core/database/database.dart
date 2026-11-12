import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../logging/app_logger.dart';
import 'database_config.dart';
import 'database_exception.dart';
import 'migrations/migration.dart';
import 'migrations/migrations.dart';

/// A single, initialized connection to the UAM SQLite database.
///
/// Responsibilities:
/// * enforce foreign keys, a busy timeout, and WAL on file databases;
/// * run the migration registry transactionally;
/// * refuse to open a newer, unsupported schema;
/// * verify integrity after every open.
///
/// The class never opens a second conflicting connection: [open] memoizes by
/// path *and* passes `singleInstance: true` to the factory.
final class UamDatabase {
  UamDatabase._(this._db, {required this.path, required this.isInMemory});

  static final Map<String, Future<UamDatabase>> _openByPath =
      <String, Future<UamDatabase>>{};

  final Database _db;

  /// Absolute path of the database file, or `:memory:` for test databases.
  final String path;

  /// Whether this database lives only in memory.
  final bool isInMemory;

  /// Raw handle for repository code. Repositories must only use parameterized
  /// queries; callers must never interpolate user values into SQL.
  Database get handle => _db;

  bool _closed = false;

  bool get isClosed => _closed;

  /// Open (or reuse) the database at [path].
  ///
  /// [registry] defaults to the shipped [uamMigrations]; tests may supply a
  /// custom registry to exercise migration paths.
  static Future<UamDatabase> open({
    required DatabaseFactory factory,
    required String path,
    bool isInMemory = false,
    MigrationRegistry? registry,
  }) {
    return _openByPath.putIfAbsent(path, () async {
      try {
        return await _openInternal(
          factory: factory,
          path: path,
          isInMemory: isInMemory,
          registry: registry ?? uamMigrations,
        );
      } catch (_) {
        final _ = _openByPath.remove(path);
        rethrow;
      }
    });
  }

  static Future<UamDatabase> _openInternal({
    required DatabaseFactory factory,
    required String path,
    required bool isInMemory,
    required MigrationRegistry registry,
  }) async {
    if (!registry.startsAtOne) {
      throw const UamDataException(
        UamDataErrorCode.migrationFailure,
        'The migration registry is invalid: it must start at version 1.',
      );
    }
    final Database db;
    try {
      db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: false, singleInstance: true),
      );
    } catch (error) {
      throw UamDataException(
        UamDataErrorCode.databaseUnavailable,
        'The UAM database could not be opened.',
        cause: error,
      );
    }
    try {
      // Pragmas that cannot run inside a transaction are applied first.
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('PRAGMA busy_timeout = ${DatabaseConfig.busyTimeoutMs}');
      if (!isInMemory) {
        try {
          await db.execute('PRAGMA journal_mode = WAL');
        } catch (error) {
          AppLogger.warning(
            'WAL mode is unavailable on this filesystem; continuing '
            'with the default journal. (${error.runtimeType})',
          );
        }
      }

      final current = await _readUserVersion(db);
      final latest = registry.latestVersion;
      if (current > latest) {
        throw UamDataException.unsupportedSchema(
          found: current,
          supported: latest,
        );
      }
      if (current < latest) {
        await db.transaction((txn) async {
          // Re-read inside the transaction so concurrent openers cannot apply a
          // stale `from` version twice.
          final version = await _readUserVersion(txn);
          if (version > latest) {
            throw UamDataException.unsupportedSchema(
              found: version,
              supported: latest,
            );
          }
          await registry.migrate(txn, from: version, to: latest);
        });
      }

      final database = UamDatabase._(db, path: path, isInMemory: isInMemory);
      await database.verifyIntegrity();
      return database;
    } on UamDataException {
      await db.close();
      rethrow;
    } catch (error) {
      // Any raw SQLite failure during pragmas, version probing, or migration
      // means the file cannot be used. Wrap it so the UI shows a stable,
      // user-presentable error instead of a driver exception.
      await db.close();
      throw UamDataException(
        UamDataErrorCode.corruptDatabase,
        'The UAM database could not be read and was not opened.',
        cause: error,
      );
    }
  }

  static Future<int> _readUserVersion(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) {
      return 0;
    }
    final value = rows.first.values.first;
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  /// Current `PRAGMA user_version`.
  Future<int> schemaVersion() => _readUserVersion(_db);

  /// Run `PRAGMA integrity_check` and `PRAGMA foreign_key_check`.
  ///
  /// Throws [UamDataException] with [UamDataErrorCode.corruptDatabase] when the
  /// file is damaged rather than returning silently.
  Future<void> verifyIntegrity() async {
    try {
      final integrity = await _db.rawQuery('PRAGMA integrity_check');
      final ok =
          integrity.length == 1 &&
          integrity.first.values.first.toString().toLowerCase() == 'ok';
      if (!ok) {
        throw const UamDataException(
          UamDataErrorCode.corruptDatabase,
          'The UAM database failed its integrity check.',
        );
      }
      final foreignKeys = await _db.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        throw const UamDataException(
          UamDataErrorCode.corruptDatabase,
          'The UAM database contains foreign-key violations.',
        );
      }
    } on UamDataException {
      rethrow;
    } catch (error) {
      throw UamDataException(
        UamDataErrorCode.corruptDatabase,
        'The UAM database integrity check could not be completed.',
        cause: error,
      );
    }
  }

  /// Run [action] inside a single SQLite transaction.
  ///
  /// A throw rolls back every change, leaving the previous valid state intact.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      _db.transaction<T>(action);

  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return _db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    return _db.insert(table, values, conflictAlgorithm: conflictAlgorithm);
  }

  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    return _db.rawInsert(sql, arguments);
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    return _db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    return _db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> execute(String sql, [List<Object?>? arguments]) {
    return _db.execute(sql, arguments);
  }

  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _db.rawQuery(sql, arguments);
  }

  /// Drop every memoized connection. Test-only helper.
  static Future<void> resetOpenCache() async {
    final pending = List<Future<UamDatabase>>.of(_openByPath.values);
    _openByPath.clear();
    for (final future in pending) {
      try {
        final database = await future;
        if (!database.isClosed) {
          await database.handle.close();
        }
      } catch (_) {
        // A failed open has nothing to close.
      }
    }
  }

  /// Close the connection and drop it from the process-wide cache.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final _ = _openByPath.remove(path);
    await _db.close();
  }
}
