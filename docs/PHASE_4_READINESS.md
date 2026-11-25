# Phase 4 readiness

Status: **PARTIALLY COMPLETE**.

## Verified

- Native WASAPI shared render backend exists.
- Real endpoint enumeration and mix-format parsing exist.
- UAM-owned generated tone reaches real default endpoint in `wasapi_render`.
- Rust DSP host, EQ/preamp/limiter path, bypass handoff, format conversion, lifecycle, metrics, notification adapter, and FFI control API exist.
- Rust format, DSP, lifecycle, bridge, allocation, and integration tests pass.

## Not verified or incomplete

- Flutter now binds audio-engine FFI symbols, drives live lifecycle controls, enumerates/selects endpoints, sends debounced EQ changes, and displays live native metrics or `Unavailable`.
- Targeted controller/widget tests cover lifecycle, device selection, persistence, removal, rejection, bypass, diagnostics, and unavailable backend.
- Manual EQ audible/frequency-response verification not recorded.
- Endpoint switching/removal/reappearance hardware scenarios not recorded.
- Flutter Windows debug build and packaged native library validation not run.
- System-wide processing not implemented.

Critical hardware acceptance criteria remain unverified. Status: PARTIALLY COMPLETE, not COMPLETE.
