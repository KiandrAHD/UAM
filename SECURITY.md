# Security Policy

## Supported versions

The repository is in Phase 0 technical validation. Security fixes should target the default branch and the latest release tag once releases exist.

## Reporting a vulnerability

Do not publish exploitable details in a public issue. Report privately through the repository's configured GitHub security contact or the project maintainer. Include:

- Affected commit or version.
- Reproduction steps and a minimal safe proof of concept.
- Impact and required permissions.
- Logs or screenshots with secrets, personal paths, device identifiers, and credentials removed.

## Import and preset safety

`.uam-preset.json` files are untrusted input. UAM must reject oversized, malformed, unknown-field, unsupported-version, non-finite, and out-of-range documents. Presets must never execute commands, load code, carry credentials, contain Bluetooth pairing secrets, or send arbitrary vendor protocol frames.

## Privacy boundary

Do not commit audio samples, private exported presets, live SQLite databases, user device inventories, pairing keys, credentials, signing keys, or logs containing personal paths or identifiers.
