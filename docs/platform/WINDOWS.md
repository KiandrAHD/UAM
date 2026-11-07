# Windows Platform Notes — Phase 0

**Status:** Audio device enumeration validated with a real Rust probe. No audio
stream processing implemented.

## 1. Host and toolchain findings

Observed on the Phase 0 host (Windows 11, x86_64):

| Tool | Result |
|---|---|
| Flutter | `3.44.6` (stable) |
| Bundled Dart | `3.12.2` |
| Standalone PATH Dart | `3.10.2` (version mismatch warning; use the Flutter-bundled Dart) |
| Rust | `1.99.1` |
| Rust toolchains | `stable-x86_64-pc-windows-gnu` and `stable-x86_64-pc-windows-msvc` |
| Git | `2.52.0` |
| Visual Studio Community 2022 | Installed **without** C++ desktop workload |
| CMake / Ninja | `4.4.4` / `1.13.2` |

### Blockers found

1. **MSVC linker missing.** `link.exe` is not on PATH because the VS C++
   workload is not installed. The Rust workspace therefore validates with:

   ```powershell
   $env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
   $env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
   ```

2. **Flutter Windows desktop build blocked.** `flutter doctor -v` reports
   missing:
   - `MSVC v142 - VS 2019 C++ x64/x86 build tools`
   - `C++ CMake tools for Windows`
   - `Windows 10 SDK`

   Consequence: the Flutter UI, analyzer, widget tests, and the live
   Flutter↔Rust test run, but the `.exe` desktop bundle is **not built** in
   Phase 0.

   Fix (requires user action / admin): install the **Desktop development with
   C++** workload in the Visual Studio Installer, including the Windows 10/11
   SDK and CMake tools. Then `flutter build windows`.

## 2. Audio architecture recommendation

See `docs/adr/ADR-006-windows-first-mvp.md`. Summary:

- Phase 0 reports `audio_processing_scope = "configuration_only"`.
- First real integration target: **selected-stream loopback capture** into the
  UAM DSP chain, re-rendered to a chosen output.
- Full **system-wide output** processing requires either a virtual audio device
  driver or an Audio Processing Object (APO). That is a separate, heavier
  decision with driver signing and installer consequences. It is not proposed
  for the first slice and is not accepted.

Candidate Windows audio APIs (documented, not all prototyped):

- WASAPI shared-mode render/capture.
- WASAPI loopback capture of a render endpoint.
- Per-process loopback capture (Windows 10 2004+).
- APO for device-level processing.
- A virtual audio device driver for system-wide routing.

## 3. What was actually validated

### 3.1 Device enumeration through the Windows audio API

`tools/audio_diagnostics/` is a Rust probe that enumerates active render and
capture endpoints through the MMDevice API (`IMMDeviceEnumerator`), reads each
endpoint's state, and reads `PKEY_Device_FriendlyName`.

Observed on this host:

```text
== Render endpoints (ACTIVE): 4 endpoint(s) ==
  [0] state=ACTIVE name=<redacted>
  [1] state=ACTIVE name=<redacted>
  [2] state=ACTIVE name=<redacted>
  [3] state=ACTIVE name=<redacted>
== Capture endpoints (ACTIVE): 2 endpoint(s) ==
  [0] state=ACTIVE name=<redacted>
  [1] state=ACTIVE name=<redacted>
phase0_wasapi_probe_ok render_active=4 capture_active=2
```

Exit code: `0`.

The device names are redacted here because they are a machine-specific
inventory. The tool prints real names locally; captured output must not be
committed.

This demonstrates:

- Rust can initialize COM and create the Windows audio device enumerator.
- Rust can enumerate endpoints and read device properties.
- A future UAM Windows backend can build on the same API family.

It does **not** demonstrate:

- Opening an audio stream.
- Capturing or rendering audio.
- Processing system output.
- Surviving device removal or default-device changes.

### 3.2 OS-level endpoint inventory

`scripts/test/windows_endpoint_inventory.ps1` collects a coarse OS inventory
using `Get-PnpDevice` and related PowerShell cmdlets. It captured 22 render
entries (4 in `Status OK`) and 7 capture entries.

This is **not** a WASAPI enumeration; it is an OS device list retained only as
a cross-check. Its output is machine-specific and is gitignored at
`docs/platform/windows-endpoint-inventory.txt`.

## 4. Remaining validation points

- [ ] Install the VS C++ workload and build the Flutter Windows bundle.
- [ ] Add a WASAPI shared-mode **render** stream that plays a test tone.
- [ ] Add WASAPI **loopback** capture and measure round-trip latency.
- [ ] Prototype per-process loopback on Windows 10 2004+.
- [ ] Handle `IMMNotificationClient` default-device and removal events.
- [ ] Measure CPU and buffer latency at 44.1 kHz and 48 kHz.
- [ ] Decide and document shared vs exclusive mode.
- [ ] Evaluate APO vs virtual-device effort for system-wide processing, with an
      explicit security and installer review.

## 5. Bluetooth and hardware controls

Windows exposes Bluetooth through the Win32 Bluetooth and BLE APIs. Phase 0
does **not** implement discovery or control. Per ADR-005:

- Audio endpoint enumeration is not Bluetooth scanning.
- Pairing does not grant ANC/transparency access.
- No vendor hardware control is claimed on Windows.

## 6. Official sources

- WASAPI overview — https://learn.microsoft.com/windows/win32/coreaudio/wasapi
- Enumerating audio devices — https://learn.microsoft.com/windows/win32/coreaudio/enumerating-audio-devices
- Loopback recording — https://learn.microsoft.com/windows/win32/coreaudio/loopback-recording
- Device events — https://learn.microsoft.com/windows/win32/coreaudio/device-events
- Device roles — https://learn.microsoft.com/windows/win32/coreaudio/device-roles
- `IMMDeviceEnumerator` — https://learn.microsoft.com/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator
- Audio Processing Objects — https://learn.microsoft.com/windows-hardware/drivers/audio/audio-processing-objects