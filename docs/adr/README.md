# Architecture Decision Records (ADR)

This directory records the architectural decisions made for Universe Audio
Management (UAM). Each record is immutable once it reaches `Accepted`; a
superseding decision is recorded as a new ADR that references the old one.

## Format

Every ADR uses these sections:

- **Status** — `Proposed`, `Accepted`, `Deprecated`, or `Superseded by ADR-NNN`.
- **Context** — the forces that require a decision.
- **Decision** — what was chosen.
- **Consequences** — positive and negative results.
- **Evidence** — Phase 0 artifacts, tests, or sources that support the record.

## Index

| ADR | Title | Status |
|---|---|---|
| [ADR-001](ADR-001-flutter-ui.md) | Flutter for the shared user interface | Accepted |
| [ADR-002](ADR-002-rust-core.md) | Rust for the shared DSP and domain core | Accepted |
| [ADR-003](ADR-003-flutter-rust-interop.md) | Flutter–Rust interoperability via a narrow C ABI and Dart FFI | Accepted (Phase 0) |
| [ADR-004](ADR-004-local-first-data.md) | Local-first data and portable preset interchange | Accepted (Phase 0) |
| [ADR-005](ADR-005-capability-based-controls.md) | Capability-based hardware controls | Accepted (principle) |
| [ADR-006](ADR-006-windows-first-mvp.md) | Windows-first audio integration | Proposed |

## Naming note

`docs/Structure_File.md` proposes an earlier set of ADR filenames
(`ADR-003-local-first-storage`, `ADR-004-preset-interchange`). The task that
drove Phase 0 requested an interop decision and a local-first data decision.
This directory keeps the Structure_File convention (`ADR-NNN-short-description`)
but uses the decision titles below. The mapping is:

| Structure_File proposal | This directory |
|---|---|
| ADR-001 Flutter UI | ADR-001 Flutter UI |
| ADR-002 Rust core | ADR-002 Rust core |
| ADR-003 Local-first storage | ADR-003 Flutter–Rust interop |
| ADR-004 Preset interchange | ADR-004 Local-first data (includes interchange) |
| ADR-005 Capability-based controls | ADR-005 Capability-based controls |
| ADR-006 Windows-first MVP | ADR-006 Windows-first audio integration |

`Structure_File.md` also lists a possible ADR-007 (real-time audio thread
safety). That topic is folded into ADR-002 and ADR-006 in this pass because the
real-time path is not yet implemented; a dedicated ADR will be added in the
phase that introduces a live audio backend.

## Status discipline

An ADR is `Accepted` only when its decision is backed by working code,
tests, or directly cited authoritative documentation. Platform capabilities
that Phase 0 could not execute on this host remain `Proposed`. In particular,
system-wide audio processing and Windows stream routing are **not** accepted in
Phase 0.
