# Universe Audio Management (UAM)

[English](#english) | [Bahasa Indonesia](#bahasa-indonesia)

A local-first, universal-first audio management application built around a
Flutter UI, a shared Rust core, and capability-gated native platform adapters.

**Bridge ABI version:** `1` · **Core engine version:** `0.1.0`

> UAM reports a feature only after the operating-system API and hardware adapter
> for it have actually been tested. This README is written to match the real
> state of the repository — not the intended end state.

---

## English

### Contents

1. [Overview](#overview)
2. [Current status](#current-status)
3. [Repository layout](#repository-layout)
4. [Architecture at a glance](#architecture-at-a-glance)
5. [Requirements](#requirements)
6. [Tutorial: run the project](#tutorial-run-the-project)
7. [Testing and quality checks](#testing-and-quality-checks)
8. [The Rust ↔ Flutter bridge](#the-rust--flutter-bridge)
9. [Continuous integration](#continuous-integration)
10. [Scope and limitations](#scope-and-limitations)
11. [Documentation index](#documentation-index)
12. [Contributing, security, license](#contributing-security-license)

### Overview

UAM is a monorepo that combines:

- A **Flutter** desktop/mobile UI at `app/flutter/` with a reusable design
  system, a responsive shell, and seven configuration modules.
- A **Rust** workspace at `crates/` with platform-independent domain types, a
  deterministic DSP core, portable preset validation, and a narrow C ABI.
- **Versioned preset interchange** (`.uam-preset.json`, schema v1) with schema,
  fixtures, and a validation script.
- **Documentation** (PRD, roadmap, architecture, ADRs, per-platform notes, and
  phase reports) under `docs/`.

The Flutter app reports structured metadata from the compiled Rust core. It
explicitly reports a processing scope of `configuration_only`: UAM does not yet
perform system-wide equalization, live device discovery, or hardware control.
Device and hardware UI stays unavailable until a verified platform adapter
reports capability evidence.

### Current status

| Area | Status |
|---|---|
| **Phase 0** — discovery and technical validation | Complete, with documented platform blockers |
| **Phase 1** — foundation and UX (shell, design system, modules) | Implemented and validated in the available Flutter/Rust test environment |
| **Phase 2.1–2.3, 2.6** — DSP core (config, EQ, limiter, metering, pipeline, benchmarks) | Implemented and tested; no live audio callback yet |
| **Phase 2.7** — repository stabilization and Android CI repair | Android CI failure root-caused and fixed (obsolete `tools` package); cross-compilation, symbols, and APK re-verified locally; device/CI validation deferred |
| **Android** — platform support and Rust FFI packaging | Implemented; a debug APK builds locally and contains `lib/arm64-v8a/libuam_ffi.so`. Not device-validated |
| **Audio backend / system-wide processing** | Not implemented. Processing scope is `configuration_only` |

Recorded validation on the reference host: 127 Rust tests, 68 Flutter tests,
and 3 valid / 8 invalid preset fixtures. DSP benchmarks meet the `< 2 %` of one
core target (stereo 10-band EQ + limiter at 48 kHz / 256 frames). Phase 2.7
re-verified the Android build script (debug + release), APK packaging, native
symbols, and the Windows/Rust/Flutter regressions. See
[`docs/Roadmap.md`](docs/Roadmap.md) and the phase reports for evidence.

### Repository layout

| Path | Purpose |
|---|---|
| `app/flutter/` | Flutter application: design system, bridge, features, tests, and the native platform folders (`android/`, `windows/`, `linux/`, `macos/`, `ios/`); official brand assets in `assets/branding/` |
| `crates/` | Rust workspace: `uam_domain`, `uam_dsp`, `uam_preset`, `uam_ffi` |
| `database/` | Preset JSON Schema (`schema/`), fixtures (`fixtures/sample-presets/`), migration notes |
| `presets/` | User-facing example presets (`examples/`) and schema pointer (`schema/`) |
| `scripts/` | Setup, build, and test automation (`setup/`, `build/`, `test/`, `codegen/`) |
| `tools/audio_diagnostics/` | Read-only Windows MMDevice (WASAPI) endpoint probe |
| `docs/` | PRD, roadmap, architecture, ADRs, platform notes, testing, phase reports |
| `.github/workflows/` | Flutter, Rust, and Android CI |

### Architecture at a glance

```
Flutter UI (Dart)
   │  named routes · ChangeNotifier + InheritedNotifier state
   ▼
Dart FFI bridge (app/flutter/lib/bridge/)
   │  ABI version 1 · JSON payloads only (no audio buffers)
   ▼
Rust C ABI (crates/uam_ffi)  ──  uam_abi_version / uam_get_engine_info / uam_string_free
   ▼
Rust core: uam_preset → uam_dsp → uam_domain
```

- `uam_domain` — platform-independent primitives and validated audio config.
- `uam_dsp` — deterministic, allocation-free-at-runtime DSP primitives.
- `uam_preset` — portable preset schema, validation, import/export.
- `uam_ffi` — narrow C ABI facade used by the Flutter app.

### Requirements

| Tool | Version used |
|---|---|
| Flutter (stable) | `3.44.6` |
| Dart (bundled with Flutter) | `3.12.2` |
| Rust | `1.99.1` (declared MSRV `1.85`, edition `2021`) |
| Python (preset validation script only) | `3.11` + `jsonschema` `4.26` |
| Android SDK / NDK (Android builds only) | platform `36`, build-tools `36.0.0`, NDK `28.2.13676358` |
| Java / JDK (Android builds only) | `17+` |

Notes:

- Use the Dart bundled with Flutter. A separate PATH Dart conflicts with the
  Flutter SDK version floor and causes analyzer/test mismatches.
- On Windows, `flutter run/build` for desktop requires the Visual Studio
  **Desktop development with C++** workload.
- If MSVC's `link.exe` is unavailable, build Rust with the GNU target and the
  self-contained `rust-lld` linker (the provided script does this for you).

### Tutorial: run the project

All commands below are run from the repository root. Examples use Windows
PowerShell; Unix equivalents are noted where they differ.

#### Step 1 — Clone and enter the repository

```powershell
git clone https://github.com/KiandrAHD/UAM.git
Set-Location UAM
```

#### Step 2 — Verify the toolchain

```powershell
flutter --version
rustc --version
cargo --version

# Automated check (also prints Rust toolchains)
powershell -ExecutionPolicy Bypass -File scripts/setup/check_environment.ps1
```

For a full platform report: `flutter doctor -v`.

#### Step 3 — Fetch Flutter dependencies

```powershell
Set-Location app/flutter
flutter pub get
Set-Location ../..
```

#### Step 4 — Build the Rust core (native library)

Standard build on a host with the MSVC C++ workload:

```powershell
Set-Location crates
cargo build -p uam_ffi
Set-Location ..
```

Recommended on the reference host (no MSVC linker). The script sets the
GNU/`rust-lld` environment, builds `uam_ffi`, and copies the result to
`app/flutter/windows/runner/native/uam_ffi.dll` (gitignored):

```powershell
# Debug
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1

# Release
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1 -Profile release
```

Equivalent manual environment (Windows GNU):

```powershell
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
Set-Location crates
cargo build -p uam_ffi
Set-Location ..
```

#### Step 5 — Run the desktop app (Windows)

```powershell
Set-Location app/flutter
flutter run -d windows
```

The Dart locator finds the native library in
`app/flutter/windows/runner/native/` or `crates/target/{debug,release}`. To point
the app at a library elsewhere:

```powershell
$env:UAM_FFI_LIBRARY_PATH = 'D:\path\to\uam_ffi.dll'
```

> Without the Visual Studio C++ workload, `flutter run -d windows` and
> `flutter build windows` fail at the CMake/link stage. See
> [`docs/platform/WINDOWS.md`](docs/platform/WINDOWS.md).

#### Step 6 — Build for Android (optional)

Prerequisites are the Android SDK, NDK `28.2.13676358`, an Android Rust target,
and JDK 17+. Full steps:
[`docs/ANDROID_SETUP.md`](docs/ANDROID_SETUP.md).

```powershell
# Install the Rust target once
rustup target add aarch64-linux-android

# Cross-compile uam_ffi and pack libuam_ffi.so into jniLibs/<abi>/
powershell -ExecutionPolicy Bypass -File scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Profile debug

# Build the APK
Set-Location app/flutter
flutter build apk --debug
```

Output: `app/flutter/build/app/outputs/flutter-apk/app-debug.apk`. To run on a
connected device:

```powershell
adb devices
flutter run -d <device-id>
```

Useful build script options: `-Abi all`, `-Profile release`, `-Api 24`,
`-NdkPath "D:\Android\Sdk\ndk\28.2.13676358"`, `-Toolchain <rustup-toolchain>`.

#### Step 7 — Run the diagnostics and validation tools (optional)

```powershell
# Validate preset fixtures against the published JSON Schema
python scripts/test/validate_presets.py   # expect: Valid fixtures: 3 / Invalid fixtures: 8 / PASSED

# Confirm the compiled bridge library exists
powershell -ExecutionPolicy Bypass -File scripts/test/test_bridge.ps1

# Read-only Windows audio endpoint probe (do NOT commit its output)
Set-Location tools/audio_diagnostics
cargo run
Set-Location ../..
```

### Testing and quality checks

Rust (from `crates/`):

```powershell
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

Flutter (from `app/flutter/`):

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Preset fixtures (from the repository root):

```powershell
python scripts/test/validate_presets.py
```

The live bridge test (`app/flutter/test/integration/rust_bridge_test.dart`)
loads the compiled library if present, so build the Rust core first to exercise
it instead of skipping. On hosts without MSVC, prepend the GNU/`rust-lld`
environment from Step 4.

### The Rust ↔ Flutter bridge

The C ABI is intentionally tiny and versioned (`BRIDGE_ABI_VERSION = 1`):

| Function | Contract |
|---|---|
| `uam_abi_version() -> u32` | Returns the ABI contract version |
| `uam_get_engine_info() -> *mut c_char` | Owned UTF-8 JSON engine metadata; caller frees it |
| `uam_string_free(*mut c_char)` | Frees a pointer returned by the function above |

Rules:

- Returned strings are owned by the caller and freed exactly once with
  `uam_string_free`.
- `NULL` means internal failure, never a valid payload.
- Dart validates every JSON field and rejects an ABI mismatch.
- Never expose per-sample audio through this boundary.

The `flutter_rust_bridge` generator is deliberately not used yet; the current
three-function ABI is hand-maintained. See
[`docs/adr/ADR-003-flutter-rust-interop.md`](docs/adr/ADR-003-flutter-rust-interop.md).

### Continuous integration

| Workflow | Trigger paths | What it does |
|---|---|---|
| [`.github/workflows/rust-ci.yml`](.github/workflows/rust-ci.yml) | `crates/**` | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test --workspace` |
| [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) | `app/flutter/**`, `crates/**` | Builds the Rust FFI lib, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test` |
| [`.github/workflows/android-ci.yml`](.github/workflows/android-ci.yml) | `app/flutter/**`, `crates/**`, Android build script | Installs SDK/NDK, cross-compiles `arm64-v8a`, verifies symbols, builds a debug APK, uploads it as an artifact |

All workflows run on pushes to `main` and `feat/**` and on pull requests that
touch the listed paths.

### Scope and limitations

UAM is universal-first but **capability-gated**. Stated plainly:

- UAM does **not** currently process any system audio. The processing scope is
  `configuration_only`.
- UAM does **not** control vendor hardware (ANC, transparency, firmware) on any
  platform.
- No mobile capture or system-wide processing is claimed. Bluetooth pairing
  does not prove ANC, battery, touch, or firmware control.
- Cross-platform DSP/preset verification is by reasoning about
  platform-independent code, not by execution on every OS.
- Android support today is project configuration, Rust cross-compilation,
  native packaging, and platform-aware FFI loading — **not** an Android audio
  backend.

See [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) for the full matrix.

### Documentation index

- [Documentation index](docs/README.md)
- [Product requirements (PRD)](docs/PRD.md)
- [Roadmap](docs/Roadmap.md)
- [Architecture](docs/Architecture.md)
- [Technology stack](docs/Tech_Stack.md)
- [Repository structure](docs/Structure_File.md)
- [Compatibility matrix](docs/COMPATIBILITY.md)
- [Development guide](docs/DEVELOPMENT.md)
- [Phase 0 report](docs/PHASE_0_REPORT.md)
- [Phase 1 report](docs/PHASE_1_REPORT.md)
- [Phase 1.1 report](docs/PHASE_1_1_REPORT.md)
- [Phase 2 readiness](docs/PHASE_2_READINESS.md)
- [Phase 2 implementation report](docs/PHASE_2_IMPLEMENTATION_REPORT.md)
- [Phase 2.3 design](docs/PHASE_2_3_DESIGN.md)
- [Phase 2.3 implementation report](docs/PHASE_2_3_IMPLEMENTATION_REPORT.md)
- [Android setup](docs/ANDROID_SETUP.md) · [Android build report](docs/ANDROID_BUILD_REPORT.md)
- [Branding](docs/BRANDING.md) — official logo, generated platform icons, regeneration steps
- [Architecture Decision Records](docs/adr/README.md)
- [Platform notes](docs/platform/) · [Testing](docs/testing/) · [Benchmarks](docs/testing/BENCHMARKS.md)
- [Privacy](docs/PRIVACY.md) · [Release](docs/RELEASE.md)

### Contributing, security, license

- Contribution guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security policy: [`SECURITY.md`](SECURITY.md)
- License: [`MIT`](LICENSE)

---

## Bahasa Indonesia

### Daftar Isi

1. [Ringkasan](#ringkasan)
2. [Status saat ini](#status-saat-ini)
3. [Struktur repositori](#struktur-repositori)
4. [Arsitektur sekilas](#arsitektur-sekilas)
5. [Kebutuhan](#kebutuhan)
6. [Tutorial: menjalankan proyek](#tutorial-menjalankan-proyek)
7. [Pengujian dan pemeriksaan mutu](#pengujian-dan-pemeriksaan-mutu)
8. [Jembatan Rust ↔ Flutter](#jembatan-rust--flutter)
9. [Integrasi berkelanjutan (CI)](#integrasi-berkelanjutan-ci)
10. [Cakupan dan keterbatasan](#cakupan-dan-keterbatasan)
11. [Indeks dokumentasi](#indeks-dokumentasi)
12. [Kontribusi, keamanan, lisensi](#kontribusi-keamanan-lisensi)

### Ringkasan

UAM adalah monorepo yang menggabungkan:

- Antarmuka **Flutter** untuk desktop/mobile di `app/flutter/` dengan design
  system yang dapat digunakan ulang, shell responsif, dan tujuh modul
  konfigurasi.
- Workspace **Rust** di `crates/` dengan tipe domain yang tidak bergantung
  platform, core DSP deterministik, validasi preset portabel, dan C ABI yang
  sempit.
- **Pertukaran preset berversi** (`.uam-preset.json`, schema v1) beserta schema,
  fixtures, dan skrip validasi.
- **Dokumentasi** (PRD, roadmap, arsitektur, ADR, catatan per platform, dan
  laporan fase) di `docs/`.

Aplikasi Flutter melaporkan metadata terstruktur dari core Rust yang sudah
dikompilasi. Cakupan pemrosesan audio dilaporkan secara jujur sebagai
`configuration_only`: UAM belum melakukan ekualisasi system-wide, penemuan
perangkat langsung, atau kontrol perangkat keras. UI perangkat dan perangkat
keras tetap tidak tersedia sampai adapter platform terverifikasi melaporkan
bukti kemampuan.

### Status saat ini

| Area | Status |
|---|---|
| **Fase 0** — penemuan dan validasi teknis | Selesai, dengan blocker platform yang terdokumentasi |
| **Fase 1** — fondasi dan UX (shell, design system, modul) | Terimplementasi dan tervalidasi di lingkungan uji Flutter/Rust yang tersedia |
| **Fase 2.1–2.3, 2.6** — core DSP (config, EQ, limiter, metering, pipeline, benchmark) | Terimplementasi dan teruji; belum ada callback audio live |
| **Fase 2.7** — stabilisasi repositori dan perbaikan CI Android | Akar kegagalan CI Android ditemukan dan diperbaiki (paket usang `tools`); cross-compile, simbol, dan APK diverifikasi ulang secara lokal; validasi perangkat/CI ditunda |
| **Android** — dukungan platform dan pengemasan Rust FFI | Terimplementasi; APK debug dapat dibangun secara lokal dan memuat `lib/arm64-v8a/libuam_ffi.so`. Belum divalidasi di perangkat |
| **Backend audio / pemrosesan system-wide** | Belum diimplementasikan. Cakupan pemrosesan adalah `configuration_only` |

Validasi tercatat pada host referensi: 127 tes Rust, 68 tes Flutter, dan 3
fixture preset valid / 8 invalid. Benchmark DSP memenuhi target `< 2 %` dari
satu core (stereo 10-band EQ + limiter pada 48 kHz / 256 frame). Fase 2.7
memverifikasi ulang skrip build Android (debug + release), pengemasan APK,
simbol native, serta regresi Windows/Rust/Flutter. Lihat
[`docs/Roadmap.md`](docs/Roadmap.md) dan laporan fase untuk buktinya.

### Struktur repositori

| Path | Fungsi |
|---|---|
| `app/flutter/` | Aplikasi Flutter: design system, bridge, fitur, tes, dan folder platform native (`android/`, `windows/`, `linux/`, `macos/`, `ios/`); aset merek resmi di `assets/branding/` |
| `crates/` | Workspace Rust: `uam_domain`, `uam_dsp`, `uam_preset`, `uam_ffi` |
| `database/` | JSON Schema preset (`schema/`), fixtures (`fixtures/sample-presets/`), catatan migrasi |
| `presets/` | Contoh preset untuk pengguna (`examples/`) dan penunjuk schema (`schema/`) |
| `scripts/` | Otomasi setup, build, dan tes (`setup/`, `build/`, `test/`, `codegen/`) |
| `tools/audio_diagnostics/` | Probe endpoint Windows MMDevice (WASAPI), hanya baca |
| `docs/` | PRD, roadmap, arsitektur, ADR, catatan platform, pengujian, laporan fase |
| `.github/workflows/` | CI Flutter, Rust, dan Android |

### Arsitektur sekilas

```
Flutter UI (Dart)
   │  named routes · state ChangeNotifier + InheritedNotifier
   ▼
Jembatan Dart FFI (app/flutter/lib/bridge/)
   │  ABI versi 1 · payload JSON saja (tanpa buffer audio)
   ▼
Rust C ABI (crates/uam_ffi)  ──  uam_abi_version / uam_get_engine_info / uam_string_free
   ▼
Core Rust: uam_preset → uam_dsp → uam_domain
```

- `uam_domain` — primitif tidak bergantung platform dan konfigurasi audio tervalidasi.
- `uam_dsp` — primitif DSP deterministik, bebas alokasi saat runtime.
- `uam_preset` — schema preset portabel, validasi, impor/ekspor.
- `uam_ffi` — facade C ABI sempit yang dipakai aplikasi Flutter.

### Kebutuhan

| Alat | Versi yang dipakai |
|---|---|
| Flutter (stable) | `3.44.6` |
| Dart (bawaan Flutter) | `3.12.2` |
| Rust | `1.99.1` (MSRV dideklarasikan `1.85`, edition `2021`) |
| Python (hanya skrip validasi preset) | `3.11` + `jsonschema` `4.26` |
| Android SDK / NDK (hanya build Android) | platform `36`, build-tools `36.0.0`, NDK `28.2.13676358` |
| Java / JDK (hanya build Android) | `17+` |

Catatan:

- Gunakan Dart bawaan Flutter. Dart terpisah di PATH bertentangan dengan batas
  versi SDK Flutter dan menyebabkan ketidakcocokan analyzer/tes.
- Di Windows, `flutter run/build` untuk desktop memerlukan workload Visual Studio
  **Desktop development with C++**.
- Jika `link.exe` MSVC tidak tersedia, bangun Rust memakai target GNU dengan
  linker `rust-lld` yang self-contained (skrip yang disediakan menangani ini).

### Tutorial: menjalankan proyek

Semua perintah dijalankan dari root repositori. Contoh memakai Windows
PowerShell; padanan Unix dicatat bila berbeda.

#### Langkah 1 — Clone dan masuk ke repositori

```powershell
git clone https://github.com/KiandrAHD/UAM.git
Set-Location UAM
```

#### Langkah 2 — Verifikasi toolchain

```powershell
flutter --version
rustc --version
cargo --version

# Pemeriksaan otomatis (juga menampilkan toolchain Rust)
powershell -ExecutionPolicy Bypass -File scripts/setup/check_environment.ps1
```

Untuk laporan platform lengkap: `flutter doctor -v`.

#### Langkah 3 — Ambil dependensi Flutter

```powershell
Set-Location app/flutter
flutter pub get
Set-Location ../..
```

#### Langkah 4 — Bangun core Rust (library native)

Build standar pada host dengan workload MSVC C++:

```powershell
Set-Location crates
cargo build -p uam_ffi
Set-Location ..
```

Direkomendasikan pada host referensi (tanpa linker MSVC). Skrip menyiapkan
lingkungan GNU/`rust-lld`, mem-build `uam_ffi`, lalu menyalin hasilnya ke
`app/flutter/windows/runner/native/uam_ffi.dll` (diabaikan Git):

```powershell
# Debug
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1

# Release
powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1 -Profile release
```

Padanan lingkungan manual (Windows GNU):

```powershell
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'
Set-Location crates
cargo build -p uam_ffi
Set-Location ..
```

#### Langkah 5 — Jalankan aplikasi desktop (Windows)

```powershell
Set-Location app/flutter
flutter run -d windows
```

Locator Dart menemukan library native di
`app/flutter/windows/runner/native/` atau `crates/target/{debug,release}`. Untuk
mengarahkan aplikasi ke library di lokasi lain:

```powershell
$env:UAM_FFI_LIBRARY_PATH = 'D:\path\to\uam_ffi.dll'
```

> Tanpa workload Visual Studio C++, `flutter run -d windows` dan
> `flutter build windows` gagal di tahap CMake/link. Lihat
> [`docs/platform/WINDOWS.md`](docs/platform/WINDOWS.md).

#### Langkah 6 — Build untuk Android (opsional)

Prasyarat: Android SDK, NDK `28.2.13676358`, target Rust Android, dan JDK 17+.
Langkah lengkap: [`docs/ANDROID_SETUP.md`](docs/ANDROID_SETUP.md).

```powershell
# Pasang target Rust sekali saja
rustup target add aarch64-linux-android

# Cross-compile uam_ffi dan kemas libuam_ffi.so ke jniLibs/<abi>/
powershell -ExecutionPolicy Bypass -File scripts/build/build_android_rust.ps1 -Abi arm64-v8a -Profile debug

# Build APK
Set-Location app/flutter
flutter build apk --debug
```

Hasil: `app/flutter/build/app/outputs/flutter-apk/app-debug.apk`. Untuk
menjalankan di perangkat yang terhubung:

```powershell
adb devices
flutter run -d <device-id>
```

Opsi skrip build yang berguna: `-Abi all`, `-Profile release`, `-Api 24`,
`-NdkPath "D:\Android\Sdk\ndk\28.2.13676358"`, `-Toolchain <rustup-toolchain>`.

#### Langkah 7 — Jalankan tool diagnostik dan validasi (opsional)

```powershell
# Validasi fixture preset terhadap JSON Schema
python scripts/test/validate_presets.py   # harapan: Valid fixtures: 3 / Invalid fixtures: 8 / PASSED

# Pastikan library bridge hasil build ada
powershell -ExecutionPolicy Bypass -File scripts/test/test_bridge.ps1

# Probe endpoint audio Windows (hanya baca; JANGAN commit hasilnya)
Set-Location tools/audio_diagnostics
cargo run
Set-Location ../..
```

### Pengujian dan pemeriksaan mutu

Rust (dari `crates/`):

```powershell
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

Flutter (dari `app/flutter/`):

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Fixture preset (dari root repositori):

```powershell
python scripts/test/validate_presets.py
```

Tes bridge live (`app/flutter/test/integration/rust_bridge_test.dart`) memuat
library yang sudah dikompilasi jika ada, jadi bangun core Rust lebih dulu agar
tes benar-benar berjalan, bukan dilewati. Pada host tanpa MSVC, tambahkan
lingkungan GNU/`rust-lld` dari Langkah 4.

### Jembatan Rust ↔ Flutter

C ABI sengaja dibuat kecil dan berversi (`BRIDGE_ABI_VERSION = 1`):

| Fungsi | Kontrak |
|---|---|
| `uam_abi_version() -> u32` | Mengembalikan versi kontrak ABI |
| `uam_get_engine_info() -> *mut c_char` | Metadata engine UTF-8 JSON milik pemanggil; harus dibebaskan |
| `uam_string_free(*mut c_char)` | Membebaskan pointer hasil fungsi di atas |

Aturan:

- String hasil milik pemanggil dan dibebaskan tepat sekali dengan
  `uam_string_free`.
- `NULL` berarti kegagalan internal, bukan payload valid.
- Dart memvalidasi setiap field JSON dan menolak ketidakcocokan ABI.
- Jangan pernah mengekspos audio per-sampel melalui batas ini.

Generator `flutter_rust_bridge` sengaja belum dipakai; ABI tiga fungsi saat ini
dipelihara manual. Lihat
[`docs/adr/ADR-003-flutter-rust-interop.md`](docs/adr/ADR-003-flutter-rust-interop.md).

### Integrasi berkelanjutan (CI)

| Workflow | Path pemicu | Yang dilakukan |
|---|---|---|
| [`.github/workflows/rust-ci.yml`](.github/workflows/rust-ci.yml) | `crates/**` | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test --workspace` |
| [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml) | `app/flutter/**`, `crates/**` | Build library Rust FFI, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test` |
| [`.github/workflows/android-ci.yml`](.github/workflows/android-ci.yml) | `app/flutter/**`, `crates/**`, skrip build Android | Pasang SDK/NDK, cross-compile `arm64-v8a`, verifikasi simbol, build APK debug, unggah sebagai artifact |

Semua workflow berjalan untuk push ke `main` dan `feat/**` serta untuk pull
request yang menyentuh path terkait.

### Cakupan dan keterbatasan

UAM bersifat universal-first tetapi **capability-gated**. Tanpa bumbu:

- UAM **belum** memproses audio sistem apa pun. Cakupan pemrosesan adalah
  `configuration_only`.
- UAM **belum** mengontrol perangkat keras vendor (ANC, transparency, firmware)
  di platform mana pun.
- Tidak ada klaim tangkapan audio mobile atau pemrosesan system-wide. Pairing
  Bluetooth tidak membuktikan ANC, baterai, sentuhan, atau kontrol firmware.
- Verifikasi DSP/preset lintas platform dilakukan dengan penalaran atas kode
  yang tidak bergantung platform, bukan dengan eksekusi di setiap OS.
- Dukungan Android saat ini adalah konfigurasi proyek, cross-compile Rust,
  pengemasan native, dan pemuatan FFI sadar platform — **bukan** backend audio
  Android.

Lihat [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) untuk matriks lengkapnya.

### Indeks dokumentasi

- [Indeks dokumentasi](docs/README.md)
- [Kebutuhan produk (PRD)](docs/PRD.md)
- [Roadmap](docs/Roadmap.md)
- [Arsitektur](docs/Architecture.md)
- [Tumpukan teknologi](docs/Tech_Stack.md)
- [Struktur repositori](docs/Structure_File.md)
- [Matriks kompatibilitas](docs/COMPATIBILITY.md)
- [Panduan pengembangan](docs/DEVELOPMENT.md)
- [Laporan Fase 0](docs/PHASE_0_REPORT.md)
- [Laporan Fase 1](docs/PHASE_1_REPORT.md)
- [Laporan Fase 1.1](docs/PHASE_1_1_REPORT.md)
- [Kesiapan Fase 2](docs/PHASE_2_READINESS.md)
- [Laporan implementasi Fase 2](docs/PHASE_2_IMPLEMENTATION_REPORT.md)
- [Desain Fase 2.3](docs/PHASE_2_3_DESIGN.md)
- [Laporan implementasi Fase 2.3](docs/PHASE_2_3_IMPLEMENTATION_REPORT.md)
- [Setup Android](docs/ANDROID_SETUP.md) · [Laporan build Android](docs/ANDROID_BUILD_REPORT.md)
- [Branding](docs/BRANDING.md) — logo resmi, ikon platform yang dihasilkan, langkah regenerasi
- [Architecture Decision Records](docs/adr/README.md)
- [Catatan platform](docs/platform/) · [Pengujian](docs/testing/) · [Benchmark](docs/testing/BENCHMARKS.md)
- [Privasi](docs/PRIVACY.md) · [Rilis](docs/RELEASE.md)

### Kontribusi, keamanan, lisensi

- Panduan kontribusi: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Kebijakan keamanan: [`SECURITY.md`](SECURITY.md)
- Lisensi: [`MIT`](LICENSE)
