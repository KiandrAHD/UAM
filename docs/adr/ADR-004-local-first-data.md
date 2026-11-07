# ADR-004: Local-first data and portable preset interchange

- **Status:** Accepted (Phase 0)
- **Date:** 2026-11-07
- **Supersedes:** none

## Context

UAM must be usable offline and must not require an account. Users need to create
presets locally and share them as files with other users. Imported files are
untrusted input.

Two decisions were needed:

1. Where user data lives and whether a network is required.
2. The preset interchange format and its validation boundary.

## Decision

**Local-first.** All user data is stored on the local machine, in the
platform's application-support directory, and the application works fully
offline. No account, no automatic upload, no silent networking. Backup and
sharing are always user-initiated.

**Portable preset interchange.** Presets are exchanged as versioned UTF-8 JSON
files named `*.uam-preset.json` with:

- A stable top-level identifier `"format": "uam-preset"`.
- A required `schemaVersion` (currently `1`).
- Device-independent audio settings by default (metadata, preamp, ordered EQ
  bands).
- Explicit units (Hz, dB) and documented numeric ranges.
- **No** executable content, scripts, shell commands, credentials, pairing
  secrets, or raw vendor protocol frames.

Unknown fields are rejected so future additions require an explicit
schema-version decision. Validation is enforced twice:

- JSON Schema (`database/schema/preset.schema.json`) for external tooling and
  documentation.
- Rust semantic validation (`crates/uam_preset/src/validation.rs`) so the core
  is protected regardless of how a value was constructed.

Storage engine choice (SQLite, and Dart access via `drift` or a Rust-owned
persistence boundary) is **deferred to Phase 3** and is not part of this
decision. Phase 0 ships the schema, validation, and round-trip code only.

## Consequences

Positive:

- Works offline; privacy by default.
- Sharing needs only a file, never a service.
- The strict schema is cheap to fuzz and to validate.
- Two independent validators reduce the chance of a bad preset reaching the
  audio core.

Negative:

- Device-independent presets cannot capture hardware-specific curves; those
  require a future capability-tagged extension and a schema-version bump.
- Rejecting unknown fields means forward-compatibility requires discipline: any
  new field is a versioning event.

## Evidence

- Schema: `database/schema/preset.schema.json`.
- Rust types and strict (unknown-field-rejecting) deserialization:
  `crates/uam_preset/src/schema.rs`, `import.rs`, `export.rs`.
- Semantic validation and bounds: `crates/uam_preset/src/validation.rs`.
- Fixtures: 3 valid and 8 invalid files in
  `database/fixtures/sample-presets/`.
- `python scripts/test/validate_presets.py` reports `Valid fixtures: 3`,
  `Invalid fixtures: 8`, `PASSED`.
- Rust fixture round-trip/rejection tests in
  `crates/uam_preset/tests/preset_tests.rs`.
