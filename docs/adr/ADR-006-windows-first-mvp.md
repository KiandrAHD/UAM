# ADR-006: Windows-first audio integration

- **Status:** Proposed (not verified on this host)
- **Date:** 2026-11-07
- **Supersedes:** none

## Context

UAM needs one working end-to-end audio vertical slice before expanding to other
platforms. Windows desktop is the proposed first target because it has the most
mature, best-documented system audio APIs (the WASAPI / MMDevice family) and
because it is the host available for development here.

The central open question is **processing scope**: which audio does UAM modify?

- `app_owned_stream` — only audio UAM itself plays. Always possible, limited
  value for an equalizer.
- `selected_stream` — one chosen application's stream (requires per-process
  loopback capture, Windows 10 2004+).
- `system_output` — the whole output device (requires loopback capture plus a
  virtual audio device for the processed output, or an APO).

System-wide output processing on Windows realistically requires either a
**virtual audio device driver** (kernel/driver work, signing, admin install) or
an **Audio Processing Object (APO)**. Neither is trivial to ship, and both have
distribution and security consequences.

## Decision (proposed)

Target the **selected-stream / loopback** approach first, and treat full
system-wide output processing as a later, explicitly-scoped effort:

1. Enumerate render endpoints through the MMDevice API (shared-mode).
2. Prototype loopback capture of a selected stream and re-render through the
   UAM DSP chain to a chosen output.
3. Report processing scope honestly at all times; Phase 0 reports
   `configuration_only`.
4. Do **not** promise system-wide processing until a virtual-device or APO path
   is implemented, signed, and tested.

This decision remains **Proposed** because Phase 0 could not run a live WASAPI
stream on this host (no Visual Studio C++ workload, so no desktop binary) and
could not yet compare a working loopback prototype against a virtual-device
prototype.

## Consequences

Positive:

- Builds on documented, stable Microsoft APIs.
- Honest scope avoids over-promising.
- Avoids driver signing and admin-install complexity in the first slice.

Negative:

- Selected-stream processing covers fewer use cases than system-wide EQ.
- Per-process loopback has Windows-version requirements and edge cases.
- A future system-wide feature will require a separate, heavier decision.

## Evidence

- Windows environment and blockers: `docs/platform/WINDOWS.md`.
- Real Rust access to the Windows audio device enumeration API was attempted;
  results are recorded in `docs/platform/WINDOWS.md` and, when the probe builds
  and runs, in `tools/audio_diagnostics/` output.
- OS-level endpoint inventory captured by
  `scripts/test/windows_endpoint_inventory.ps1` (machine-specific, gitignored at
  `docs/platform/windows-endpoint-inventory.txt`).
- Official sources: Microsoft WASAPI, loopback-recording, device-enumeration,
  and device-event documentation (linked in `docs/COMPATIBILITY.md`).
