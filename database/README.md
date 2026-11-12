# Database and portable preset fixtures

`database/schema/preset.schema.json` is the version-1 JSON Schema for `.uam-preset.json` files. The Rust `uam_preset` crate performs the runtime import/export validation and rejects oversized input, invalid JSON, unknown fields, unsupported schema versions, non-finite numeric values, invalid ranges, unsupported compatibility claims, duplicate tags, and invalid capability identifiers.

Since Phase 3, the Flutter application also validates against this contract with a Dart codec (`app/flutter/lib/features/presets/data/preset_codec.dart`), which is the in-app authority for import/export in the current phase. The schema file remains the contract of record; both implementations must agree, and the fixture suite is exercised by `python scripts/test/validate_presets.py` in CI.

The live SQLite database is **not** stored in this directory. It lives in the
platform application-data directory (`<application-support>/UAM/uam.db`) and is
created by the Dart migrations in
`app/flutter/lib/core/database/migrations/`. See
[`docs/DATABASE_DESIGN.md`](../docs/DATABASE_DESIGN.md) and
[`docs/DATABASE_MIGRATIONS.md`](../docs/DATABASE_MIGRATIONS.md).

## Security boundary

Preset files are untrusted data. Import must never execute content, load plugins, issue vendor commands, contain Bluetooth pairing secrets, or carry credentials. Use a size limit before parsing and validate both schema and semantic ranges. Export validates before writing.

Fixtures under `fixtures/sample-presets/` include valid round-trip examples and invalid rejection cases. The Rust integration tests enumerate these fixtures.
