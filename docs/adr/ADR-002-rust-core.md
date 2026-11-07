# ADR-002: Rust for the shared DSP and domain core

- **Status:** Accepted
- **Date:** 2026-11-07
- **Supersedes:** none

## Context

UAM needs a shared, deterministic, real-time-safe audio core that runs on five
platforms and is callable from Flutter. It must support sample-rate-aware
filter design, strict parameter validation, and eventually a lock-free
real-time audio callback.

Candidate cores: C, C++, Rust, or pure Dart.

- Pure Dart cannot meet the real-time requirement and would not be able to run
  inside a native audio callback.
- C/C++ offer performance but provide weaker memory-safety guarantees at the
  boundary where untrusted preset files are parsed.

## Decision

Implement the shared core in Rust as a Cargo workspace with narrow,
single-responsibility crates:

- `uam_domain` — platform-independent validated primitives.
- `uam_dsp` — filters, EQ chain, gain.
- `uam_preset` — portable preset schema, validation, import/export.
- `uam_ffi` — the sole crate that exposes a C ABI.

Dependency direction is enforced: `uam_dsp` does not depend on `uam_ffi`;
domain crates do not depend on Flutter; `#![forbid(unsafe_code)]` is set on
each non-FFI crate and `unsafe` is confined to `uam_ffi`.

Real-time rules recorded with this decision (to be enforced when a live backend
exists): no heap allocation, no blocking locks, no I/O, and no logging inside
the audio callback; parameters are prepared off-thread and handed over.

## Consequences

Positive:

- Memory safety at the parser and FFI boundary.
- A single DSP implementation shared by every platform.
- Deterministic, fast unit tests without a device.
- Crates can be reused by native mobile glue later.

Negative:

- A Rust toolchain and a Cargo workspace add build complexity.
- Real-time safety must be enforced by discipline and review, not by the type
  system alone.
- A new contributor must learn the C ABI boundary in addition to Dart.

## Evidence

- Workspace manifest `crates/Cargo.toml` with the four Phase 0 crates.
- `cargo fmt`, `cargo clippy --workspace --all-targets -- -D warnings`, and
  `cargo test --workspace` pass; 41 tests.
- Real RBJ biquad math in `crates/uam_dsp/src/filters/mod.rs` verified by
  magnitude-response tests.
- Allocation-free `Equalizer::process_interleaved` in
  `crates/uam_dsp/src/equalizer/mod.rs` documents the real-time intent.
