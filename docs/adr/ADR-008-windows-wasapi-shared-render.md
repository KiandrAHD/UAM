# ADR-008: Windows WASAPI shared-mode render backend

- Status: Accepted for Phase 4 application-owned audio
- Date: 2026-11-25

## Context

UAM needs real Windows render output without claiming system-wide interception. WASAPI shared mode provides endpoint discovery, Windows mix-format negotiation, event-driven buffers, and normal coexistence with other applications. Exclusive mode would add device ownership and format restrictions without helping the first vertical slice.

## Decision

Use Windows Core Audio MMDevice and WASAPI APIs through the `windows` 0.62 crate. `uam_audio::windows` is the only platform adapter. It:

- enumerates active `eRender` endpoints and reads friendly names, state, default endpoint, and mix format;
- opens an event-driven shared-mode `IAudioClient`;
- runs a dedicated producer thread that renders an owned diagnostic tone through `DspHost` and writes the endpoint buffer;
- registers `IMMNotificationClient` for endpoint changes;
- stops and joins the producer before native handles are released;
- exposes normalized models through `AudioBackend`.

DSP uses `f64` interleaved samples internally. Boundary conversion supports WASAPI float32 and PCM 16/24/32 formats. Configuration crosses to the callback through bounded channels; bypass uses atomics and smoothing.

## Consequences

Positive: native endpoint identity, real audible output, no virtual driver, no Dart audio callback, bounded real-time path, truthful scope reporting.

Negative: current slice processes UAM-owned generated test audio only. It does not process YouTube, Spotify, games, browsers, or arbitrary system output. System-wide processing needs a virtual audio driver, APO, or equivalent future component. Physical endpoint removal/recovery requires Windows hardware testing.

## Evidence

- `crates/uam_audio/src/windows/device.rs`
- `crates/uam_audio/src/windows/render.rs`
- `crates/uam_audio/src/windows/notification.rs`
- `crates/uam_audio/tests/wasapi_render.rs`
- `cargo test --workspace --locked`
- `cargo clippy --workspace --all-targets --locked -- -D warnings`
