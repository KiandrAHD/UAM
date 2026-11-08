# UAM Development Roadmap

**Product:** Universe Audio Management  
**Planning approach:** Milestone-based, capability-first, Windows-first validation  
**Status:** Proposed roadmap — dates should be assigned after technical spikes.

---

## 1. Roadmap Principles

1. Prove the audio engine and platform integration before expanding UI features.
2. Keep the Rust core independent from Flutter widgets and OS-specific APIs.
3. Build one working vertical slice before implementing every screen.
4. Use capability detection instead of assuming universal hardware support.
5. Keep local storage and preset sharing functional without a network connection.
6. Add platforms only after the relevant adapter passes acceptance tests.

## 2. Phase Overview

| Phase | Focus | Main outcome |
|---|---|---|
| 0 | Discovery and technical validation | Feasibility report and decisions |
| 1 | Foundation and UX | App shell, design system, repository |
| 2 | Rust core and DSP prototype | Tested audio-processing core |
| 3 | Local data and preset exchange | SQLite and portable preset files |
| 4 | Windows audio integration | First end-to-end desktop experience |
| 5 | Device and Bluetooth capability layer | Honest device information and supported controls |
| 6 | Linux and macOS adapters | Desktop platform expansion |
| 7 | Android | Mobile application and supported audio/device APIs |
| 8 | iOS | iOS-specific supported functionality |
| 9 | Beta, hardening, and release | Tested distribution builds |

## 3. Phase 0 — Discovery and Technical Validation

### Objectives
- Confirm the initial product boundaries.
- Investigate audio routing options on Windows.
- Validate Flutter-to-Rust interoperability.
- Research platform restrictions for Bluetooth and audio processing.
- Define the preset interchange schema.

### Tasks
- Write a platform capability matrix.
- Prototype a Rust DSP function and unit tests.
- Build a minimal Flutter screen that calls Rust.
- Test device/output enumeration on Windows.
- Compare candidate audio libraries and their licenses.
- Decide the first audio-processing scope: app-owned stream, selected application stream, or system-wide output.

### Deliverables
- Technical spike report.
- Initial architecture decisions (ADRs).
- MVP scope and acceptance criteria.
- Dependency/license inventory.

### Exit criteria
- A working Flutter-to-Rust call is demonstrated.
- A DSP prototype passes basic correctness tests.
- A feasible Windows output integration path is selected.
- Known platform limitations are documented.

### Phase 0 result (2026-11-07)

Status: **completed with documented blockers.**

- Flutter-to-Rust call: demonstrated through a real Dart FFI call into the
  compiled `uam_ffi.dll`.
- DSP: real RBJ biquad implementation (peaking, low/high shelf) plus preamp;
  41 Rust tests pass.
- Preset interchange: strict schema v1 with 3 valid and 8 invalid fixtures.
- Windows audio path: selected-stream loopback is the proposed first scope
  (ADR-006); device enumeration is proven, stream processing is not.
- Blockers: Flutter Windows desktop build and MSVC Rust linking need the Visual
  Studio C++ workload; Android toolchain is incomplete; macOS/Linux/iOS were not
  executed.

See `docs/PHASE_0_REPORT.md` for full evidence and next steps.

## 4. Phase 1 — Foundation and UX

### Objectives
Create the application skeleton and reusable UI foundation.

### Tasks
- Initialize a monorepo.
- Configure Flutter application targets.
- Create Rust workspace and core crate.
- Establish code formatting, linting, and test commands.
- Build navigation and responsive layouts.
- Create design tokens and reusable components.
- Add logging and structured error models.
- Set up CI for formatting, static analysis, and unit tests.

### Deliverables
- Running Flutter app shell.
- Rust core crate.
- Shared design system.
- CI pipeline.
- Initial developer documentation.

### Exit criteria
- App starts on the first target platform.
- Rust bridge is callable from Flutter.
- CI passes on every pull request.

### Phase 1 result (2026-11-07)

Status: **implemented and validated in the available Flutter/Rust test
environment; platform binaries still unverified.**

- Design system: centralized tokens, bundled Inter font, dark/light/system
  themes, shared cards, statuses, capability badges, headers, grids, response
  graph, and processing ring.
- Responsive shell: 238px desktop sidebar, 76px tablet icon sidebar with
  tooltips, mobile bottom navigation plus a More sheet, 78px/60px top bars, and
  breakpoints at 390, 760, and 1100 logical pixels.
- Modules: Dashboard, Device Manager, Equalizer, Audio Engine, Hardware
  Controls, Presets, and Settings are navigable through named routes.
- Truthful state: desired configuration, core acceptance, verified processing,
  processing scope, selected/active endpoint, connection, and capability
  availability stay distinct. No fake devices or invented runtime evidence.
- Presets: bundled entries mirror `presets/examples/`; schema-v1 imports are
  validated locally; persistence is deferred.
- Validation: `flutter analyze` clean; 68 Flutter tests, 41 Rust tests, and 3
  valid / 8 invalid preset fixtures pass. Windows/Android/iOS/macOS/Linux
  binaries were not built because the required workloads are unavailable.

See `docs/PHASE_1_REPORT.md` for full evidence and limitations.

## 5. Phase 2 — Rust Core and DSP Prototype

### Objectives
Implement a deterministic, testable audio-processing core.

### Tasks
- Define audio sample formats and channel layouts.
- Define DSP configuration models.
- Implement biquad filter primitives.
- Implement peaking, low-shelf, and high-shelf filters.
- Implement a configurable EQ chain.
- Implement preamp/gain with clipping awareness.
- Prototype limiter behavior.
- Add bypass and reset behavior.
- Benchmark CPU use and processing latency.
- Ensure real-time audio callbacks avoid locks, allocations, and blocking work.

### Deliverables
- Rust DSP crate.
- Documented parameter ranges.
- Unit tests and benchmark results.
- Flutter integration for editing DSP parameters.

### Exit criteria
- DSP tests pass for supported sample rates and channel layouts.
- No unexpected NaN/infinite values for validated inputs.
- Parameter updates do not block the audio callback.
- Performance is acceptable on the MVP reference machine.

### Progress (2026-11-08) — Phase 2.1–2.3 + 2.6

- **Done (2.1–2.2):** audio sample-format and channel model (`SampleFormat`
  boundary vs internal `f64` representation); validated DSP configuration DTO
  (`DspConfig`, `LimiterConfig`); control-thread
  `Equalizer::from_config`/`apply_config` with failure-safe replacement;
  documented value ranges; real-time hand-off design recorded in
  `docs/adr/ADR-007`.
- **Done (2.3A–2.3D):** `Preset::to_dsp_config` adapter; `PeakMeter` sample-peak
  and clipping detection; feed-forward, zero-look-ahead, channel-linked
  `Limiter`; `DspPipeline` with input/pre-limiter/output reports; non-finite,
  subnormal, long-run, invalid-block, and steady-state allocation regression
  tests.
- **Done (2.6):** Criterion benchmark suite and measured reference-machine
  results. Stereo 10-band EQ + limiter at 48 kHz/256 frames uses 254.70 ns/frame
  (1.223 % of one core), meeting the < 2 % target.
- **Exit criteria met:** DSP tests pass for mono/stereo (127 Rust tests); no
  unexpected NaN/inf after containment; performance target met on the reference
  machine.
- **Still open:** parameter hand-off to a live callback, crossfade/ramping,
  FFI DSP symbols, Flutter DSP controller, and an audio backend. Therefore
  Phase 2 is still not fully complete.
- See `docs/PHASE_2_3_IMPLEMENTATION_REPORT.md` for evidence,
  `docs/PHASE_2_3_DESIGN.md` for guarantees/limits, and
  `docs/PHASE_2_READINESS.md` for the updated gap list.

## 6. Phase 3 — Local Data and Preset Exchange

### Objectives
Make UAM useful offline and enable user-to-user configuration sharing.

### Tasks
- Add SQLite schema and migration mechanism.
- Store presets, profile metadata, preferences, and device aliases.
- Implement preset CRUD.
- Define and validate `uam-preset` JSON schema.
- Implement export and import.
- Add preview and compatibility warnings.
- Implement backup/restore for local configuration.
- Add schema migration tests.

### Deliverables
- Local persistence layer.
- Versioned preset schema.
- Import/export workflow.
- Sample preset fixtures.

### Exit criteria
- Users can manage presets offline.
- Exported presets can be imported on another installation.
- Invalid or oversized files are rejected safely.
- Schema version is checked and unsupported versions produce a clear message.

## 7. Phase 4 — Windows Audio Integration

### Objectives
Connect the DSP engine to a real audio path on Windows.

### Tasks
- Select and implement the Windows audio backend.
- Enumerate render endpoints.
- Handle device changes and endpoint removal.
- Implement stream lifecycle and graceful shutdown.
- Connect DSP processing to the selected supported audio path.
- Expose bypass and processing status in UI.
- Add latency, CPU, and glitch instrumentation.
- Document whether the implementation is system-wide or limited to a specific stream.

### Deliverables
- Working Windows audio-processing vertical slice.
- Device selection UI.
- Diagnostics panel.
- Windows integration tests.

### Exit criteria
- Audio passes through the selected path.
- EQ changes are audible and measurable.
- Device switching and disconnection do not crash the app.
- Processing can be bypassed safely.
- Scope of audio capture/routing is clearly communicated.

## 8. Phase 5 — Device and Bluetooth Capability Layer

### Objectives
Introduce device metadata and hardware-control abstractions.

### Tasks
- Define normalized device model.
- Define capability model for battery, ANC, transparency, touch controls, and codec data.
- Implement platform discovery adapter for Windows where supported.
- Distinguish OS audio endpoint enumeration from Bluetooth radio scanning.
- Add permission handling and user-facing explanations.
- Add a hardware adapter registry.
- Implement only documented or validated device-control integrations.
- Add adapter conformance tests and capability provenance.

### Deliverables
- Device domain model.
- Capability registry.
- Initial platform adapter.
- Unsupported-feature UX.

### Exit criteria
- No unsupported feature is shown as operational.
- Device metadata is traceable to its source.
- Adapter failures are isolated from the audio engine.
- User can understand why a feature is unavailable.

## 9. Phase 6 — Linux and macOS

### Linux tasks
- Implement PipeWire integration, with PulseAudio compatibility where required.
- Evaluate BlueZ for Bluetooth discovery and exposed metadata.
- Test on representative distributions and desktop environments.
- Document permissions, packaging, and audio-server requirements.

### macOS tasks
- Implement Core Audio integration.
- Evaluate CoreBluetooth for supported discovery/control use cases.
- Respect app sandboxing, permissions, and entitlement requirements.
- Test Apple Silicon and supported macOS versions.

### Exit criteria
- Platform-specific audio adapter tests pass.
- Installation and permission documentation is complete.
- Unsupported capabilities are handled gracefully.

## 10. Phase 7 — Android

### Objectives
Deliver a mobile version using supported Android APIs.

### Tasks
- Implement Android audio output/device information integration.
- Investigate Bluetooth permissions by Android API level.
- Implement BLE scanning only where justified and permission-compliant.
- Validate audio effects and processing scope.
- Test device routing, foreground/background behavior, and battery impact.
- Create mobile-specific layouts and lifecycle handling.

### Exit criteria
- App works within Android permission and lifecycle rules.
- Audio features are accurately scoped.
- Bluetooth discovery and device controls are tested on representative hardware.

## 11. Phase 8 — iOS

### Objectives
Deliver the iOS experience within Apple's supported audio and Bluetooth APIs.

### Tasks
- Implement AVAudioSession/AVAudioEngine paths for audio owned by UAM.
- Evaluate CoreBluetooth use cases and required permissions.
- Document limitations for third-party headphone controls.
- Validate background audio behavior and session interruptions.
- Avoid claiming unrestricted system-wide EQ.

### Exit criteria
- App behaves correctly under audio-session interruptions.
- iOS feature matrix is documented.
- Only supported controls are presented.

## 12. Phase 9 — Beta, Hardening, and Release

### Tasks
- Security review of import/export.
- Crash and performance testing.
- Accessibility review.
- Cross-platform regression tests.
- Installer/package creation.
- Release notes and user documentation.
- Privacy policy if any optional online service or analytics is introduced.
- Beta feedback and issue triage.

### Release gates
- No known critical data-loss or audio-safety defects.
- Preset interchange tests pass.
- Platform capability matrix is published.
- Installer and update strategy are documented.
- All release builds are reproducible.

## 13. Suggested MVP Backlog

| ID | Task | Priority |
|---|---|---|
| MVP-01 | Create Flutter/Rust monorepo | P0 |
| MVP-02 | Flutter-to-Rust bridge | P0 |
| MVP-03 | Rust DSP biquad filters | P0 |
| MVP-04 | EQ editor UI | P0 |
| MVP-05 | SQLite local storage | P0 |
| MVP-06 | Preset CRUD | P0 |
| MVP-07 | JSON export/import validation | P0 |
| MVP-08 | Windows output enumeration | P0 |
| MVP-09 | Windows audio processing path | P0 |
| MVP-10 | Device capability model | P1 |
| MVP-11 | Bluetooth metadata adapter | P1 |
| MVP-12 | ANC/transparency vendor integration | P2 |

## 14. Delivery Management

For each phase:
- Create a short design note before introducing a platform-specific dependency.
- Keep tasks small enough to review and test independently.
- Require tests for domain logic and file parsing.
- Record decisions in `docs/adr/`.
- Do not mark a feature complete based only on UI implementation; require a working adapter and platform test.
- Update `docs/COMPATIBILITY.md` whenever a platform capability changes.

## 15. Definition of Done

A feature is done only when:
1. Requirements and limitations are documented.
2. Implementation is separated into appropriate modules.
3. Unit and integration tests pass.
4. Error and unsupported states are handled.
5. UI accurately reflects the feature's real capability.
6. Documentation and compatibility matrix are updated.
7. No secrets or personal data are added to logs or portable presets.
