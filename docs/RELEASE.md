# UAM Release Notes — Process

**Phase:** 0
**Status:** Process stub. No release artifacts exist yet.

## Release gates

A release only ships when:

1. Rust and Flutter CI pass on the release commit.
2. The platform compatibility matrix (`docs/COMPATIBILITY.md`) reflects the
   tested capabilities of that build.
3. Preset interchange tests pass on the release build.
4. No known critical audio-safety or data-loss defect is open.
5. Signed installers/packages are produced for each supported platform.
6. The dependency and license audit is current (`docs/DEPENDENCY_AUDIT.md`).
7. A privacy review is complete if any network or analytics feature shipped.

## Versioning

- Product version: semantic `MAJOR.MINOR.PATCH`.
- C ABI version: integer in `uam_domain::BRIDGE_ABI_VERSION`; increment on any
  incompatible exported-function or payload change.
- Preset schema version: integer in `database/schema/preset.schema.json`; bump
  when the portable format changes and document the migration.
- Keep the app version, core version, ABI version, and preset schema version
  distinct and documented.

## Artifacts

Do not commit release binaries, installers, signing keys, certificates, or
notarization credentials to the repository. Publish signed artifacts through the
release channel and record their checksums.

## Phase 0 status

No release is produced in Phase 0. The Windows desktop binary is blocked by the
missing Visual Studio C++ workload. See `docs/PHASE_0_REPORT.md` §13.