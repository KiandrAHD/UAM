import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Transaction;

import '../../../core/database/app_setting_keys.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_config.dart';
import '../../../core/database/database_exception.dart';
import '../../../shared/models/preset_document.dart';
import '../domain/builtin_presets.dart';
import '../domain/preset_entry.dart';
import '../domain/preset_source.dart';
import 'preset_repository.dart';
import 'preset_row_mapper.dart';

/// SQLite-backed [PresetRepository].
///
/// Every multi-row write (preset + its filter cascade) runs inside a single
/// transaction, so a failure leaves the previous rows untouched.
final class SqlitePresetRepository implements PresetRepository {
  SqlitePresetRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final UamDatabase _database;
  final DateTime Function() _clock;

  /// Deterministic ordering: built-ins first, then alphabetically by name.
  static const String _order =
      'is_builtin DESC, name COLLATE NOCASE ASC, id ASC';

  String _now() => _clock().toUtc().toIso8601String();

  @override
  Future<List<PresetEntry>> getAll() async {
    final rows = await _database.query(PresetRowMapper.table, orderBy: _order);
    return _hydrate(rows);
  }

  @override
  Future<PresetEntry?> getById(String id) async {
    final rows = await _database.query(
      PresetRowMapper.table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final filters = await _filtersFor(id);
    return PresetRowMapper.toEntry(rows.first, filters);
  }

  @override
  Future<PresetEntry> create(
    PresetDocument document, {
    String? id,
    PresetSource source = PresetSource.user,
    bool isFavorite = false,
  }) async {
    _validate(document);
    final resolvedId = id ?? _generateId(source);
    if (await exists(resolvedId)) {
      throw UamDataException(
        UamDataErrorCode.duplicateId,
        'A preset with the identifier "$resolvedId" already exists.',
      );
    }
    final timestamp = _now();
    final row = PresetRowMapper.toRow(
      id: resolvedId,
      document: document,
      source: source,
      isFavorite: isFavorite,
      createdAt: document.metadata.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    final filters = PresetRowMapper.toFilterRows(
      presetId: resolvedId,
      bands: document.audio.bands,
    );
    await _database.transaction((Transaction txn) async {
      await txn.insert(PresetRowMapper.table, row);
      for (final filter in filters) {
        await txn.insert(PresetRowMapper.filterTable, filter);
      }
    });
    return PresetRowMapper.toEntry(row, filters);
  }

  @override
  Future<PresetEntry> update(String id, PresetDocument document) async {
    _validate(document);
    final existing = await _database.query(
      PresetRowMapper.table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (existing.isEmpty) {
      throw UamDataException(
        UamDataErrorCode.notFound,
        'Preset "$id" no longer exists.',
      );
    }
    if ((existing.first['is_builtin'] as int? ?? 0) != 0) {
      throw const UamDataException(
        UamDataErrorCode.constraintViolation,
        'Built-in presets cannot be overwritten.',
      );
    }
    final prev = PresetRowMapper.toEntry(existing.first, await _filtersFor(id));
    final timestamp = _now();
    final row = PresetRowMapper.toRow(
      id: id,
      document: document,
      source: prev.source,
      isFavorite: prev.isFavorite,
      createdAt: prev.createdAt ?? prev.document.metadata.createdAt,
      updatedAt: timestamp,
    );
    final filters = PresetRowMapper.toFilterRows(
      presetId: id,
      bands: document.audio.bands,
    );
    await _database.transaction((Transaction txn) async {
      await txn.update(
        PresetRowMapper.table,
        row,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        PresetRowMapper.filterTable,
        where: 'preset_id = ?',
        whereArgs: <Object?>[id],
      );
      for (final filter in filters) {
        await txn.insert(PresetRowMapper.filterTable, filter);
      }
    });
    return PresetRowMapper.toEntry(row, filters);
  }

  @override
  Future<bool> delete(String id) async {
    final existing = await _database.query(
      PresetRowMapper.table,
      columns: const <String>['is_builtin'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (existing.isEmpty) {
      return false;
    }
    if ((existing.first['is_builtin'] as int? ?? 0) != 0) {
      return false;
    }
    await _database.transaction((Transaction txn) async {
      await txn.delete(
        PresetRowMapper.filterTable,
        where: 'preset_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete(
        PresetRowMapper.table,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
    final active = await getActivePresetId();
    if (active == id) {
      await setActivePreset(null);
    }
    return true;
  }

  @override
  Future<bool> setFavorite(String id, bool favorite) async {
    final updated = await _database.update(
      PresetRowMapper.table,
      <String, Object?>{'is_favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return updated > 0;
  }

  @override
  Future<List<PresetEntry>> getFavorites() async {
    final rows = await _database.query(
      PresetRowMapper.table,
      where: 'is_favorite = 1',
      orderBy: _order,
    );
    return _hydrate(rows);
  }

  @override
  Future<List<PresetEntry>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return getAll();
    }
    final pattern = '%$normalized%';
    final rows = await _database.query(
      PresetRowMapper.table,
      where:
          'lower(name) LIKE ? OR lower(COALESCE(description, \'\')) LIKE ? '
          'OR lower(COALESCE(author, \'\')) LIKE ? '
          'OR lower(COALESCE(category, \'\')) LIKE ? '
          'OR lower(metadata_json) LIKE ?',
      whereArgs: <Object?>[pattern, pattern, pattern, pattern, pattern],
      orderBy: _order,
    );
    return _hydrate(rows);
  }

  @override
  Future<List<PresetEntry>> getByCategory(String category) async {
    final rows = await _database.query(
      PresetRowMapper.table,
      where: 'category = ?',
      whereArgs: <Object?>[category],
      orderBy: _order,
    );
    return _hydrate(rows);
  }

  @override
  Future<void> setActivePreset(String? presetId) async {
    if (presetId == null) {
      await _database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[AppSettingKeys.activePresetId],
      );
      return;
    }
    if (!await exists(presetId)) {
      throw UamDataException(
        UamDataErrorCode.notFound,
        'Cannot activate preset "$presetId": it does not exist.',
      );
    }
    await _writeSetting(AppSettingKeys.activePresetId, presetId);
  }

  @override
  Future<String?> getActivePresetId() async {
    final rows = await _database.query(
      'app_settings',
      columns: const <String>['value_json'],
      where: 'key = ?',
      whereArgs: <Object?>[AppSettingKeys.activePresetId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final raw = rows.first['value_json'];
    if (raw is! String) {
      return null;
    }
    String? id;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) {
        id = decoded;
      }
    } on FormatException {
      id = null;
    }
    if (id == null || id.isEmpty) {
      return null;
    }
    // Safe recovery: a dangling reference clears itself instead of crashing.
    if (!await exists(id)) {
      await setActivePreset(null);
      return null;
    }
    return id;
  }

  @override
  Future<bool> exists(String id) async {
    final rows = await _database.query(
      PresetRowMapper.table,
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> nameExists(String name, {String? excludeId}) async {
    final rows = await _database.query(
      PresetRowMapper.table,
      columns: const <String>['id'],
      where: excludeId == null
          ? 'name = ? COLLATE NOCASE'
          : 'name = ? COLLATE NOCASE AND id <> ?',
      whereArgs: excludeId == null
          ? <Object?>[name]
          : <Object?>[name, excludeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> ensureBuiltinsSeeded() async {
    final current = await _readSeedVersion();
    if (current >= DatabaseConfig.builtinSeedVersion) {
      return;
    }
    final builtins = builtInPresetEntries();
    final timestamp = _now();
    await _database.transaction((Transaction txn) async {
      for (final entry in builtins) {
        _validate(entry.document);
        final row = PresetRowMapper.toRow(
          id: entry.id,
          document: entry.document,
          source: PresetSource.builtin,
          isFavorite: entry.isFavorite,
          createdAt: entry.createdAt ?? entry.document.metadata.createdAt,
          updatedAt: timestamp,
        );
        // Preserve user favorites across re-seeding: is_favorite is not part of
        // the update set.
        await txn.rawInsert(
          '''
          INSERT INTO ${PresetRowMapper.table} (
            id, name, description, author, category, schema_version, source,
            is_builtin, is_favorite, preamp_db, created_at, updated_at,
            metadata_json, compatibility_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            description = excluded.description,
            author = excluded.author,
            category = excluded.category,
            schema_version = excluded.schema_version,
            source = 'builtin',
            is_builtin = 1,
            preamp_db = excluded.preamp_db,
            updated_at = excluded.updated_at,
            metadata_json = excluded.metadata_json,
            compatibility_json = excluded.compatibility_json
          ''',
          <Object?>[
            row['id'],
            row['name'],
            row['description'],
            row['author'],
            row['category'],
            row['schema_version'],
            row['source'],
            row['is_favorite'],
            row['preamp_db'],
            row['created_at'],
            row['updated_at'],
            row['metadata_json'],
            row['compatibility_json'],
          ],
        );
        await txn.delete(
          PresetRowMapper.filterTable,
          where: 'preset_id = ?',
          whereArgs: <Object?>[entry.id],
        );
        for (final filter in PresetRowMapper.toFilterRows(
          presetId: entry.id,
          bands: entry.document.audio.bands,
        )) {
          await txn.insert(PresetRowMapper.filterTable, filter);
        }
      }
      await txn.rawInsert(
        '''
        INSERT INTO app_settings (key, value_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
          value_json = excluded.value_json,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          AppSettingKeys.builtinSeedVersion,
          '${DatabaseConfig.builtinSeedVersion}',
          timestamp,
        ],
      );
    });
  }

  Future<int> _readSeedVersion() async {
    final rows = await _database.query(
      'app_settings',
      columns: const <String>['value_json'],
      where: 'key = ?',
      whereArgs: <Object?>[AppSettingKeys.builtinSeedVersion],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return int.tryParse(rows.first['value_json']?.toString() ?? '') ?? 0;
  }

  Future<void> _writeSetting(String key, Object? value) async {
    await _database.rawInsert(
      '''
      INSERT INTO app_settings (key, value_json, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value_json = excluded.value_json,
        updated_at = excluded.updated_at
      ''',
      <Object?>[key, _encodeSetting(value), _now()],
    );
  }

  Future<List<Map<String, Object?>>> _filtersFor(String presetId) {
    return _database.query(
      PresetRowMapper.filterTable,
      where: 'preset_id = ?',
      whereArgs: <Object?>[presetId],
      orderBy: 'position ASC',
    );
  }

  Future<List<PresetEntry>> _hydrate(List<Map<String, Object?>> rows) async {
    final entries = <PresetEntry>[];
    for (final row in rows) {
      final id = row['id'] as String? ?? '';
      entries.add(PresetRowMapper.toEntry(row, await _filtersFor(id)));
    }
    return List<PresetEntry>.unmodifiable(entries);
  }

  String _generateId(PresetSource source) {
    final micros = _clock().microsecondsSinceEpoch;
    return '${source.wireName}-$micros';
  }

  void _validate(PresetDocument document) {
    final result = PresetCodec.parse(document.toPrettyJson());
    if (!result.isValid) {
      throw UamDataException(
        UamDataErrorCode.invalidPreset,
        'The preset is not valid for schema version 1 and was not saved.',
        cause: result.errors.join('; '),
      );
    }
  }
}

String _encodeSetting(Object? value) => jsonEncode(value);
