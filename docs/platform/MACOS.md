# macOS Platform Notes — Phase 0

**Status:** DOCUMENTED only. Not executed. No macOS host was available.

## 1. Audio integration candidates

| Area | Candidate API | Phase 0 status |
|---|---|---|
| App-owned playback/processing | AVFoundation / `AVAudioEngine` | DOCUMENTED |
| Device enumeration | Core Audio (`AudioObjectGetPropertyData`) | DOCUMENTED |
| Per-app / system tap (macOS 14.2+) | Core Audio process taps (`AudioHardwareTap`) | DOCUMENTED |
| Audio unit graph | Audio Toolbox / `AUGraph` / `AVAudioEngine` | DOCUMENTED |

Core Audio is the native device and stream layer. `AVAudioEngine` is the
higher-level graph that suits app-owned processing. Recent macOS versions add
Core Audio taps, which can expose other processes' audio to an app; this is the
most plausible route to non-app-owned processing, but it is version-gated and
must be validated on a real Mac.

## 2. Processing scope implications

- **App-owned stream:** realistic and should be the first macOS scope.
- **Selected / system audio:** depends on Core Audio taps (macOS 14.2+),
  entitlements, and user consent. Not verified.
- A macOS **Audio Server Plug-in** (a Core Audio driver) is the traditional
  system-wide route. It is a driver, with installation and signing
  consequences, and is not proposed for the first slice.

UAM must not claim system-wide macOS processing until a tap or driver path is
implemented and tested.

## 3. Permissions and distribution

- Microphone/capture access requires user consent and an
  `NSMicrophoneUsageDescription` entry if input is captured.
- System audio capture via taps may require additional entitlements or user
  approval depending on OS version.
- App Sandbox restricts file and device access; distribution choice (Mac App
  Store vs notarized direct download) affects which APIs are usable.
- Hardened Runtime and notarization are required for direct distribution.

## 4. Bluetooth and hardware controls

- CoreBluetooth covers BLE discovery and GATT interaction.
- Classic Bluetooth audio (A2DP/HFP) is handled by the OS, not by an app.
- ANC, transparency, and firmware control are vendor-specific and are not
  generally exposed. No support is claimed.

## 5. Rust and Flutter

- The `uam_dsp` and `uam_preset` crates are platform-independent and expected
  to compile unchanged. This is inferred, not executed.
- The FFI library would be built as `libuam_ffi.dylib` and loaded by Dart FFI.
  The locator already checks `libuam_ffi.dylib`
  (`app/flutter/lib/core/utils/rust_library_locator.dart`).
- Flutter macOS desktop requires Xcode and CocoaPods.

## 6. Remaining validation points

- [ ] Build the Rust core on macOS (both Apple Silicon and Intel).
- [ ] Build `libuam_ffi.dylib` and load it from Flutter.
- [ ] Enumerate devices with Core Audio.
- [ ] Prototype `AVAudioEngine` app-owned processing.
- [ ] Evaluate Core Audio taps on macOS 14.2+ with a real capture test.
- [ ] Document sandbox/entitlement requirements per distribution channel.

## 7. Official sources

- Core Audio — https://developer.apple.com/documentation/coreaudio
- AVAudioEngine — https://developer.apple.com/documentation/avfaudio/avaudioengine
- AVAudioSession — https://developer.apple.com/documentation/avfaudio/avaudiosession
- Core Audio taps — https://developer.apple.com/documentation/coreaudio/audiohardwaretap
- CoreBluetooth — https://developer.apple.com/documentation/corebluetooth

> Apple documentation pages could not be fetched as text during Phase 0, so
> these are cited as official URLs and labeled DOCUMENTED rather than VERIFIED.