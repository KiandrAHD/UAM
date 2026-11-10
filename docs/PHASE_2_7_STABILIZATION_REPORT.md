# Phase 2.7 — Repository Stabilization and Android CI Repair

**Branch:** `feat/phase-2-7-stabilization`
**Report date:** 2026-11-10
**Base:** `main` @ `cb142aa` (PRs #1–#3 merged)
**Flutter:** 3.44.6 stable (Dart 3.12.2)
**Rust:** 1.99.1 stable (cross-compiled with `stable-x86_64-pc-windows-gnu`)
**Bridge ABI:** 1
**Scope:** stabilization only — no new audio features

---

## 1. Purpose

This pass stabilizes the repository before Phase 2.4 DSP integration. It:

1. finds and fixes the root cause of the failing Android CI workflow,
2. re-verifies the Android Rust cross-compilation script (debug + release),
3. re-verifies APK packaging and native symbol exports,
4. re-runs the Rust, Flutter, and Windows regressions,
5. records what was **actually** executed versus what was not.

No DSP, audio backend, device discovery, or hardware-control code changed.

---

## 2. Android CI failure — root cause

Failed run: `https://github.com/KiandrAHD/UAM/actions/runs/42467553523`

Recorded error:

```
Warning: Failed to find package 'tools'
sdkmanager failed with exit code 1
```

The failing step was **`Install Android SDK command-line tools and NDK`**, i.e.
`android-actions/setup-android@v3` itself, not UAM's own `sdkmanager` line.

**Root cause:** the `packages` input of `android-actions/setup-android@v3`
defaults to `tools platform-tools`. The legacy `tools` package was **removed from
the Android SDK repository** (replaced by `cmdline-tools`). When the action asks
`sdkmanager` for `tools`, `sdkmanager` prints
`Warning: Failed to find package 'tools'` and exits non-zero, so the action step
fails before the rest of the workflow runs.

The workflow's own install line (`platforms;android-36`,
`build-tools;36.0.0`, `ndk;28.2.13676358`) was already correct and was **not** the
cause.

### Fix

Pin the action's `packages` input explicitly and drop the obsolete `tools`
package. The workflow now:

- sets `cmdline-tools-version` explicitly (`12266719`),
- requests only `platform-tools` from the action,
- installs `platforms;android-36`, `build-tools;36.0.0`, and
  `ndk;28.2.13676358` in a dedicated step,
- keeps SDK license acceptance on (`accept-android-sdk-licenses: "true"`)
  instead of masking failures with `yes |` or retry loops.

No obsolete package is requested, and no setup failure is hidden.

---

## 3. Pinned Android toolchain versions

| Component | Version | Source of truth |
|---|---|---|
| Flutter | 3.44.6 (stable) | `flutter-action` + `pubspec` |
| Android SDK platform | `platforms;android-36` | Flutter 3.44.6 `compileSdkVersion = 36` |
| Android build-tools | `build-tools;36.0.0` | Flutter 3.44.6 / AGP 9.0.1 |
| Android NDK | `28.2.13676358` (r28c) | Flutter 3.44.6 `ndkVersion` |
| Command-line tools | `12266719` | pinned `setup-android` input |
| `minSdk` / `targetSdk` / `compileSdk` | 24 / 36 / 36 | `flutter.*Version` |
| AGP / Kotlin / Gradle | 9.0.1 / 2.3.20 / 9.1.0 | `app/flutter/android` |

The NDK value is held in one workflow-level variable (`NDK_VERSION`) so the
install, symbol check, and docs cannot drift apart.

---

## 4. Android Rust cross-compilation result

Script: `scripts/build/build_android_rust.ps1`

| Check | Result |
|---|---|
| NDK discovery (`ANDROID_SDK_ROOT`, `ANDROID_NDK_HOME`, standard paths) | Pass — resolved `D:\Android\Sdk\ndk\28.2.13676358` |
| Rust target `aarch64-linux-android` detection | Pass |
| NDK linker wiring (`CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER`) | Pass |
| `arm64-v8a` debug build | Pass |
| `arm64-v8a` release build | Pass |
| Exported ELF shared library | Pass |

Produced artifacts (gitignored, not committed):

| Profile | On-disk size |
|---|---|
| debug | ~5.9 MB |
| release | ~0.44 MB |

ELF verification (`llvm-readelf`):

```
Class:   ELF64
Type:    DYN (Shared object file)
Machine: AArch64
NEEDED:  libdl.so, libc.so   (both provided by Android)
```

Native symbol exports (`llvm-nm --dynamic --defined-only`):

```
T uam_abi_version
T uam_get_engine_info
T uam_string_free
```

### Script fix in this pass

The script built the LLVM binutils names with the clang wrapper suffix
(`.cmd`) on Windows, so it looked for `llvm-nm.cmd`, `llvm-ar.cmd`, and
`llvm-ranlib.cmd`. The NDK ships those as `.exe` on Windows, so symbol
verification and `AR`/`RANLIB` configuration were silently skipped. The script
now uses `.exe` for the binutils and keeps `.cmd` only for the clang wrappers.
This changes no Windows desktop behavior; it only affects the Android script.

---

## 5. APK validation

```
Command: flutter build apk --debug --target-platform android-arm64   (from app/flutter)
Result:  success (exit 0)
Output:  build/app/outputs/flutter-apk/app-debug.apk
Size:    141.73 MB
```

Native libraries inside the APK:

```
lib/arm64-v8a/libuam_ffi.so                     ~0.34 MB (symbol-stripped on packaging)
lib/arm64-v8a/libflutter.so
lib/arm64-v8a/libVkLayer_khronos_validation.so
```

- `lib/arm64-v8a/libuam_ffi.so` is present.
- The extracted library still exports `uam_abi_version`, `uam_get_engine_info`,
  and `uam_string_free`.
- `libuam_ffi.so` appears only under `arm64-v8a`.
- No Windows `uam_ffi.dll` is packaged.
- Dart loader (`RustLibraryLocator`) returns the bare SONAME `libuam_ffi.so`
  on Android; the packaged library is resolved by the Android dynamic linker.

---

## 6. Device and emulator status

- `adb devices` → no device attached.
- `emulator -list-avds` → no AVD installed.

Therefore:

- **Tested on emulator:** not performed.
- **Tested on physical Android device:** not performed.
- On-device FFI load, bridge ABI version call, and lifecycle checks are **not**
  verified. Android is **not** claimed production-ready.

---

## 7. Windows regression

| Check | Result |
|---|---|
| `scripts/build/build_rust.ps1` (debug) | Pass — rebuilt `uam_ffi.dll`, copied to `app/flutter/windows/runner/native/` |
| `flutter analyze` | Pass — no issues |
| `flutter test` | Pass — 68 tests |
| `flutter build windows --debug` | Pass — `build/windows/x64/runner/Debug/uam.exe` |

No Windows file, CMake configuration, or `build_rust.ps1` was modified.

---

## 8. Rust regression

From `crates/`:

| Check | Result |
|---|---|
| `cargo fmt --all -- --check` | Clean |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | Clean |
| `cargo test --workspace --locked` | 127 passed, 0 failed |
| `cargo bench -p uam_dsp --no-run --locked` | Compiles |

No test was removed, weakened, or ignored.

---

## 9. Flutter regression

From `app/flutter/`:

| Check | Result |
|---|---|
| `flutter pub get` | Pass |
| `dart format --output=none --set-exit-if-changed .` | 75 files, 0 changed |
| `flutter analyze` | No issues |
| `flutter test` | 68 passed, 0 failed |

---

## 10. Status classification

| Category | Items |
|---|---|
| **Implemented** | Android CI workflow fix; Android NDK/SDK version pinning; `.exe` LLVM binutils fix in the Android build script; docs updates |
| **Built locally** | `libuam_ffi.so` for `arm64-v8a` (debug and release); debug APK with `lib/arm64-v8a/libuam_ffi.so`; Windows `uam.exe` |
| **Tested on emulator** | None — no AVD installed |
| **Tested on physical Android device** | None — no device attached |
| **Verified in GitHub Actions** | Not yet — the repair is committed, but the workflow has not been re-run remotely in this environment |
| **Not implemented** | Android audio backend, device discovery, Bluetooth, system-wide processing |
| **Deferred** | On-device/emulator validation; CI re-run confirmation; release signing; `armeabi-v7a`/`x86_64` local builds |

UAM still does **not** process system-wide audio on any platform. Processing
scope remains `configuration_only`.

---

## 11. Remaining blockers

1. **Remote CI confirmation.** The workflow fix is logically verified (YAML
   parses, steps mirror the local commands) but must be observed green on GitHub
   Actions after this branch is pushed.
2. **Physical/emulator validation.** No Android device or AVD is available here.
   The on-device FFI load and bridge ABI `1` call remain unverified.
3. **Agreement with Phase 2.4.** DSP integration over the FFI boundary is not
   started; the C ABI is still the three control-path functions only.

---

## 12. Exact commands run

```powershell
# Preflight
git status --short --branch
git branch -vv
git log -8 --oneline --decorate
git fetch origin
git pull --ff-only origin main
git checkout -b feat/phase-2-7-stabilization

# Rust
cd crates
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo bench -p uam_dsp --no-run --locked
cd ..

# Android native build (debug + release)
powershell -ExecutionPolicy Bypass -File scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Profile debug
powershell -ExecutionPolicy Bypass -File scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Profile release

# Flutter + APK
cd app/flutter
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
cd ../..

# Windows regression
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1
cd app/flutter
flutter analyze
flutter test
flutter build windows --debug
```