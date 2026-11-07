# ADR-005: Capability-based hardware controls

- **Status:** Accepted (principle); implementations remain unproven
- **Date:** 2026-11-07
- **Supersedes:** none

## Context

Operating systems and Bluetooth profiles expose hardware features
inconsistently. On Windows, macOS, Linux, Android, and iOS:

- Audio-endpoint enumeration is not Bluetooth scanning.
- Bluetooth pairing does not grant access to noise cancelling, transparency, or
  touch controls.
- Battery level, codec, and firmware information are available on some devices
  and not others.
- Vendor features frequently require undocumented protocols.

Advertising a feature as available because a device is connected would be
dishonest and would produce unreliable UX.

## Decision

Every hardware feature is modeled as an explicit **capability** that is
discovered at runtime and carries provenance. A capability has:

- `featureId` — a stable identifier (for example `hardware.anc`).
- `supported` — boolean.
- `availability` — `available | unavailable | permission_required |
  unsupported | unknown`.
- `controlMode` — `read_only | read_write | not_applicable`.
- `source` — `os_api | standard_profile | vendor_adapter | inferred`.
- `reason` — optional human-readable explanation.
- `adapterId` and adapter version where relevant.

Rules:

- The UI must never show a control as operational unless a capability reports
  `available` with a non-`inferred` source.
- Vendor-specific adapters must be isolated, independently testable, and
  allowlisted; UAM must never send undocumented Bluetooth commands by default.
- A capability that cannot be verified is reported as `unknown`, not assumed
  available.
- Audio processing scope (see ADR-006) is a capability in the same sense and
  must be reported honestly.

This ADR fixes the **principle and the data shape**. No hardware adapter is
implemented in Phase 0; the adapter registry and device model arrive in Phase 5.

## Consequences

Positive:

- Users can trust what the app shows.
- Unsupported states are first-class and testable.
- Vendor integrations can be added without weakening the common model.

Negative:

- More UI states to design (unavailable, permission required, unknown).
- Capability discovery costs runtime work and platform-specific code.

## Evidence

- Architecture rules: `docs/Architecture.md` §6 and §11.
- Processing-scope contract implemented as a typed closed enum that throws on
  unknown wire values: `app/flutter/lib/platform/audio/audio_processing_scope.dart`.
- Phase 0 engine payload reports `audioProcessingScope: "configuration_only"`
  and never claims an attached audio path:
  `crates/uam_ffi/src/api/mod.rs`.
