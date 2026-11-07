# Dependency and License Audit — Phase 0

**Date:** 2026-11-07
**Project license:** MIT (see `LICENSE`)
**Scope:** everything actually used by the Phase 0 build, plus the main
candidate that was evaluated and deferred.

> Method: direct manifests (`crates/*/Cargo.toml`, `app/flutter/pubspec.yaml`,
> `tools/audio_diagnostics/Cargo.toml`) and lockfiles (`crates/Cargo.lock`,
> `app/flutter/pubspec.lock`). Licenses read from crate/package metadata.
> `cargo audit` / `cargo deny` were not installed, so this is a license and
> provenance audit, not a vulnerability scan.

## 1. Rust workspace — direct dependencies

| Crate | Version | Used by | License |
|---|---|---|---|
| `serde` | `1.0.229` | `uam_preset`, `uam_ffi` | MIT OR Apache-2.0 |
| `serde_json` | `1.0.154` | `uam_preset`, `uam_ffi` | MIT OR Apache-2.0 |
| `uam_domain` | `0.1.0` (path) | `uam_dsp`, `uam_ffi` | MIT (this project) |
| `uam_dsp` | `0.1.0` (path) | `uam_preset` | MIT (this project) |
| `uam_preset` | `0.1.0` (path) | `uam_ffi` | MIT (this project) |

`uam_domain` and `uam_dsp` have no third-party dependencies. The DSP core is
therefore dependency-free and auditable.

## 2. Rust workspace — transitive dependencies (from `crates/Cargo.lock`)

| Crate | Version | License | Pulled in by |
|---|---|---|---|
| `itoa` | `1.0.18` | MIT OR Apache-2.0 | `serde_json` |
| `memchr` | `2.8.3` | Unlicense OR MIT | `serde_json` |
| `proc-macro2` | `1.0.107` | MIT OR Apache-2.0 | `serde_derive` |
| `quote` | `1.0.47` | MIT OR Apache-2.0 | `serde_derive` |
| `serde_core` | `1.0.229` | MIT OR Apache-2.0 | `serde` |
| `serde_derive` | `1.0.229` | MIT OR Apache-2.0 | `serde` |
| `syn` | `3.0.9` | MIT OR Apache-2.0 | `serde_derive` |
| `unicode-ident` | `1.0.27` | (MIT OR Apache-2.0) AND Unicode-3.0 | `proc-macro2`, `syn` |
| `zmij` | `1.0.23` | MIT | `serde_json` |

All are permissive and compatible with an MIT-licensed project. `unicode-ident`
carries the Unicode-3.0 license in addition to MIT/Apache-2.0; it is a build-time
proc-macro dependency and is permissive.

## 3. Rust diagnostics tool — direct dependencies

`tools/audio_diagnostics/` is a standalone Cargo project, not part of the
`crates/` workspace.

| Crate | Version | License | Purpose |
|---|---|---|---|
| `windows` | `0.62.2` | MIT OR Apache-2.0 | Win32 MMDevice / WASAPI bindings |
| `windows-core` | `0.62.2` | MIT OR Apache-2.0 | Transitive |
| `windows-link` | `0.2.1` | MIT OR Apache-2.0 | Transitive |
| `windows-strings` | `0.5.1` | MIT OR Apache-2.0 | Transitive |
| `windows-result` | `0.4.1` | MIT OR Apache-2.0 | Transitive |
| `windows-threading` | `0.2.1` | MIT OR Apache-2.0 | Transitive |
| `windows-implement` | `0.60.2` | MIT OR Apache-2.0 | Transitive (macro) |
| `windows-interface` | `0.59.3` | MIT OR Apache-2.0 | Transitive (macro) |
| `windows-collections` | `0.3.2` | MIT OR Apache-2.0 | Transitive |
| `windows-numerics` | `0.3.1` | MIT OR Apache-2.0 | Transitive |
| `windows-future` | `0.3.2` | MIT OR Apache-2.0 | Transitive |
| `proc-macro2` / `quote` / `syn` / `unicode-ident` | see §2 | permissive | Macro support |

The `windows` crate is Windows-only and is used only by the diagnostics tool,
so it does not affect the cross-platform core dependency graph.

## 4. Flutter / Dart — direct dependencies

| Package | Resolved version | License | Purpose |
|---|---|---|---|
| `ffi` | `2.2.0` | BSD-3-Clause | `dart:ffi` helpers (`Utf8`, etc.) |
| `flutter` | SDK | BSD-3-Clause | UI framework |
| `flutter_lints` | `6.0.0` | BSD-3-Clause | Analyzer lint set (dev) |
| `flutter_test` | SDK | BSD-3-Clause | Test framework (dev) |
| `integration_test` | SDK | BSD-3-Clause | Integration test driver (dev) |

Third-party (`pub.dev`) packages are limited to `ffi` and `flutter_lints`; the
rest of the transitive packages are Flutter SDK packages or Dart-team packages
(`async`, `collection`, `meta`, `path`, `test_api`, `vm_service`, and so on),
all BSD-3-Clause. Full resolution is pinned in `app/flutter/pubspec.lock`.

## 5. Development tooling (not shipped)

| Tool | Version | License |
|---|---|---|
| Python | `3.11` | PSF-2.0 |
| `jsonschema` (Python) | `4.26` | MIT |
| CMake | `4.4.4` | BSD-3-Clause |
| Ninja | `1.13.2` | Apache-2.0 |
| Git | `2.52.0` | GPL-2.0 (tool only) |
| Rust toolchain (`rustc`/`cargo`) | `1.99.1` | MIT OR Apache-2.0 |
| Flutter SDK | `3.44.6` | BSD-3-Clause |

## 6. Evaluated but not adopted

| Candidate | Version | License | Decision |
|---|---|---|---|
| `flutter_rust_bridge` | `2.14.0-beta.2` | MIT | Deferred. Beta; adds a Dart codegen toolchain. Phase 0 uses a narrow C ABI + Dart FFI instead (ADR-003). |

No audio, Bluetooth, database, or state-management runtime dependency has been
locked yet. `drift`, `riverpod`, and platform audio libraries remain candidates
for later phases and must pass this audit before adoption.

## 7. License compatibility summary

- All adopted dependencies are permissive (MIT, Apache-2.0, BSD-3-Clause,
  Unlicense, Unicode-3.0, PSF-2.0).
- No copyleft (GPL/AGPL/LGPL) dependency is linked into the shipped
  application. Git is GPL-2.0 but is a build tool only, not distributed with
  UAM.
- The project can remain MIT-licensed and distribute binaries under the current
  dependency set.

## 8. Gaps and next actions

- [ ] Install and run `cargo audit` (or `cargo deny check`) in CI.
- [ ] Run `dart pub outdated` and review advisory data in CI.
- [ ] Re-audit when adding SQLite/Drift, state management, and platform audio
      crates.
- [ ] Record SBOM at release time (Phase 9).
- [ ] Confirm the license of every new dependency before merge (policy in
      `docs/Tech_Stack.md` §13).