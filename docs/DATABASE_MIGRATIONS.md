# Database Migrations

## Current state

The shipped registry contains migration **1**: `migration_001_initial.dart`. Its target is `PRAGMA user_version = 1`.

## Rules

1. Add one forward-only `migration_00N_description.dart` file.
2. Append it to `lib/core/database/migrations/migrations.dart`.
3. Use the next integer version. Do not edit an already shipped migration.
4. Keep schema/data changes inside the migration transaction.
5. Do not introduce a second schema-version table. `PRAGMA user_version` is authoritative.
6. Add migration, reopen, rollback, and data-preservation tests before release.

`MigrationRegistry` sorts migrations, rejects duplicate/non-positive versions, runs pending versions in order, and only advances `user_version` after each migration body succeeds. `UamDatabase.open` wraps the registry in a SQLite transaction; failed DDL/DML and its version update roll back together.

## Upgrade behavior

- Fresh database: applies every migration from 0 to the latest version.
- Existing older database: applies only pending migrations.
- Database newer than this app: refused with `unsupportedSchema`; no downgrade is attempted.
- Failure: database closes, cache entry is removed, and a typed `migrationFailure` reaches bootstrap.

## Version 1 contents

Creates `presets`, `preset_filters`, `app_settings`, `profiles`, `device_aliases`, and query indexes. See `DATABASE_DESIGN.md` for fields and constraints.

## Operational notes

Back up user data before shipping a migration that removes or rewrites data. SQLite migrations in this repository are forward-only; restoration is from a `.uam-backup` package, not an automatic down migration.

## Test evidence

`flutter test test/unit/database_migration_test.dart` verifies first open, reopen, extra migration advancement, failed-migration rollback, future-schema rejection, transaction rollback, foreign keys/cascades, and corrupt-file handling.
