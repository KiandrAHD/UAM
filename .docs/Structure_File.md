# UAM Repository File Structure

**Repository name:** `universe-audio-management`  
**Product:** Universe Audio Management (UAM)  
**Architecture:** Flutter application + Rust workspace + native platform adapters

This document proposes a maintainable monorepo. The structure is intentionally modular, but folders should be created when their implementation phase begins rather than generating empty placeholders for every future feature.

---

## 1. Proposed Repository Tree

```text
universe-audio-management/
│
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── .gitignore
├── .editorconfig
├── .gitattributes
│
├── docs/
│   ├── PRD.md
│   ├── Roadmap.md
│   ├── Architecture.md
│   ├── Tech_Stack.md
│   ├── Structure_File.md
│   ├── COMPATIBILITY.md
│   ├── PRIVACY.md
│   ├── DEVELOPMENT.md
│   ├── RELEASE.md
│   │
│   ├── adr/
│   │   ├── README.md
│   │   ├── ADR-001-flutter-ui.md
│   │   ├── ADR-002-rust-core.md
│   │   ├── ADR-003-local-first-storage.md
│   │   ├── ADR-004-preset-interchange.md
│   │   ├── ADR-005-capability-based-controls.md
│   │   └── ADR-006-windows-first-mvp.md
│   │
│   ├── platform/
│   │   ├── WINDOWS.md
│   │   ├── MACOS.md
│   │   ├── LINUX.md
│   │   ├── ANDROID.md
│   │   └── IOS.md
│   │
│   └── testing/
│       ├── TEST_STRATEGY.md
│       ├── AUDIO_TESTING.md
│       └── HARDWARE_MATRIX.md
│
├── app/
│   └── flutter/
│       ├── pubspec.yaml
│       ├── analysis_options.yaml
│       ├── lib/
│       │   ├── main.dart
│       │   ├── bootstrap.dart
│       │   │
│       │   ├── app/
│       │   │   ├── uam_app.dart
│       │   │   ├── router/
│       │   │   ├── theme/
│       │   │   └── config/
│       │   │
│       │   ├── core/
│       │   │   ├── errors/
│       │   │   ├── logging/
│       │   │   ├── utils/
│       │   │   ├── constants/
│       │   │   └── result/
│       │   │
│       │   ├── features/
│       │   │   ├── dashboard/
│       │   │   │   ├── data/
│       │   │   │   ├── application/
│       │   │   │   └── presentation/
│       │   │   │
│       │   │   ├── device_manager/
│       │   │   │   ├── domain/
│       │   │   │   ├── data/
│       │   │   │   ├── application/
│       │   │   │   └── presentation/
│       │   │   │
│       │   │   ├── equalizer/
│       │   │   │   ├── domain/
│       │   │   │   ├── application/
│       │   │   │   └── presentation/
│       │   │   │
│       │   │   ├── audio_engine/
│       │   │   │   ├── domain/
│       │   │   │   ├── data/
│       │   │   │   ├── application/
│       │   │   │   └── presentation/
│       │   │   │
│       │   │   ├── hardware_controls/
│       │   │   │   ├── domain/
│       │   │   │   ├── data/
│       │   │   │   ├── application/
│       │   │   │   └── presentation/
│       │   │   │
│       │   │   ├── presets/
│       │   │   │   ├── domain/
│       │   │   │   ├── data/
│       │   │   │   ├── application/
│       │   │   │   └── presentation/
│       │   │   │
│       │   │   ├── audio_lab/
│       │   │   └── settings/
│       │   │
│       │   ├── shared/
│       │   │   ├── widgets/
│       │   │   ├── models/
│       │   │   └── extensions/
│       │   │
│       │   ├── bridge/
│       │   │   ├── rust_api.dart
│       │   │   └── generated/
│       │   │
│       │   └── platform/
│       │       ├── audio/
│       │       ├── bluetooth/
│       │       ├── permissions/
│       │       └── share/
│       │
│       ├── test/
│       │   ├── unit/
│       │   ├── widget/
│       │   └── integration/
│       │
│       ├── integration_test/
│       ├── assets/
│       │   ├── icons/
│       │   ├── images/
│       │   └── fonts/
│       │
│       ├── windows/
│       ├── macos/
│       ├── linux/
│       ├── android/
│       └── ios/
│
├── crates/
│   ├── Cargo.toml
│   ├── uam_domain/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── device.rs
│   │       ├── capability.rs
│   │       ├── preset.rs
│   │       └── audio_config.rs
│   │
│   ├── uam_dsp/
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── filters/
│   │   │   ├── equalizer/
│   │   │   ├── dynamics/
│   │   │   ├── meters/
│   │   │   └── validation.rs
│   │   ├── tests/
│   │   └── benches/
│   │
│   ├── uam_audio/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── graph/
│   │       ├── stream/
│   │       ├── formats/
│   │       └── backend/
│   │
│   ├── uam_device/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── discovery.rs
│   │       ├── capabilities.rs
│   │       └── adapter_registry.rs
│   │
│   ├── uam_preset/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── schema.rs
│   │       ├── import.rs
│   │       ├── export.rs
│   │       └── validation.rs
│   │
│   ├── uam_platform/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── traits/
│   │       ├── windows/
│   │       ├── macos/
│   │       ├── linux/
│   │       ├── android/
│   │       └── ios/
│   │
│   └── uam_ffi/
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs
│           ├── api/
│           └── error.rs
│
├── native/
│   ├── windows/
│   │   ├── audio/
│   │   └── bluetooth/
│   ├── macos/
│   │   ├── audio/
│   │   └── bluetooth/
│   ├── linux/
│   │   ├── audio/
│   │   └── bluetooth/
│   ├── android/
│   │   ├── audio/
│   │   └── bluetooth/
│   └── ios/
│       ├── audio/
│       └── bluetooth/
│
├── database/
│   ├── README.md
│   ├── migrations/
│   │   ├── 0001_initial.sql
│   │   └── 0002_preset_metadata.sql
│   ├── schema/
│   │   └── preset.schema.json
│   └── fixtures/
│       └── sample-presets/
│
├── presets/
│   ├── examples/
│   └── schema/
│
├── scripts/
│   ├── setup/
│   ├── build/
│   ├── codegen/
│   ├── test/
│   └── release/
│
├── tools/
│   ├── preset_validator/
│   └── audio_diagnostics/
│
├── .github/
│   └── workflows/
│       ├── flutter-ci.yml
│       ├── rust-ci.yml
│       └── platform-builds.yml
│
└── build_support/
    ├── packaging/
    └── signing/
```

---

## 2. Directory Responsibilities

### `app/flutter/`
Contains the cross-platform Flutter application. Keep widgets, navigation, state management, and user workflows here.

### `app/flutter/lib/features/`
Feature-first modules. Each feature owns its presentation and application logic. Avoid a single oversized `screens/` folder.

### `app/flutter/lib/bridge/`
Contains the public Dart-facing Rust bridge and generated binding code. Generated files should be clearly marked and not edited manually.

### `crates/`
Rust workspace. Each crate has a narrow responsibility and explicit dependency direction.

### `crates/uam_dsp/`
Contains signal-processing algorithms. It should not depend on Flutter, SQLite, or UI state.

### `crates/uam_audio/`
Contains audio graph and backend abstractions. Platform-specific implementation details should be isolated.

### `crates/uam_device/`
Contains normalized device and capability models, discovery orchestration, and adapter registration.

### `crates/uam_preset/`
Contains portable preset schema, serialization, validation, and migration logic.

### `crates/uam_ffi/`
Contains the narrow API exposed to Flutter. Do not expose every internal Rust type.

### `native/`
Contains platform-specific code that does not fit naturally into a shared Rust implementation, such as Swift, Kotlin, C++, or platform glue.

### `database/`
Contains SQLite migration files, JSON schema definitions, fixtures, and database documentation. The actual user database file must live in the OS-appropriate application data directory, not in the repository.

### `presets/`
Contains safe sample preset files for development and tests. Do not store private user presets here.

### `docs/`
Contains product, architecture, compatibility, platform, and development documentation.

## 3. Dependency Direction

Preferred dependency direction:

```text
Flutter Presentation
        |
Flutter Application / Use Cases
        |
Repositories and Platform Services
        |
Flutter-Rust Bridge
        |
Rust FFI Facade
        |
Rust Domain / DSP / Audio / Preset crates
        |
Platform Adapter Implementations
```

Rules:
- `uam_dsp` must not depend on `uam_ffi`.
- Domain crates must not depend on Flutter.
- UI widgets must not call OS APIs directly.
- Platform-specific code must not leak into portable domain models.
- Keep generated bridge code separate from hand-written code.
- Avoid circular crate dependencies.

## 4. Naming Conventions

### Dart
- Files: `snake_case.dart`
- Types: `PascalCase`
- Variables/functions: `lowerCamelCase`
- Private members: `_leadingUnderscore`

### Rust
- Files/modules: `snake_case.rs`
- Types/traits: `PascalCase`
- Functions/variables: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`

### Documentation
- Use clear title-case or descriptive filenames.
- Keep filenames stable and avoid spaces.
- Use `ADR-NNN-short-description.md` for architecture decisions.

### Database
- Tables and columns: `snake_case`
- Migration filenames: sequential numeric prefix, e.g. `0001_initial.sql`.
- Never edit an already-applied migration; add a new migration.

## 5. Local Data Location

The SQLite database should be stored in the platform's application-support/data directory, not in the project folder.

Examples of location strategy:
- Windows: application data directory under the current user profile.
- macOS: Application Support directory.
- Linux: XDG data directory.
- Android: app-private internal storage.
- iOS: app sandbox application-support directory.

Use Flutter path-provider or an equivalent platform-supported mechanism to resolve the correct location. Do not hardcode absolute user paths.

## 6. What Not to Commit

Do not commit:
- User's live SQLite database.
- Personal device inventories.
- Private exported presets unless intentionally contributed as examples.
- Logs containing personal paths or identifiers.
- Signing keys, certificates, passwords, API tokens, or Bluetooth secrets.
- Build outputs and generated temporary artifacts unless the chosen toolchain explicitly requires them.

## 7. Start Small

For the first MVP, create only:
- `app/flutter/`
- `crates/uam_domain/`
- `crates/uam_dsp/`
- `crates/uam_preset/`
- `crates/uam_ffi/`
- `database/migrations/`
- `docs/`
- `.github/workflows/`

Add audio and hardware platform adapter folders when the relevant phase begins. This keeps the repository understandable and avoids premature abstraction.
