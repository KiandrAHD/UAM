import 'dart:convert';

import '../../../core/database/database.dart';
import '../../../core/logging/app_logger.dart';

/// Typed key/value persistence for application settings.
///
/// Values are stored as JSON so a single table can hold booleans, strings,
/// numbers, lists, and maps with stable keys.
abstract interface class SettingsRepository {
  /// Read [key] as `T`, or null when absent, malformed, or of another type.
  Future<T?> get<T>(String key);

  /// Store [value] under [key].
  Future<void> set<T>(String key, T value);

  /// Remove [key]; returns whether a row was deleted.
  Future<bool> remove(String key);

  /// Every readable setting. Malformed rows are skipped and logged.
  Future<Map<String, dynamic>> getAll();

  /// Remove user-facing appearance and general settings, restoring defaults.
  Future<void> resetToDefaults();
}

/// SQLite implementation of [SettingsRepository].
///
/// Malformed values never throw: they are logged and reported as absent so a
/// corrupted record cannot prevent application startup.
final class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final UamDatabase _database;
  final DateTime Function() _clock;

  static const String _table = 'app_settings';

  @override
  Future<T?> get<T>(String key) async {
    final rows = await _query(key);
    if (rows.isEmpty) {
      return null;
    }
    final raw = rows.first['value_json'];
    if (raw is! String) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      AppLogger.warning('Setting "$key" holds invalid JSON and was ignored.');
      return null;
    }
    if (decoded is T) {
      return decoded;
    }
    if (T == double && decoded is num) {
      return decoded.toDouble() as T;
    }
    AppLogger.warning('Setting "$key" has an unexpected type and was ignored.');
    return null;
  }

  @override
  Future<void> set<T>(String key, T value) async {
    await _database.rawInsert(
      '''
      INSERT INTO $_table (key, value_json, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value_json = excluded.value_json,
        updated_at = excluded.updated_at
      ''',
      <Object?>[key, jsonEncode(value), _now()],
    );
  }

  @override
  Future<bool> remove(String key) async {
    final deleted = await _database.delete(
      _table,
      where: 'key = ?',
      whereArgs: <Object?>[key],
    );
    return deleted > 0;
  }

  @override
  Future<Map<String, dynamic>> getAll() async {
    final rows = await _database.query(_table, orderBy: 'key ASC');
    final result = <String, dynamic>{};
    for (final row in rows) {
      final key = row['key'];
      final raw = row['value_json'];
      if (key is! String || raw is! String) {
        continue;
      }
      try {
        result[key] = jsonDecode(raw);
      } on FormatException {
        AppLogger.warning('Setting "$key" holds invalid JSON and was skipped.');
      }
    }
    return result;
  }

  @override
  Future<void> resetToDefaults() async {
    await _database.delete(
      _table,
      where: "key LIKE 'appearance.%' OR key LIKE 'general.%'",
    );
  }

  Future<List<Map<String, Object?>>> _query(String key) {
    return _database.query(
      _table,
      columns: const <String>['value_json'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
  }

  String _now() => _clock().toUtc().toIso8601String();
}
