import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migration.dart';

/// Version 1 — initial UAM local schema.
///
/// Normalization strategy (see `docs/DATABASE_DESIGN.md`):
/// * Columns hold the fields UAM queries or indexes (identity, name, author,
///   description, category, flags, timestamps, schema version, source, preamp).
/// * `metadata_json` holds only the non-columnar metadata (`createdAt`, `tags`).
/// * `compatibility_json` holds the portable compatibility contract.
/// * `preset_filters` holds the ordered equalizer cascade.
///
/// The full portable `.uam-preset.json` document is reconstructed from these
/// rows on export, so the database never stores an unvalidated JSON blob as the
/// sole source of truth and export round-trips exactly.
final Migration migration001Initial = Migration(
  version: 1,
  description: 'Initial schema: presets, filters, settings, profiles, aliases',
  apply: (DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        author TEXT,
        category TEXT,
        schema_version INTEGER NOT NULL,
        source TEXT NOT NULL CHECK (source IN ('builtin', 'imported', 'user')),
        is_builtin INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        preamp_db REAL NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        metadata_json TEXT NOT NULL,
        compatibility_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE preset_filters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        preset_id TEXT NOT NULL
          REFERENCES presets(id) ON DELETE CASCADE ON UPDATE CASCADE,
        position INTEGER NOT NULL,
        filter_type TEXT NOT NULL
          CHECK (filter_type IN ('peaking', 'low_shelf', 'high_shelf')),
        frequency_hz REAL NOT NULL,
        gain_db REAL NOT NULL,
        q_factor REAL NOT NULL,
        UNIQUE (preset_id, position)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        active_preset_id TEXT
          REFERENCES presets(id) ON DELETE SET NULL ON UPDATE CASCADE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE device_aliases (
        id TEXT PRIMARY KEY,
        platform TEXT NOT NULL,
        device_identifier TEXT NOT NULL,
        alias TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (platform, device_identifier)
      )
    ''');

    // Indexes for the actual query patterns: source/built-in/binary filtering,
    // category facets, favorite listing, filter lookup by parent preset, and
    // device-alias resolution.
    await db.execute('CREATE INDEX idx_presets_source ON presets(source)');
    await db.execute(
      'CREATE INDEX idx_presets_is_builtin ON presets(is_builtin)',
    );
    await db.execute(
      'CREATE INDEX idx_presets_is_favorite ON presets(is_favorite)',
    );
    await db.execute('CREATE INDEX idx_presets_category ON presets(category)');
    await db.execute('CREATE INDEX idx_presets_name ON presets(name)');
    await db.execute(
      'CREATE INDEX idx_preset_filters_preset ON preset_filters(preset_id)',
    );
    await db.execute(
      'CREATE INDEX idx_device_aliases_lookup '
      'ON device_aliases(platform, device_identifier)',
    );
  },
);
