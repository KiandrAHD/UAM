# UAM Platform Compatibility Matrix

**Phase:** 0 (Discovery and Technical Validation)
**Date:** 2026-11-07
**Scope:** What has actually been demonstrated, what is documented, and what is
still unknown.

> UAM is universal-first but capability-gated. This matrix is deliberately
> conservative: a feature is only `VERIFIED` when it was executed and observed,
> not when a library claims support.

## Status labels

| Label | Meaning |
|---|---|
| `VERIFIED` | Executed on this host and observed to work; evidence path given. |
| `PROTOTYPED` | Code exists and runs, but only as a local prototype, not integrated or cross-checked. |
| `DOCUMENTED` | Backed by official platform documentation; not executed in Phase 0. |
| `UNVERIFIED` | Believed possible; no proof gathered yet. |
| `BLOCKED` | Attempted but prevented by a concrete blocker on this host. |
| `NOT SUPPORTED` | Platform policy makes the feature impossible or disallowed. |

Blank cells are `UNVERIFIED` by default.

## Host used for Phase 0

- Windows 11 desktop, x86_64.
- Flutter `3.44.6`, bundled Dart `3.12.2`.
- Rust `1.99.1` (`stable-x86_64-pc-windows-gnu` for linking).
- Visual Studio Community 2022 installed **without** the C++ desktop workload.
- Android SDK `36` present but missing `cmdline-tools` and accepted licenses.
- No macOS, Linux, iOS, or Android device available.

## Feature matrix

| Capability | Windows | macOS | Linux | Android | iOS |
|---|---|---|---|---|---|
| Flutter UI shell | PROTOTYPED | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED |
| Rust core (compiles/tests) | VERIFIED | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED |
| DSP biquad EQ + preamp | VERIFIED | VERIFIED¹ | VERIFIED¹ | VERIFIED¹ | VERIFIED¹ |
| Preset schema + validation | VERIFIED | VERIFIED¹ | VERIFIED¹ | VERIFIED¹ | VERIFIED¹ |
| Flutter↔Rust bridge | VERIFIED | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED |
| Desktop app binary (build) | BLOCKED | UNVERIFIED | UNVERIFIED | NOT SUPPORTED² | NOT SUPPORTED² |
| Audio endpoint enumeration | VERIFIED | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED |
| App-owned stream processing | UNVERIFIED | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED |
| Selected-stream processing | UNVERIFIED | DOCUMENTED | DOCUMENTED | DOCUMENTED³ | NOT SUPPORTED³ |
| System-wide output processing | UNVERIFIED | UNVERIFIED | DOCUMENTED | NOT SUPPORTED³ | NOT SUPPORTED³ |
| Bluetooth device discovery | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED | DOCUMENTED |
| Vendor hardware controls (ANC, etc.) | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

¹ The DSP and preset crates are platform-independent Rust. They are verified on
Windows and are expected to compile unchanged elsewhere; they have not been
executed on another operating system in Phase 0.
² "Desktop app binary" is not a mobile concept.
³ Mobile operating systems restrict capture/processing of audio produced by
other apps. See the platform documents.

## What is genuinely verified

1. **Rust DSP correctness.** RBJ biquad coefficients with sample-rate-aware
   design; peaking gain at centre frequency matches the configured gain within
   `0.01 dB`; shelves boost/cut the correct band. 41 Rust tests pass.
   Evidence: `crates/uam_dsp/tests/dsp_tests.rs`,
   `crates/uam_dsp/src/filters/mod.rs`.
2. **Preset interchange.** A strict JSON Schema plus redundant Rust semantic
   validation. 3 valid fixtures accepted, 8 invalid fixtures rejected.
   Evidence: `database/schema/preset.schema.json`,
   `database/fixtures/sample-presets/`, `scripts/test/validate_presets.py`.
3. **Flutter↔Rust bridge.** A real Dart FFI call loads the compiled
   `uam_ffi.dll` and returns structured engine info. Evidence:
   `app/flutter/test/integration/rust_bridge_test.dart`.
4. **Windows audio device enumeration.** A Rust probe using the Windows
   MMDevice (WASAPI) API enumerated 4 active render endpoints and 2 active
   capture endpoints on this host, with names and states. See
   `docs/platform/WINDOWS.md` and `tools/audio_diagnostics/`.

## What is explicitly not claimed

- UAM does **not** currently process any system audio. Phase 0 reports
  `configuration_only`.
- UAM does **not** support any vendor hardware control (ANC, transparency,
  firmware) on any platform.
- No mobile capture or system-wide processing is claimed.
- Cross-platform DSP/preset verification is by reasoning about the
  platform-independent code, not by execution on those hosts.

## Official sources

Windows:

- WASAPI overview — https://learn.microsoft.com/windows/win32/coreaudio/wasapi
- Loopback recording — https://learn.microsoft.com/windows/win32/coreaudio/loopback-recording
- Enumerating audio devices — https://learn.microsoft.com/windows/win32/coreaudio/enumerating-audio-devices
- Device events — https://learn.microsoft.com/windows/win32/coreaudio/device-events
- Device roles — https://learn.microsoft.com/windows/win32/coreaudio/device-roles
- `IMMDeviceEnumerator` — https://learn.microsoft.com/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator

macOS / iOS:

- Core Audio overview — https://developer.apple.com/documentation/coreaudio
- AVAudioEngine — https://developer.apple.com/documentation/avfaudio/avaudioengine
- AVAudioSession — https://developer.apple.com/documentation/avfaudio/avaudiosession
- Core Audio taps (macOS 14.2+) — https://developer.apple.com/documentation/coreaudio/audiohardwaretap

Linux:

- PipeWire — https://pipewire.org/
- PipeWire documentation — https://docs.pipewire.org/
- BlueZ — https://www.bluez.org/

Android:

- `AudioEffect` — https://developer.android.com/reference/android/media/audiofx/AudioEffect
- `AudioPlaybackCapture` — https://developer.android.com/media/platform/av-capture
- Bluetooth permissions — https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
