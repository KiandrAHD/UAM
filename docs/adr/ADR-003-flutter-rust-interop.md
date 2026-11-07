# ADR-003: Flutter–Rust interoperability via a narrow C ABI and Dart FFI

- **Status:** Accepted (Phase 0)
- **Date:** 2026-11-07
- **Supersedes:** none

## Context

The Flutter UI and the Rust core must exchange data. The two candidates were:

1. `flutter_rust_bridge` — generates typed bindings and reduces manual FFI
   boilerplate. Evaluated version: `2.14.0-beta.2` (MIT).
2. A hand-written narrow C ABI (`extern "C"`) called from Dart `dart:ffi`.

Additional hard constraint: real-time audio frames must never cross the Dart
boundary. The audio callback must live entirely in native code.

## Decision

For Phase 0, use a **narrow hand-written C ABI** plus Dart `dart:ffi`:

- The C surface is tiny: `uam_abi_version()`, `uam_get_engine_info()`
  (returns an owned UTF-8 JSON `char*`), and `uam_string_free()`.
- All structured data crosses the boundary as versioned UTF-8 JSON, decoded and
  type-checked on the Dart side into typed objects.
- Ownership is explicit: Rust allocates with `CString::into_raw`; Dart must call
  `uam_string_free` exactly once. ABI version mismatches are rejected by the
  app.
- `flutter_rust_bridge` is **deferred, not rejected**. It remains a candidate
  for a later phase if the control surface grows large enough to justify
  codegen. Reasons for deferral: it is currently a beta release, and it adds a
  Dart codegen toolchain and its own dependency graph that Phase 0 does not
  need.

The audio path is unaffected by the bridge choice: it stays native.

## Consequences

Positive:

- Minimal dependency surface; no codegen step required to build.
- Memory ownership and the wire contract are explicit and testable.
- JSON payloads are trivially logged and versioned.
- The ABI can be frozen with an explicit version number.

Negative:

- Hand-written bindings do not offer compile-time type safety across the
  boundary; the Dart layer must validate every field (it does).
- JSON adds marshalling overhead, which is irrelevant for the low-frequency
  control path but rules this out for per-sample data.
- Every new capability needs matching hand-written Rust and Dart code.

## Evidence

- Rust exports in `crates/uam_ffi/src/lib.rs`; the file confines all `unsafe` to
  pointer ownership transfer.
- Dart bindings in `app/flutter/lib/bridge/generated/uam_ffi_bindings.dart`;
  typed facade in `app/flutter/lib/bridge/rust_api.dart` (validates the JSON,
  checks the ABI version).
- Live proof: `app/flutter/test/integration/rust_bridge_test.dart` loads
  `crates/target/debug/uam_ffi.dll` and receives `Universe Audio Management`,
  core `0.1.0`, ABI `1`.
- `flutter_rust_bridge` version and license recorded in
  `docs/DEPENDENCY_AUDIT.md`.
