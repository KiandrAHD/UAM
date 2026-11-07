# Phase 1 Report — Foundation and UX

**Date:** 2026-11-07  
**Branch:** `feat/phase-1-foundation-ux`  
**Status:** implemented and validated in the available Flutter/Rust test environment; no commit, merge, or push was performed.

## Executive summary

Phase 1 turns the Phase 0 bridge proof into a responsive Flutter application foundation. It adds a centralized design system, dark/light/system appearance support, a responsive application shell, seven navigable modules, capability-aware configuration UX, strict local preset validation, and tests.

The application remains an honest configuration prototype. The Rust bridge ABI is unchanged at `1`; the only runtime engine claim is `configuration_only`. There is no audio backend, endpoint adapter, Bluetooth scanner, ANC protocol, cloud/auth service, SQLite database, or persistent preferences in this phase.

## Git status

Working tree contains uncommitted Phase 1 changes on `feat/phase-1-foundation-ux`.

- Modified tracked files: `README.md`; Flutter routes, theme export, app root, bootstrap, constants, `pubspec.yaml`, and the existing widget test; `docs/Architecture.md`, `docs/DEVELOPMENT.md`, `docs/README.md`, `docs/Roadmap.md`, `docs/Structure_File.md`.
- Added files: Inter font asset; router, shell, state, design-system, feature, and shared-model source trees; test support; Phase 1 unit and widget tests; `docs/PHASE_1_REPORT.md`.
- No commit, push, merge, force-push, or history rewrite was performed.

## Implemented tree

```text
app/flutter/
├── assets/fonts/Inter-Variable.ttf
├── lib/
│   ├── app/
│   │   ├── router/{app_router.dart,app_routes.dart}
│   │   ├── shell/{uam_destinations,uam_mobile_navigation,uam_shell,uam_sidebar,uam_top_bar}.dart
│   │   ├── state/uam_app_controller.dart
│   │   └── uam_app.dart
│   ├── design_system/
│   │   ├── components/{uam_components,uam_layout,uam_processing_ring,uam_response_graph}.dart
│   │   ├── theme/uam_theme.dart
│   │   └── tokens/{uam_breakpoints,uam_colors,uam_motion,uam_radii,uam_shadows,uam_spacing,uam_typography}.dart
│   ├── features/{audio_engine,dashboard,device_manager,equalizer,hardware_controls,presets,settings}/
│   └── shared/models/{audio_device,capability,engine_runtime_state,equalizer_configuration,preset_document}.dart
└── test/
    ├── support/test_harness.dart
    ├── unit/ (Phase 0 and Phase 1 model/controller/token tests)
    └── widget/ (app, shell, navigation, hardware, presets, settings tests)
```

Existing `crates/`, schema, fixture, bridge, and platform structures remain intact.

## Design system

- Font: bundled `Inter-Variable.ttf`, declared in `pubspec.yaml` as `Inter`.
- Tokens: color roles, typography, spacing, radii, shadows, motion, and breakpoints live under `lib/design_system/tokens/`.
- Themes: `UamTheme.dark` and `UamTheme.light` use `UamColorTokens`, a `ThemeExtension`; the default preference is system.
- Dark palette: exact values extracted from `design_uam.md`, including canvas `#080C12`, surface `#111720`, accent `#2CBFF3`, success `#45D8A0`, warning `#F0B35C`, error `#F06E77`, and planned `#A797F6`.
- Light palette: derived intentionally because no light palette exists in the Figma source. It preserves surface hierarchy and cyan identity with dark, accessible foreground values. The implementation labels it as derived; it does not imply a Figma-approved light design.
- Shared UI: cards, statuses, capability badges, notices, headers, responsive grids, response graph, processing ring, icon buttons, and empty states.

## Responsive shell and navigation

`UamShell` surrounds every named route.

| Width | Shell behavior |
|---|---|
| `<=390` | compact mobile layout, 60px top bar, bottom navigation |
| `391–760` | mobile layout, 60px top bar, bottom navigation |
| `761–1100` | 76px icon-only sidebar with tooltips, 78px top bar |
| `>1100` | 238px sidebar, 78px top bar |

Mobile primary destinations are Dashboard, Device Manager, Equalizer, and Presets. Audio Engine, Hardware Controls, and Settings are accessible from the More sheet. Navigation uses named routes and replacement navigation to keep one shell instance per module.

## Modules

1. **Dashboard** — selected-device, desired EQ, processing scope, system health, hardware capability and preset summaries. It always distinguishes configuration from verified audio output.
2. **Device Manager** — an unavailable repository rather than fake device data; discovery, selected endpoint, connection, and metadata remain explicit unavailable states.
3. **Equalizer** — a ten-band desired configuration editor, response graph, bypass state, bounded preamp, and no claim that the system is processing sound.
4. **Audio Engine** — bridge/runtime status, diagnostic entries, and a clipboard-backed report action. The Phase 0 Rust proof page remains separately reachable.
5. **Hardware Controls** — availability, unsupported, permission-required, disconnected, not-implemented, loading, unknown, and error are distinct. A `Switch` renders only for a connected device whose adapter reports an available, non-badge control.
6. **Presets** — bundled entries mirror `presets/examples/`, filters, favorite state, preview, local import validation, clipboard export, and delete protection for built-ins. The library is memory-only.
7. **Settings** — in-memory appearance/general preferences, reduced motion, About, reset confirmation, and explicit placeholders for undesigned categories.

## State and data architecture

Phase 1 uses Flutter built-ins only:

- `UamAppController` is the app root `ChangeNotifier`.
- `UamAppScope` exposes it through `InheritedNotifier`.
- Feature controllers own engine, devices, equalizer, and preset-library state.
- `UamApp` rebuilds the `MaterialApp` only when theme or reduced-motion preference changes; feature updates flow through the inherited notifier. This avoids recreating the navigator during ordinary feature-state updates.

The modeled state distinguishes desired configuration, core reachability/acceptance evidence, processing verification, processing scope, selected/active endpoint, connection, and capability availability. No UI state upgrades missing runtime evidence into a verified claim.

## Rust and preset integration

Phase 0 bridge functions remain unchanged:

- `uam_abi_version()`
- `uam_get_engine_info()`
- `uam_string_free()`

ABI remains `1`; Flutter still uses `EngineInfoGateway` and `RustApi`. Engine metadata reports `configuration_only` and does not prove an audio stream.

Preset documents use `.uam-preset.json` schema v1. `PresetCodec` is a strict Dart mirror of the schema/range contract and is tested against repository fixtures. It exists because this build exposes no FFI preset-validation symbol. The UI explicitly calls this **local** validation and never claims that Rust validated an import.

## Validation

Executed successfully:

```text
app/flutter
  dart format lib test
  flutter analyze                 # No issues found
  flutter test                    # 68 tests passed

crates (stable-x86_64-pc-windows-gnu + rust-lld)
  cargo fmt --all -- --check      # passed
  cargo clippy --workspace --all-targets -- -D warnings  # passed
  cargo test --workspace          # 41 tests passed

repository root
  python scripts/test/validate_presets.py
  # Valid fixtures: 3
  # Invalid fixtures: 8
  # PASSED
```

Flutter coverage includes tokens/themes, capability states, engine truth, EQ bounds and mapping, preset codec/library, root state, app success/failure states, responsive shell classes, all seven desktop destinations, mobile More navigation, unavailable hardware controls, valid/invalid preset import, and appearance/reduced-motion settings.

The existing `.github/workflows/flutter-ci.yml` and `rust-ci.yml` workflows remain
valid and continue to cover format, analysis, Flutter tests, and Rust
fmt/clippy/tests. They were reviewed but not executed locally because this
environment has no GitHub Actions runner.

## Platform builds

| Target | Status |
|---|---|
| Flutter widget/unit tests | verified on host |
| Rust workspace | verified on host GNU/rust-lld configuration |
| Windows desktop binary | not verified; Visual Studio Desktop development with C++ workload is absent |
| Android | not verified; toolchain unavailable |
| iOS/macOS/Linux | not verified in this Windows environment |

No platform build is claimed working beyond the checks listed above.

## Limitations

- No audio is processed or measured; status is `configuration_only`.
- No device discovery, endpoint enumeration, Bluetooth scanning, or hardware command adapter exists.
- No persistence: presets, favorites, selected configuration, and preferences reset when the app restarts.
- Import accepts pasted JSON in the current UI; native file picking is deferred.
- Preset validation is Dart-local, not an FFI call.
- Clipboard report/preset export is a local action; native file export is deferred.
- Light appearance is derived, not sourced from the provided Figma specification.

## Acceptance checklist

- [x] Centralized design tokens and reusable components
- [x] Dark, light, and system themes
- [x] Required breakpoints and sidebar/top-bar/bottom-nav geometry
- [x] Seven navigable modules
- [x] No fake device data or verified-processing claim
- [x] Capability-gated controls without unavailable switches
- [x] Strict schema-v1 preset parse/import/preview behavior
- [x] Existing Rust FFI ABI and Phase 0 test surface retained
- [x] Flutter, Rust, and preset validation commands pass
- [x] Existing Flutter and Rust CI workflows remain valid
- [ ] Desktop/mobile platform binaries verified — blocked by unavailable toolchains
- [ ] Live audio/device/hardware integration — intentionally outside Phase 1

## Phase 2 recommendations

1. Add a narrow, versioned Rust FFI endpoint for validated preset parsing before relying on it at a native import boundary.
2. Select one Windows audio path and prove a complete, measurable vertical slice before adding more UI controls.
3. Introduce a real endpoint adapter before allowing device selection or hardware capabilities to become actionable.
4. Add persistence only after deciding the schema/migration boundary; use the database guidance and load the Postgres skill only if Postgres is introduced.
5. Install the Windows C++ workload and verify a Windows binary before marking Phase 1 build acceptance complete.
6. Add visual/golden tests and accessibility semantics tests once CI has a stable desktop runner.
