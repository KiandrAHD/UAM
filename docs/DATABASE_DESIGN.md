# Database Design

## Scope

Phase 3 stores UAM local state in SQLite through `sqflite_common_ffi` on every target platform. The production database is `<application-support>/UAM/uam.db`; tests inject isolated temporary directories.

## Connection policy

- One memoized connection per absolute path with `singleInstance: true`.
- `PRAGMA foreign_keys = ON`, `busy_timeout = 5000`, and WAL for file databases.
- `PRAGMA user_version` is the only schema-version source.
- Open verifies `integrity_check` and `foreign_key_check`.
- Initialization failures surface as a bootstrap error screen. Production has no in-memory fallback.

## Schema version 1

| Table | Purpose | Main constraints |
|---|---|---|
| `presets` | Preset identity, queryable metadata, source, flags, and audio preamp | `id` primary key; source enum; normalized fields plus JSON metadata/compatibility |
| `preset_filters` | Ordered EQ filter cascade | FK to `presets`, cascade delete/update, unique `(preset_id, position)` |
| `app_settings` | Namespaced JSON values | `key` primary key |
| `profiles` | Reserved profile metadata | optional FK active preset, `ON DELETE SET NULL` |
| `device_aliases` | Future platform device aliases | unique `(platform, device_identifier)` |

`metadata_json` contains non-query metadata (`createdAt`, `tags`). `compatibility_json` keeps portable compatibility metadata. Export reconstructs a validated schema-v1 document from normalized rows.

## Preset source and protection

`source` is `builtin`, `imported`, or `user`. Built-ins use stable IDs, are seeded idempotently, preserve favorites on reseed, and cannot be updated or deleted.

## Setting keys

- `appearance.themeMode`
- `appearance.reducedMotion`
- `general.launchAtStartup`
- `preset.activeId`
- `backup.lastBackupAt`
- `backup.lastBackupPath`
- `internal.builtinSeedVersion` (excluded from backups)

Settings are JSON encoded. Malformed values are logged and treated as absent rather than blocking startup.

## Indexes

Version 1 indexes source, built-in/favorite flags, category, name, filter parent ID, and device-alias lookup. These match the current library filtering and hydration paths.

## Validation evidence

`test/unit/database_migration_test.dart` covers initial schema creation, WAL, FK enforcement/cascade, reopen, unsupported schemas, migration rollback, integrity failure mapping, transactions, and connection reuse.
