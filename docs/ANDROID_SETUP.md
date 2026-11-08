# Android Setup Guide

**Status:** Implemented for `feat/android-platform-support`

## Overview

UAM uses a narrow Dart FFI bridge into a Rust shared library (`libuam_ffi.so`)
that is cross-compiled for Android using the NDK and bundled inside the APK under
`jniLibs/<abi>/`. No audio processing is claimed on Android in this phase;
the bridge exposes engine metadata only.

---

## Prerequisites

| Tool | Required version | Notes |
|---|---|---|
| Flutter | 3.44.6 (stable) | Installed and on `PATH` |
| Android SDK | 36.x | Platform `android-36` and build-tools `36.0.0` required |
| Android NDK | **28.2.13676358** | Must include `aarch64-linux-android<API>-clang` |
| Rust toolchain | stable (1.85+) | Must include target `aarch64-linux-android` |
| Java / JDK | 17+ | Android Studio JBR 21 works |
| PowerShell | Core or Windows PowerShell 5.1 | For the build script |

Verify with:

```powershell
flutter doctor -v
rustup --version
```

---

## 1. Android SDK Setup

Set `ANDROID_HOME` (or `ANDROID_SDK_ROOT`) to your SDK root:

```powershell
$env:ANDROID_HOME = 'D:\Android\Sdk'        # Windows example
$env:ANDROID_SDK_ROOT = 'D:\Android\Sdk'
```

The SDK must contain:
- `platforms/android-36.1/` or `android-36.0/`
- `build-tools/36.0.0/`
- `ndk/<version>/` (see §2)

If licenses are not accepted:

```powershell
sdkmanager --licenses
# accept all android-sdk-license entries
```

Or use Android Studio's SDK Manager UI.

---

## 2. Android NDK Installation

**The NDK is the primary setup blocker on this host.**

### Option A: Use Android Studio SDK Manager (recommended)

```powershell
sdkmanager --install "ndk;28.2.13676358"
```

The NDK is placed under `ANDROID_SDK/ndk/28.2.13676358/`.

### Option B: Download directly

Download the NDK zip from the Android repository and extract:

```powershell
$ndkUrl = 'https://dl.google.com/android/repository/android-ndk-r28c-windows.zip'
$zipPath = "$env:TEMP\android-ndk-r28c-windows.zip"
curl.exe -L -o $zipPath $ndkUrl
Expand-Archive -Path $zipPath -DestinationPath "D:\Android\Sdk\ndk\"
Move-Item "D:\Android\Sdk\ndk\android-ndk-r28c" "D:\Android\Sdk\ndk\28.2.13676358"
Remove-Item $zipPath
```

Verify:

```powershell
Get-Content "D:\Android\Sdk\ndk\28.2.13676358\source.properties"
# Revision should be NDK 28.2.13676358
```

The following clang wrappers must exist after installation:

| ABI | Wrapper |
|---|---|
| arm64-v8a | `toolchains/llvm/prebuilt/<host>/bin/aarch64-linux-android24-clang.cmd` |
| armeabi-v7a | `toolchains/llvm/prebuilt/<host>/bin/armv7a-linux-androideabi24-clang.cmd` |
| x86_64 | `toolchains/llvm/prebuilt/<host>/bin/x86_64-linux-android24-clang.cmd` |

`<host>` is `windows-x86_64` on Windows, `linux-x86_64` on Linux, `darwin-x86_64` on macOS.

---

## 3. Rust Target Installation

Install the required Rust targets (one or more):

```powershell
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi   # optional, for armeabi-v7a
rustup target add x86_64-linux-android      # optional, for x86_64
```

Verify:

```powershell
rustup target list --installed
```

---

## 4. Android Flutter Configuration

The following files are part of this implementation:

- `app/flutter/android/app/build.gradle.kts` — `namespace`/`applicationId` updated to `com.kiandrahd.uam`
- `app/flutter/android/settings.gradle.kts` — Flutter 3.44.6 / AGP 9.0.1 / Kotlin 2.3.20
- `app/flutter/android/app/src/main/kotlin/com/kiandrahd/uam/MainActivity.kt`
- `app/flutter/android/app/src/main/AndroidManifest.xml` — label set to "UAM"

No manual Gradle edits are needed. The Flutter toolchain defaults are used:
- `minSdk = flutter.minSdkVersion` → 24
- `targetSdk = flutter.targetSdkVersion` → 36
- `compileSdk = flutter.compileSdkVersion` → 36
- `ndkVersion = flutter.ndkVersion` → 28.2.13676358

---

## 5. Native Library Build

Build `libuam_ffi.so` for one or more Android ABIs:

```powershell
# Single ABI (arm64-v8a), debug
scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Profile debug

# All supported ABIs, release
scripts/build/build_android_rust.ps1 -Abi all -Profile release

# Explicit NDK path
scripts/build/build_android_rust.ps1 -Abi arm64-v8a -NdkPath "D:\Android\Sdk\ndk\28.2.13676358"

# Explicit host toolchain (Windows defaults to stable-x86_64-pc-windows-gnu)
scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Toolchain stable-x86_64-pc-windows-msvc
```

On Windows the script defaults the host toolchain to
`stable-x86_64-pc-windows-gnu` and uses the self-contained `rust-lld` linker,
mirroring `scripts/build/build_rust.ps1`. This is required when no MSVC linker
is on `PATH`. On Linux and macOS the script uses the active default toolchain.

The script:
1. Locates the NDK from `ANDROID_NDK_HOME` / standard SDK search paths.
2. Validates Rust targets are installed.
3. Configures `CARGO_TARGET_<triple>_LINKER` to the NDK clang wrapper.
4. Builds `uam_ffi` for each ABI using `cargo build --target <triple>`.
5. Copies `libuam_ffi.so` to:
   `app/flutter/android/app/src/main/jniLibs/<abi>/`
6. Optionally lists exported `uam_*` symbols using `llvm-nm`.

---

## 6. APK Build

After the native library is built:

```powershell
flutter pub get
flutter build apk --debug
# or for release:
flutter build apk --release
```

The APK is placed at:
`app/flutter/build/app/outputs/flutter-apk/app-debug.apk`

---

## 7. Verify Native Library in APK

```powershell
# List shared libraries in the debug APK (contains native libs)
flutter build apk --debug 2>&1 | Select-String "libc++"

# Or inspect the output directory after build:
Get-ChildItem "app/flutter/build/app/intermediates/jni_libs" -Recurse -Filter "*.so" | Select-Object FullName
```

On a device or emulator:

```bash
adb shell unzip -l /data/app/*/base.apk | grep "\.so$"
```

---

## 8. Physical Device Test

```bash
# List connected devices
adb devices

# Install and run
flutter run -d <device-id>
```

Expected startup behavior without a native library:
- The app launches and the UI loads.
- The Rust engine page shows `configuration_only` scope.
- No crash at startup.

Expected startup behavior with the native library:
- The Rust engine page shows `Universe Audio Management 0.1.0`, bridge ABI version 1.
- The processing scope reports `configuration_only`.

---

## 9. Troubleshooting

### "NDK not found"

```powershell
# Verify NDK environment
$env:ANDROID_NDK_HOME
Get-Content "$env:ANDROID_NDK_HOME\source.properties"
```

If empty, install the NDK or set the variable:
```powershell
$env:ANDROID_NDK_HOME = 'D:\Android\Sdk\ndk\28.2.13676358'
```

### "Rust target not installed"

```powershell
rustup target add aarch64-linux-android
```

### "flutter build apk fails with SDK licenses"

```powershell
flutter doctor --android-licenses
# accept all prompts
```

### "libuam_ffi.so not found in APK"

Verify the file was copied:
```powershell
Test-Path "app/flutter/android/app/src/main/jniLibs/arm64-v8a/libuam_ffi.so"
```
If missing, re-run the build script.

### "Missing NDK clang wrapper"

Verify the NDK install: the `toolchains/llvm/prebuilt/windows-x86_64/bin/` directory must exist and contain `aarch64-linux-android24-clang.cmd`.

---

## 10. CI/CD

A GitHub Actions workflow at `.github/workflows/android-ci.yml` runs on every
push to `main` and `feat/**`. It:
1. Installs Flutter 3.44.6 and Rust stable.
2. Installs Android SDK and NDK 28.2.13676358 via `android-actions/setup-android`.
3. Builds the Rust library for `arm64-v8a` using the `build_android_rust.ps1` script.
4. Builds a debug APK and uploads it as a workflow artifact.

Artifacts are available from the GitHub Actions run summary.

---

## Platform Capability Notes

- **No system-wide audio processing** is claimed on Android.
- The bridge ABI version is `1`.
- Processing scope is `configuration_only`.
- Audio device discovery and hardware controls are not implemented in Phase 1.
- Bluetooth functionality is not implemented in Phase 1.
- Future audio backend integration requires a separate adapter that uses
  `AudioEffect` (app-owned session) or `AudioTrack`/`AAudio`/`Oboe`.
  System-wide output interception is not possible on standard Android.
