# Phase 4 implementation report

## Current implementation

Rust `uam_audio` now contains platform-independent stream vocabulary, format conversion, real-time DSP host, test-tone source, atomic metrics, lifecycle engine, and truthful unsupported-platform fallback. Windows adapter uses native MMDevice/WASAPI shared-mode event-driven rendering.

Windows endpoint enumeration returns real active render endpoints, endpoint IDs, friendly names, default marker, state, transport where exposed, and mix format on selection. Endpoint notification callback forwards add/remove/state/default/property events through a control-side channel.

Render lifecycle owns `IAudioClient`, `IAudioRenderClient`, event handles, and producer thread. Stop joins thread before handle release. Device invalidation is surfaced through metrics and bounded recovery.

The DSP host generates sine test audio, processes `DspPipeline`, supports preamp/EQ/limiter, smooth bypass, click-free pipeline transition, finite-output containment, and format conversion. Metrics are atomic and callback-safe.

FFI exposes opaque engine handles and JSON envelopes for create/destroy/status/enumerate/default/select/configure/start/stop/bypass/test tone/events/subscribe.

## Verification

- `cargo fmt --all -- --check`: PASS
- `cargo clippy --workspace --all-targets --locked -- -D warnings`: PASS
- `cargo test --workspace --locked`: PASS on current Windows environment
- Real WASAPI test: PASS; 48 kHz, stereo, float32, 1056-frame buffer, 14,976 frames, 30 callbacks, peak -40 dBFS. Audible physical output was not independently documented by this automated test.
- Flutter native audio UI/bridge integration: not complete in this working tree. Existing Flutter screens still use Phase 1 metadata-only controllers.

## Scope and limitations

Implemented path processes UAM-owned generated test tone only. No system-wide capture, interception, virtual driver, APO, or processing of third-party applications exists. Flutter still needs control-path wiring for the new FFI exports and real device/diagnostics views. Physical device removal, switching, EQ audibility, and Flutter Windows build remain not verified here.
