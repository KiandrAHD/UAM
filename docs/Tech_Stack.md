# UAM Technology Stack

**Product:** Universe Audio Management  
**Primary stack:** Flutter + Rust  
**Architecture:** Shared UI and domain core with native platform adapters  
**Storage:** SQLite locally, JSON for sharing

---

## 1. Stack Summary

| Layer | Recommended technology | Responsibility |
|---|---|---|
| Cross-platform UI | Flutter / Dart | Application UI and interaction |
| Shared core | Rust | DSP, validation, domain logic |
| Flutter-Rust bridge | `flutter_rust_bridge` (evaluate) | Typed interop |
| Local database | SQLite | Presets, profiles, settings |
| Dart database access | `drift` (evaluate) | Typed queries and migrations |
| Preset interchange | JSON + JSON Schema or equivalent validation | Portable sharing |
| Windows audio | WASAPI / Windows audio APIs | Audio endpoint and stream integration |
| macOS audio | Core Audio | Audio device and stream integration |
| Linux audio | PipeWire; PulseAudio compatibility where needed | Audio routing and streams |
| Android audio | Android audio APIs | Mobile audio integration |
| iOS audio | AVAudioEngine / AVAudioSession | App-owned audio processing |
| Bluetooth Windows | Windows Bluetooth APIs | Supported discovery and metadata |
| Bluetooth macOS/iOS | CoreBluetooth | BLE interactions within OS rules |
| Bluetooth Linux | BlueZ | Bluetooth discovery and supported operations |
| Bluetooth Android | Android Bluetooth / BLE APIs | Discovery and supported operations |
| Testing | Rust tests, Flutter tests, integration tests | Correctness and regression prevention |
| CI | GitHub Actions (or equivalent) | Build, lint, test |

Library selection must be confirmed against current maintenance, licensing, platform coverage, and actual prototype results before locking dependencies.

## 2. Flutter

### Why Flutter
- Shared UI code across desktop and mobile.
- Strong widget and layout system.
- Responsive interfaces.
- Good fit for dashboards, sliders, device lists, and settings.
- Can call native functionality through plugins, platform channels, or FFI.

### Responsibilities
- App navigation and UI.
- EQ controls and preset editor.
- Device information display.
- Import/export workflows.
- Settings and permissions UX.
- Application state and use-case orchestration.

### Rules
- Keep DSP out of Dart.
- Keep native OS integration out of UI widgets.
- Use platform services behind repositories/interfaces.
- Do not assume all Flutter plugins support all five targets equally.

## 3. Rust

### Why Rust
- Strong memory safety.
- High performance for DSP and data processing.
- Good support for reusable libraries.
- Suitable for building a shared core with narrow native interfaces.

### Responsibilities
- DSP algorithms.
- Filter coefficient generation.
- EQ chain configuration.
- Audio parameter validation.
- Preset parsing and validation where appropriate.
- Shared device/capability domain models.
- Audio graph orchestration where appropriate.

### Suggested workspace crates
- `uam_domain`
- `uam_dsp`
- `uam_audio`
- `uam_device`
- `uam_preset`
- `uam_platform`
- `uam_ffi`

### Rust engineering requirements
- Keep the audio callback real-time safe.
- Avoid heap allocations in the callback.
- Avoid blocking mutexes in the callback.
- Validate all external parameters.
- Benchmark release builds.
- Use explicit error types.
- Keep FFI types stable and narrow.

## 4. Flutter-Rust Interoperability

**Phase 0 decision:** use a narrow, hand-written C ABI with Dart `dart:ffi`
(ADR-003). `flutter_rust_bridge` (evaluated at `2.14.0-beta.2`, MIT) remains a
candidate for a later phase if the control surface grows; it is deferred because
it is beta and adds a Dart codegen toolchain.

Evaluation criteria for any future switch:
- Supported Flutter/Dart and Rust versions.
- Desktop and mobile target support.
- Generated API stability.
- Async support for control operations.
- Clear memory ownership rules.
- Debugging and CI experience.

The C ABI currently exposes only `uam_abi_version`, `uam_get_engine_info`, and
`uam_string_free`, with UTF-8 JSON as the payload. Every payload is versioned and
validated on the Dart side.

Important: do not transfer real-time audio buffers frame-by-frame through
ordinary Dart method calls. The audio callback should run in the native/backend
layer.

## 5. Audio DSP

### Initial DSP components
- Biquad filter primitives.
- Peaking EQ.
- Low-shelf EQ.
- High-shelf EQ.
- Preamp/gain.
- Peak meter.
- Optional limiter.

### Later DSP components
- Compressor.
- Stereo width processing.
- Loudness analysis.
- Channel tools.
- Convolution or advanced spatial processing only after performance and licensing review.

### Implementation guidance
- Define sample rate and channel layout explicitly.
- Use stable coefficient calculations.
- Smooth parameter transitions to avoid clicks.
- Add clipping/peak monitoring.
- Test at common sample rates such as 44.1 kHz and 48 kHz, and additional rates when supported.
- Benchmark on low-power devices.

## 6. Platform Audio Backends

### Windows
Candidate: WASAPI and related Windows audio APIs.

Investigate:
- Render endpoint enumeration.
- Shared-mode and exclusive-mode trade-offs.
- Loopback capture and routing options.
- Device changes and endpoint notifications.
- Whether the chosen approach supports the intended processing scope.

### macOS
Candidate: Core Audio.

Investigate:
- Device enumeration.
- Audio unit/graph integration.
- Permissions and system extension requirements for any advanced routing.
- Apple Silicon behavior.

### Linux
Candidate: PipeWire, with PulseAudio compatibility as needed.

Investigate:
- PipeWire node enumeration and stream integration.
- Session manager behavior.
- Distribution differences.
- Permissions and packaging.

### Android
Candidate: Android audio APIs and applicable audio effect APIs.

Investigate:
- Output routing.
- Audio effect availability and restrictions.
- Bluetooth permission changes across Android versions.
- Background and lifecycle behavior.

### iOS
Candidate: AVAudioEngine and AVAudioSession.

Investigate:
- App-owned audio processing.
- Audio-session categories and interruptions.
- Background behavior.
- Restrictions on processing audio generated by unrelated apps.

## 7. Bluetooth and Hardware Integration

Use native adapters because Bluetooth capabilities differ by operating system and device.

Potential APIs:
- Windows Bluetooth and BLE APIs.
- CoreBluetooth on Apple platforms.
- BlueZ on Linux.
- Android Bluetooth and BLE APIs.

Important distinctions:
- Audio endpoint discovery is not the same as BLE scanning.
- Bluetooth pairing is not the same as vendor-control access.
- Battery information may be exposed inconsistently.
- ANC, transparency, touch controls, and firmware management may require vendor-specific protocols.
- Do not promise support without a tested adapter.

## 8. Local Database

### SQLite
Use SQLite for:
- Preset metadata.
- EQ filter rows or serialized validated configuration.
- Profiles.
- Device aliases.
- App settings.
- Migration history.

### Dart data layer
Evaluate Drift for:
- Typed Dart queries.
- Schema migrations.
- Reactive queries.
- Testability.

Alternative: direct SQLite bindings if the project needs tighter control or a different Rust-owned persistence boundary. Choose one primary database owner; avoid maintaining the same records independently in Dart and Rust.

### Data policy
- Database remains local.
- No account required.
- No automatic upload.
- Backup/export is user-initiated.
- Portable presets use JSON, not raw SQLite database files.

## 9. Preset Sharing

Format: `.uam-preset.json`

Requirements:
- Stable format identifier.
- Schema version.
- Metadata.
- Explicit units.
- Validated numeric ranges.
- Device-independent EQ settings by default.
- Compatibility warnings.
- No executable code, credentials, or arbitrary vendor commands.

Sharing channels:
- Local file save/open.
- Operating-system share sheet where available.
- User-selected messaging, email, cloud-drive, or file-hosting service.

Future option:
- An online community catalogue can be introduced as a separate optional service. It must not be required for local preset creation, import, export, or application.

## 10. State Management and Application Structure

Choose one Flutter state-management solution and apply it consistently. Riverpod is a reasonable candidate.

Suggested Dart boundaries:
- `presentation`: screens and widgets.
- `application`: use cases and state controllers.
- `domain`: Dart-facing domain contracts where needed.
- `data`: repositories and storage adapters.
- `platform`: Flutter/native platform service wrappers.
- `bridge`: generated Rust bindings.

Avoid duplicating domain rules in Dart and Rust. Define which layer owns each validation rule.

## 11. Testing and Quality

### Rust
- Unit tests for filters and parameter validation.
- Integration tests for DSP chains.
- Benchmarks for CPU and latency.
- Fuzz/property tests for preset parsers.

### Flutter
- Widget tests.
- State/use-case tests.
- Repository tests.
- Import/export flow tests.
- Accessibility checks.

### Platform
- Real-device tests for audio routing.
- Device disconnect/reconnect tests.
- Permission-denied tests.
- Sleep/wake and audio-session interruption tests.
- Hardware capability tests on a documented device matrix.

## 12. Tooling

Suggested tools:
- Flutter SDK and Dart SDK.
- Rust stable toolchain.
- Cargo workspace.
- `rustfmt` and Clippy.
- Flutter formatter and analyzer.
- Git.
- GitHub Actions or equivalent CI.
- Figma for UI/UX design.
- Issue tracker and ADR documents.

Pin toolchain versions for reproducible builds. Review dependency licenses and maintenance before release.

## 13. Dependency Policy

Before adding a dependency:
1. Confirm target platform support.
2. Check maintenance activity and release history.
3. Review license compatibility.
4. Review transitive dependencies.
5. Verify security advisories.
6. Prototype the exact required API.
7. Document why the dependency is needed.

Do not select a library solely because its README claims cross-platform support.

## 14. Recommended Initial Stack Lock

For the first prototype, use:
- Flutter stable.
- Dart.
- Rust stable.
- `flutter_rust_bridge` evaluation.
- SQLite.
- Drift evaluation for Dart-owned persistence.
- Rust DSP crate with a small initial filter set.
- Windows audio API prototype.
- GitHub Actions CI.

Do not lock all audio/Bluetooth dependencies until Phase 0 technical spikes are complete.
