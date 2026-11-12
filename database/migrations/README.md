# Database migrations

The runtime SQLite schema is owned by the Flutter data layer, not by files in
this directory. As of Phase 3 the authoritative migration list is
`app/flutter/lib/core/database/migrations/` (`migration.dart`,
`migration_001_initial.dart`, `migrations.dart`), and the schema version is read
from `PRAGMA user_version`. See [`docs/DATABASE_MIGRATIONS.md`](../../docs/DATABASE_MIGRATIONS.md)
for the full policy and failure behavior.

This directory is kept as a documentation placeholder for the sequential
migration naming convention:

- Migration identifiers use a sequential numeric prefix, for example
  `0001_initial.sql`.
- An already-applied migration must never be edited; add a new migration instead.
  A released migration that produced schema version `N` must keep producing
  exactly schema version `N`.
- Do not add a live database file here. SQLite files belong in the platform
  application-data directory (`<application-support>/UAM/uam.db`), and are
  ignored by Git (`*.db`, `*.sqlite`, `*.sqlite3`).

If a SQL mirror of a migration is ever added here for review purposes, it must
be generated from the Dart migration and never become a second source of truth.
