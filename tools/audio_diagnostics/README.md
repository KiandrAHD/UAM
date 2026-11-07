# UAM Audio Diagnostics (Phase 0)

A read-only Windows audio endpoint probe used to validate that Rust can reach
the Windows MMDevice (WASAPI) audio device layer.

## What it does

- Initializes COM in multithreaded mode.
- Creates an `IMMDeviceEnumerator`.
- Enumerates active **render** and **capture** endpoints.
- Reads each endpoint's state (`ACTIVE`, `DISABLED`, `NOTPRESENT`,
  `UNPLUGGED`) and friendly name from its property store.
- Prints a summary line:
  `phase0_wasapi_probe_ok render_active=<n> capture_active=<n>`.

## What it does not do

- It does not open an audio stream.
- It does not capture, play, or modify audio.
- It does not change device configuration.
- It does not prove that UAM can process system audio. It only proves device
  enumeration access.

## Build and run

This tool is intentionally separate from the main `crates/` workspace.

```powershell
# Host without MSVC linker (the Phase 0 environment):
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'

Set-Location tools/audio_diagnostics
cargo run
```

On a host with the MSVC C++ workload:

```powershell
Set-Location tools/audio_diagnostics
cargo run
```

## Privacy

Output contains real, machine-specific device names. **Do not commit captured
output.** It is a device inventory and can identify a user's hardware. Capture
results for diagnostics locally, or summarize only counts in documentation.