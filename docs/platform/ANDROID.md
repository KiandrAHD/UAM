# Android Platform Notes — Phase 0

**Status:** Platform configuration, Rust cross-compilation, native library
packaging, and Dart FFI loading are implemented and the debug APK builds
locally. Audio backend, device discovery, and Bluetooth integration remain
unimplemented. Physical-device and emulator validation were not performed. See
`docs/ANDROID_SETUP.md` and `docs/ANDROID_BUILD_REPORT.md`.

## 1. Toolchain status

- Android SDK `36` is present.
- `cmdline-tools` is missing, and SDK licenses have not been accepted.
- No emulator or physical device test was run.
- Mobile builds were not attempted.

## 2. Audio integration candidates

| Area | Candidate | Phase 0 status |
|---|---|---|
| App-owned processing | `AudioTrack` / `AudioRecord` / AAudio / Oboe | DOCUMENTED |
| Audio effects | `AudioEffect` subclasses on a session | DOCUMENTED |
| Capturing other apps | `AudioPlaybackCapture` | DOCUMENTED |
| Bluetooth | Android Bluetooth / BLE APIs | DOCUMENTED |
| Device routing | `AudioManager` device lists | DOCUMENTED |

`AudioEffect` (for example `Equalizer`, `BassBoost`) applies to a specific audio
session and is **not** a general system equalizer. It also depends on the device
implementing the effect. UAM should not assume every device exposes a given
effect.

`AudioPlaybackCapture` (Android 10+) allows an app to capture audio played by
other apps **only** if the source app permits capture (its usage/allowance
flags). This makes unconstrained system-wide capture impossible.

## 3. Processing scope implications

- **App-owned stream:** realistic first scope using AAudio/Oboe or
  `AudioTrack`.
- **Selected app:** possible only for apps that allow playback capture, and only
  on Android 10+. Not guaranteed.
- **System-wide output:** **NOT SUPPORTED** as an unrestricted feature. Android
  does not provide a general system-wide audio effect path for third-party apps.

UAM must never present an Android feature as a system equalizer.

## 4. Permissions and lifecycle

- `AudioPlaybackCapture` requires `RECORD_AUDIO` and, for capturing other apps,
  the `MediaProjection` flow or the capture policy the platform provides.
- Bluetooth permissions changed across Android 12/13: `BLUETOOTH_SCAN`,
  `BLUETOOTH_CONNECT`, and legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` for older
  versions.
- Background execution and foreground-service rules affect long-running audio.
- Audio focus and interruptions must be handled.

## 5. Rust and Flutter

- Rust can target Android via the NDK; the FFI library would be bundled per ABI
  (for example `arm64-v8a`, `x86_64`).
- Dart FFI can load a bundled `.so` from the app's native library directory.
- Flutter Android builds require the Android SDK, `cmdline-tools`, accepted
  licenses, and a JDK. None of these is fully configured here.

## 6. Remaining validation points

- [ ] Install `cmdline-tools`, accept licenses, and run `flutter doctor`.
- [ ] Build the Rust core for Android ABIs with the NDK.
- [ ] Load the `.so` from Flutter and call the bridge.
- [ ] Prototype app-owned playback through AAudio/Oboe.
- [ ] Test `AudioPlaybackCapture` against a cooperating app on Android 10+.
- [ ] Document per-version Bluetooth permission requirements.
- [ ] Test lifecycle, audio focus, and background behavior.

## 7. Official sources

- `AudioEffect` — https://developer.android.com/reference/android/media/audiofx/AudioEffect
- `AudioPlaybackCapture` — https://developer.android.com/media/platform/av-capture
- Bluetooth permissions — https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
- AAudio — https://developer.android.com/ndk/guides/audio/aaudio/aaudio
- Oboe — https://github.com/google/oboe