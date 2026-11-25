# Phase 4 readiness

Status: **PARTIALLY COMPLETE** — the implementation and automated verification
are in place; hardware acceptance and the packaged Windows launch are not.

## Verified

| Item | Evidence |
|---|---|
| Native WASAPI shared-mode render backend exists and renders | `cargo test -p uam_audio --test wasapi_render -- --nocapture` |
| Real endpoint enumeration and mix-format parsing | `crates/uam_audio/src/windows/device.rs`, engine tests |
| UAM-owned stream reaches a real default endpoint | WASAPI test: 14 976 frames, 30 callbacks, peak −40 dBFS |
| Rust DSP host with EQ/preamp/limiter, crossfade, bypass smoothing | `crates/uam_audio/src/host.rs` and its tests |
| Format conversion for f32 / PCM16 / PCM24 / PCM32 | `crates/uam_audio/src/format.rs` unit tests |
| Atomic metrics with no callback allocation or locking | `crates/uam_audio/src/metrics.rs`, allocation tests |
| Endpoint notifications and bounded recovery | `notification.rs`, `engine.rs` tests |
| FFI control API with panic containment | `crates/uam_ffi/src/engine.rs` tests |
| Cargo fmt, clippy (`-D warnings`), workspace tests | PASS on reference host |
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 190 tests |
| Flutter live engine controls, endpoints, EQ handoff, diagnostics | `test/unit/audio_engine_controller_test.dart`, `test/widget/diagnostics_test.dart` |
| Flutter Windows debug build and packaged DLL load | `flutter build windows --debug`; `uam_ffi.dll` observed loaded in the running process |

## Not verified

- Audible output on physical speakers or headphones (`NOT VERIFIED`).
- EQ audible change and measured frequency response on hardware (`NOT VERIFIED`).
- Endpoint switching and hot-unplug/replug on hardware (`NOT VERIFIED`).
- System-wide processing — not implemented by design and not claimed.

The Flutter Windows debug build now succeeds, and the packaged bundle copies and
loads `uam_ffi.dll` (verified by observing the module in the running process).
That verifies packaging, not audio acceptance.

## Conclusion

The vertical slice is implemented, wired end-to-end, and tested by automation
that touches a real Windows endpoint. Because the hardware acceptance criteria
and the packaged Windows launch were not exercised, Phase 4 must be reported as
**PARTIALLY COMPLETE**, never as complete.
