# Phase 4 implementation report — Windows audio integration

## Summary

Phase 4 adds the first working audio path in UAM. It is a **UAM-owned render
stream** on Windows: UAM generates audio, processes it through the Rust DSP
chain, and writes it to a real Windows endpoint through WASAPI shared mode.

UAM does **not** capture, intercept, or modify audio produced by other Windows
applications. System-wide equalization would require a virtual audio device, an
audio processing object (APO), or an equivalent integration, and none of those
exist in this build.

## What was implemented

### Rust core (`crates/uam_audio`)

- `backend.rs` — `AudioBackend` trait, `OpenRequest`, `RunningStream`,
  `DeviceSubscription`. Platform code sits behind this boundary.
- `device.rs` — normalized endpoint model (`id`, `displayName`, `transport`,
  `connectionState`, `isDefault`, `formatSummary`, `formatProvenance`),
  `DeviceListSnapshot`, `DeviceEvent`. Nothing is inferred from a device name.
- `config.rs` — `StreamFormat` (rate, channels, encoding, container/valid bits),
  `DspRequest` (preamp, bands, bypass, limiter), `TestToneConfig` with validated
  frequency/level limits.
- `format.rs` — boundary conversion between interleaved `f64` and IEEE float32,
  PCM16, packed PCM24, and PCM32, with clamping, non-finite containment, and
  counts reported in `FormatReport`.
- `tone.rs` — deterministic sine oscillator with a click-free amplitude ramp.
  Opt-in, conservative default level, never starts automatically.
- `host.rs` — real-time `DspHost`: owns `DspPipeline`, applies handed-off
  configuration at block boundaries, crossfades between prepared chains, applies
  bypass through an atomic flag with smoothing, and writes to the endpoint buffer.
- `metrics.rs` — atomic audio-thread counters (callback duration, peaks, limiter
  reduction, clipping, non-finite samples, glitches, underruns, deadline misses,
  restarts, disconnects, buffer/latency). Unobserved metrics are absent, not zeroed
  and invented.
- `engine.rs` — control-side state machine: device selection, start/stop,
  configuration, bypass, test tone, subscription, event draining, and bounded
  recovery preferring the original endpoint then the default endpoint.
- `stub.rs` — truthful fallback for platforms without a native adapter.

### Windows adapter (`crates/uam_audio/src/windows`)

- `com.rs` — scoped `CoInitializeEx`/`CoUninitialize` guard.
- `device.rs` — MMDevice enumeration of active `eRender` endpoints, friendly
  names, default marker, state, transport where exposed, and mix-format parsing.
- `notification.rs` — `IMMNotificationClient` forwarding add/remove/state/default/
  property events to a control-side channel.
- `render.rs` — event-driven shared-mode `IAudioClient` open/start/stop, producer
  thread using the endpoint event handle, buffer acquisition/release, and a
  stop signal that joins the thread before native handles are dropped.

### FFI (`crates/uam_ffi`)

`uam_audio_engine_*` exports create, destroy, status, enumerate, default device,
select device, configure, start, stop, set bypass, set test tone, device events,
and subscribe. Handles are opaque `u64`; every call returns one owned JSON
envelope (`{"ok":…,"error":…,"data":…}`) released by `uam_string_free`. Panics are
caught and converted to an `internal` error envelope. No audio buffer crosses the
ABI.

### Flutter

- `bridge/generated/uam_ffi_bindings.dart` — typed bindings for every engine
  symbol, with immediate freeing of returned strings.
- `platform/audio/audio_engine_gateway.dart` — gateway interface, JSON models
  (`AudioEndpoint`, `AudioEndpointList`, `AudioStreamFormat`, `AudioMetrics`,
  `AudioEngineSnapshot`), and envelope decoding with typed failures.
- `platform/audio/ffi_audio_engine_gateway.dart` — real implementation.
- `features/audio_engine/application/engine_controller.dart` — merges core
  metadata with live status, drives start/stop/bypass/test tone, debounces
  equalizer hand-off, drains endpoint events, and records session diagnostics.
- `features/device_manager/*` — `EngineDeviceRepository` enumerates real
  endpoints, resolves and persists selection, maps OS states, and reports rejected
  or vanished selections without pretending success.
- `features/diagnostics/presentation/diagnostics_page.dart` — live metrics or
  `Unavailable`, polled once per second.
- Dashboard, Device Manager, Equalizer, and Audio Engine pages now display real
  backend/endpoint/stream state instead of Phase 1 caveats.

## Verification

Run on the reference Windows host:

| Check | Result |
|---|---|
| `cargo fmt --all -- --check` | PASS |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | PASS |
| `cargo test --workspace --locked` | PASS (exit 0) |
| `cargo test -p uam_audio --test wasapi_render -- --nocapture` | PASS — 48 kHz / 2 ch / f32, 1056-frame buffer, 14 976 frames, 30 callbacks, avg 447 µs, max 1104 µs, peak output −40 dBFS |
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 190 tests |
| `flutter build windows --debug` | PASS — `build\windows\x64\runner\Debug\uam.exe` |
| Packaged `uam_ffi.dll` copied into the bundle | PASS — CMake install rule + locator search |
| Packaged `uam.exe` launch and native DLL load | PASS — `uam_ffi.dll` observed loaded in the running process |
| Audible output on physical speakers/headphones | NOT VERIFIED |
| EQ audible/frequency-response measurement on hardware | NOT VERIFIED |
| Endpoint hot-unplug / hot-plug on hardware | NOT VERIFIED |

The automated WASAPI test proves frames were rendered to a real default endpoint
and stayed below full scale. It does not prove a human heard the tone. The
packaged Windows build launched and loaded `uam_ffi.dll`, which proves packaging
and library resolution, not audible output.

## Scope, honesty, and limitations

- Processing path: UAM-generated diagnostic sine → DSP chain → WASAPI render →
  selected endpoint. Only UAM's own stream is processed.
- No virtual driver, no APO, no loopback capture, no processing of Spotify,
  browsers, games, or any other application.
- Physical hardware acceptance (audibility, EQ measurement, endpoint removal) is
  recorded as not verified and must not be reported as passed.
- The Windows debug build and packaged DLL were not exercised in this session.
