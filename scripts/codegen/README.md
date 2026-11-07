# Code generation

Phase 0 uses a deliberately small hand-reviewed C ABI between `crates/uam_ffi` and `app/flutter/lib/bridge/generated/uam_ffi_bindings.dart`. The binding shim is kept in the generated directory to enforce a hard boundary between low-level ABI code and application code.

`flutter_rust_bridge` was evaluated at `2.14.0-beta.2` (MIT). It was not adopted for Phase 0 because the current release is a beta, code generation adds a toolchain step that was not installed on the validation host, and a three-function control ABI is smaller than the generated surface. See `docs/adr/ADR-003-flutter-rust-interop.md`.

If a later phase adopts generated bindings, generated Dart files belong here and must not be edited by hand. Do not place application logic in this directory.

Do not expose audio sample buffers through ordinary Dart method calls.