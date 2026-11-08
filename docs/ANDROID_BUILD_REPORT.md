# Android Build Report

**Branch:** `feat/android-platform-support`  
**Report date:** 2026-11-08  
**Flutter:** 3.44.6 stable (Dart 3.12.2)  
**Rust:** 1.99.1 stable  
**Bridge ABI:** 1

## 1. Scope

This work adds Android platform configuration, Rust cross-compilation, native
library packaging, and platform-aware Dart FFI loading for the existing narrow
C ABI. It does **not** add Android audio capture, playback, audio effects,
Bluetooth control, device discovery, or system-wide audio processing.

## 2. Status summary

| Area | Status | Evidence |
|---|---|---|
| Flutter Android project | Implemented | `app/flutter/android/` present, Flutter 3.44.6 template |
| Application ID | Implemented | `com.kiandrahd.uam` |
| min / target / compile SDK | Implemented | Flutter defaults: 24 / 36 / 36 |
| Required ABI | Built locally | `arm64-v8a` (ELF64 AArch64) |
| Optional ABIs | Implemented | `armeabi-v7a`, `x86_64` supported by the build script |
| Rust Android script | Implemented + runs | `scripts/build/build_android_rust.ps1` |
| Native packaging | Built locally | `jniLibs/arm64-v8a/libuam_ffi.so` |
| APK (debug) | **Built locally** | `build/app/outputs/flutter-apk/app-debug.apk` |
| `.so` in APK | Verified | `lib/arm64-v8a/libuam_ffi.so` present in APK |
| Exported symbols | Verified | `uam_abi_version`, `uam_get_engine_info`, `uam_string_free` |
| Dart FFI loader | Implemented | Android SONAME loading in `RustLibraryLocator` |
| Android CI workflow | Added (not yet run on GitHub) | `.github/workflows/android-ci.yml` |
| Emulator test | **Not performed** | No AVD or system image installed |
| Physical-device test | **Not performed** | `adb devices` reported no device |

## 3. Build environment (this host)

- Android SDK: `D:\Android\Sdk`, platform `android-36.1`, build-tools `36.0.0`.
- Android NDK: `28.2.13676358` (r28c). It was **not installed at preflight** — the
  directory existed only as an empty installer stub. It was installed from the
  official `android-ndk-r28c-windows.zip` during this work.
- JDK: Android Studio JBR 21.
- Rustus targets: `aarch64-linux-android` (default and GNU host toolchains).
- Host toolchain for cross-compilation: `stable-x86_64-pc-windows-gnu` with the
  self-contained `rust-lld` linker (mirrors `build_rust.ps1`).

## 4. FFI library result

```
File:   app/flutter/android/app/src/main/jniLibs/arm64-v8a/libuam_ffi.so
Format: ELF64, DYN (shared object), AArch64
Size:   ~6.2 MB (debug profile, includes debug info)
NEEDED: libdl.so, libc.so  (both provided by Android; no missing dependencies)
Exports:
  T uam_abi_version
  T uam_get_engine_info
  T uam_string_free
```

## 5. APK result

```
Command: flutter build apk --debug   (from app/flutter)
Result:  success (exit 0)
Output:  build/app/outputs/flutter-apk/app-debug.apk  (~141.7 MB)
```

Native libraries inside the APK:

```
lib/arm64-v8a/libuam_ffi.so          <- UAM Rust core (this work)
lib/arm64-v8a/libflutter.so
lib/arm64-v8a/libVkLayer_khronos_validation.so
lib/armeabi-v7a/libflutter.so
lib/x86_64/libflutter.so
```

`libuam_ffi.so` is present only for `arm64-v8a` (the required ABI). No Windows
`uam_ffi.dll` is included in the APK.

AGP resolved and auto-installed CMake `3.22.1` into the SDK during the first
Gradle run; this is a standard Flutter Android build behavior and was not
introduced by UAM scripts.

## 6. ABI verification

- Bridge ABI version is unchanged at `1`.
- All three symbols the Dart bindings look up exist in the Android `.so`.
- Memory ownership: `uam_get_engine_info` returns a Rust-allocated string that
  Dart frees exactly once through `uam_string_free` in a `finally` block. No
  pointer is retained across calls.
- No audio callback API is exported. `uam_ffi` remains `cdylib`/`staticlib`/`rlib`.

## 7. FFI loading design (Dart)

`RustLibraryLocator.resolve()` returns:

- Android: the bare SONAME `libuam_ffi.so` (resolved by the Android dynamic
  linker from the installed native library directory).
- Windows: `uam_ffi.dll`; macOS: `libuam_ffi.dylib`; Linux: `libuam_ffi.so`
  (existing filesystem search preserved).

`DynamicLibrary.process()` is intentionally not used on Android: it resolves
from the already-loaded global symbol table and does not guarantee the bundled
library is loaded before the bridge is used. `DynamicLibrary.open('libuam_ffi.so')`
is the documented mechanism for packaged Android libraries.

A missing or unloadable library does not crash the process: `RustApi` maps it to
a typed `bridgeUnavailable` failure and the UI reports it.

## 8. Test results

| Suite | Command | Result |
|---|---|---|
| Dart format | `dart format --output=none --set-exit-if-changed .` | 75 files, 0 changed |
| Dart analyze | `flutter analyze` | No issues found |
| Flutter tests | `flutter test` | 68 passed, 0 failed |
| Live FFI bridge test | `flutter test test/integration/rust_bridge_test.dart` | Passed: core `0.1.0`, ABI `1` |
| Rust format | `cargo fmt --all -- --check` | Clean |
| Rust tests | `cargo test --workspace` | 127 passed, 0 failed |

The live FFI test ran against the Windows `uam_ffi.dll` (same code path and
bindings as Android); an Android `.so` cannot be loaded on the Windows host.

## 9. Windows regression

| Check | Result |
|---|---|
| `scripts/build/build_rust.ps1 -Profile debug` | Success; `uam_ffi.dll` rebuilt and copied |
| `flutter build windows --debug` | Success; `build/windows/x64/runner/Debug/uam.exe` |

No Windows files, CMake configuration, or the Windows build script were modified.

## 10. What was NOT validated

- **Physical Android device run** — no device connected (`adb devices` empty).
- **Emulator run** — no AVD or system image present; none was created.
- **On-device FFI load** — cannot be exercised without a device/emulator.
- **Android CI** — the workflow was authored but not executed on GitHub here.

## 11. Remaining limitations

1. System-wide Android audio processing is not implemented and is not claimed.
2. Processing scope reported by the core remains `configuration_only`.
3. No Android permissions are declared in the release manifest. `INTERNET`
   appears only in the debug/profile manifests generated by Flutter.
4. Release APKs use debug signing until a keystore is configured.
5. Only `arm64-v8a` was built here; other ABIs require their Rust targets.
6. The debug `.so` is ~6.2 MB; a `release` profile build is smaller (LTO, symbols
   stripped) and is the recommended profile for distribution.

## 12. Exact commands

```powershell
# 1. Setup (once)
$env:ANDROID_HOME     = 'D:\Android\Sdk'
$env:ANDROID_SDK_ROOT = 'D:\Android\Sdk'
sdkmanager --install "ndk;28.2.13676358"
sdkmanager --licenses
rustup target add aarch64-linux-android --toolchain stable-x86_64-pc-windows-gnu

# 2. Build the Rust core and package it
scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Profile debug

# 3. Build the APK
cd app/flutter
flutter pub get
flutter build apk --debug
# output: build\app\outputs\flutter-apk\app-debug.apk

# 4. Run on a device (when one is connected)
adb devices
flutter run -d <device-id>
```
