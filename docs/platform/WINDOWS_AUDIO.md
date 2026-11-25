# Windows audio integration

## Scope

UAM currently owns and renders diagnostic audio to one selected Windows output endpoint. Signal path:

`generated sine tone -> DspHost -> DSP filters/preamp/limiter -> boundary format conversion -> WASAPI shared render -> selected endpoint`

This is **application-owned audio processing**. UAM does not capture or modify audio produced by other Windows applications. System-wide EQ remains future work requiring a virtual audio driver, APO, or equivalent Windows integration.

## Backend

Backend: native Windows Core Audio through `windows` crate 0.62. MMDevice enumerates active `eRender` endpoints. WASAPI shared mode uses the endpoint mix format and event-driven callbacks. Endpoint notifications use `IMMNotificationClient`.

## Lifecycle

1. Create engine.
2. Enumerate endpoints.
3. Select endpoint; read mix format.
4. Build DSP pipeline off callback thread.
5. Open event-driven `IAudioClient`.
6. Start producer thread.
7. Apply DSP updates through bounded handoff; bypass uses atomic state with smoothing.
8. Stop signal wakes producer; producer stops client and exits.
9. Join thread; close events and release COM resources.

Device invalidation ends producer safely. Control-side status observes failure and attempts bounded recovery, preferring original endpoint then default endpoint.

## Real-time rules

Audio callback allocates no buffers, takes no mutex, performs no file/network I/O, and does no synchronous logging. Scratch buffers are allocated before start. Metrics use atomics. Callback duration, peaks, buffer, latency, underruns, glitches, and errors are exposed in status snapshots.

## Build

From `crates`:

```powershell
cargo build --workspace --locked
cargo test --workspace --locked
cargo test -p uam_audio --test wasapi_render -- --nocapture
```

The last test requires Windows audio. It skips when no usable endpoint exists. Skipped hardware verification is not proof of audible output.
