# UAM Privacy Notes

**Phase:** 0
**Status:** Product policy foundation; implementation follows in later phases.

## Defaults

- UAM is local-first and works without an account or network connection.
- Presets, settings, aliases, and future local profiles remain on the user's
  device by default.
- UAM does not silently upload presets, diagnostics, audio, or device data.
- Portable preset export is user-initiated and uses `.uam-preset.json` files.
- Audio samples are not recorded by default.

## Diagnostics

Diagnostics should contain only the minimum information needed to troubleshoot:
OS/build information, backend name, sample rate, channel layout, processing
scope, capability status, and safe error codes.

Do not collect by default:

- Raw audio.
- Private file paths.
- Bluetooth pairing keys or OS secrets.
- Stable hardware identifiers unless required and clearly disclosed.
- Credentials, tokens, or vendor protocol frames.

The Windows endpoint inventory and audio diagnostics tool can print local device
names. Their output is machine-specific and must not be committed or uploaded
without deliberate user action.

## Imported files

Preset files are untrusted input. UAM validates size, UTF-8, JSON structure,
schema version, fields, ranges, and compatibility before saving. Presets cannot
contain executable content, shell commands, credentials, pairing secrets, or
vendor frames.

## Future network services

An optional community catalogue or update service, if introduced, must be:

- Opt-in.
- Separate from local preset creation and use.
- Documented before release.
- Explicit about data collected and retention.
- Disabled by default when technically feasible.

See `SECURITY.md`, `docs/Architecture.md`, and ADR-004 for related boundaries.