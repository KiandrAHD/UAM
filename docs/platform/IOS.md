# iOS Platform Notes — Phase 0

**Status:** DOCUMENTED only. Not executed. No macOS/Xcode host was available.

## 1. Audio integration candidates

| Area | Candidate | Phase 0 status |
|---|---|---|
| App-owned processing | `AVAudioEngine` | DOCUMENTED |
| Session management | `AVAudioSession` | DOCUMENTED |
| Device route changes | `AVAudioSession` route-change notifications | DOCUMENTED |
| Bluetooth | CoreBluetooth / `AVAudioSession` Bluetooth options | DOCUMENTED |

## 2. Processing scope implications

- **App-owned stream:** the only realistic full-processing scope on iOS.
  `AVAudioEngine` can host UAM's DSP chain for audio the app itself plays or
  generates.
- **Selected / other-app audio:** **NOT SUPPORTED.** iOS does not provide a
  general API for a third-party app to capture and process audio produced by
  other apps.
- **System-wide output:** **NOT SUPPORTED** for third-party apps. App extensions
  and Audio Unit extensions exist for specific host contexts, but they are not
  a general system equalizer.

UAM must not claim system-wide iOS processing under any circumstance.

## 3. Session, lifecycle, and background behavior

- Audio session categories/modes determine mixing, ducking, and whether other
  audio is interrupted.
- Interruptions (calls, Siri, other apps) must be handled; the engine may need
  to restart.
- Background audio requires the `audio` background mode and correct session
  configuration.
- Route changes (headphones, Bluetooth) must be observed; the sample rate and
  channel layout can change.

## 4. Permissions and distribution

- Microphone input requires `NSMicrophoneUsageDescription` and user consent.
- Bluetooth usage may require `NSBluetoothAlwaysUsageDescription` depending on
  the API used.
- App Store review constrains background behavior and Bluetooth usage; document
  the justification.
- The app must be built and signed with Xcode; no iOS build was attempted.

## 5. Rust and Flutter

- Rust can target iOS (`aarch64-apple-ios`, simulator targets). The FFI library
  would be a static or dynamic library linked into the Runner, or a bundled
  framework.
- Flutter iOS builds require macOS and Xcode.
- The Dart locator currently selects a `.dylib` for `macos`; iOS packaging will
  need an explicit FFI loading strategy in the Xcode target.

## 6. Remaining validation points

- [ ] Build the Rust core for iOS on macOS/Xcode.
- [ ] Integrate the FFI library into the Runner.
- [ ] Prototype `AVAudioEngine` app-owned processing.
- [ ] Handle interruption, route change, and background audio.
- [ ] Document App Store constraints for Bluetooth and background modes.

## 7. Official sources

- AVAudioEngine — https://developer.apple.com/documentation/avfaudio/avaudioengine
- AVAudioSession — https://developer.apple.com/documentation/avfaudio/avaudiosession
- CoreBluetooth — https://developer.apple.com/documentation/corebluetooth
- Background audio — https://developer.apple.com/documentation/avfoundation/audio-and-video-capture

> Apple documentation pages could not be fetched as text during Phase 0, so
> these are cited as official URLs and labeled DOCUMENTED rather than VERIFIED.