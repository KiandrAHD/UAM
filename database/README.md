# Database and portable preset fixtures

`database/schema/preset.schema.json` is the version-1 JSON Schema for `.uam-preset.json` files. The Rust `uam_preset` crate performs the runtime import/export validation and rejects oversized input, invalid JSON, unknown fields, unsupported schema versions, non-finite numeric values, invalid ranges, unsupported compatibility claims, duplicate tags, and invalid capability identifiers.

The database layer is intentionally not implemented in Phase 0. Do not put a live SQLite database in this directory. Future SQLite files belong in the platform application-data directory, not the repository.

## Security boundary

Preset files are untrusted data. Import must never execute content, load plugins, issue vendor commands, contain Bluetooth pairing secrets, or carry credentials. Use a size limit before parsing and validate both schema and semantic ranges. Export validates before writing.

Fixtures under `fixtures/sample-presets/` include valid round-trip examples and invalid rejection cases. The Rust integration tests enumerate these fixtures.
