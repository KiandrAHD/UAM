# Product Requirements Document (PRD)
## Universe Audio Management (UAM)

**Status:** Draft v1.0  
**Product type:** Cross-platform audio management application  
**Target platforms:** Windows, macOS, Linux, Android, iOS  
**Primary technologies:** Flutter, Rust  
**Compatibility strategy:** Universal-first

---

## 1. Executive Summary

Universe Audio Management (UAM) is a local-first, cross-platform application for managing and customizing audio devices and listening experiences. It combines two product capabilities:

1. **Audio Processing:** equalization, gain management, filters, dynamics processing, audio analysis, and user-defined sound profiles.
2. **Hardware Control:** device discovery and information, connection-related status, battery reporting, and supported hardware features such as ANC or transparency modes where accessible through documented operating-system or vendor interfaces.

UAM aims to provide a consistent experience across Windows, macOS, Linux, Android, and iOS without depending on one audio-device manufacturer. Common features should work across supported platforms, while hardware-specific functions are exposed only when the connected device and platform provide a reliable control path.

UAM is local-first. Device metadata, preferences, and presets are stored on the user's device. Users can export and import configuration files to share settings with other people. Cloud accounts are not required for core functionality.

## 2. Product Vision

**Vision:** One platform to manage audio devices and shape the listening experience, regardless of device brand.

**Product promise:** Give users a clear, honest, and accessible way to customize audio while respecting operating-system and hardware limitations.

**Suggested tagline:** *One Platform. Every Audio Device. Your Sound, Your Rules.*

## 3. Problem Statement

Users commonly encounter several problems:

- Audio settings are spread across operating-system controls, device utilities, and manufacturer applications.
- Many inexpensive or older audio devices do not have a dedicated companion application.
- Equalizer and sound-enhancement tools differ by operating system.
- Manufacturer applications may support only selected product families.
- Users cannot easily move their preferred EQ configuration between devices or share it with others.
- Device features such as battery reporting, ANC, and touch controls are inconsistently exposed.

UAM addresses these problems with a unified interface, a portable audio-processing core, capability-aware hardware integrations, and portable configuration sharing.

## 4. Goals

### 4.1 Product Goals

- Deliver a consistent Flutter application experience on five target operating systems.
- Build a reusable Rust core for audio DSP and shared domain logic.
- Provide practical audio controls such as equalizer bands, preamp/gain, bass and treble shaping, and safe output limiting.
- Discover and display audio devices where platform APIs allow.
- Expose hardware controls only when a supported protocol/API is available.
- Store user data locally by default.
- Support portable export/import of presets and device-independent configurations.
- Make platform and device limitations visible rather than silently failing.

### 4.2 Non-Goals for the Initial Release

- Guaranteeing ANC, transparency, touch remapping, firmware updates, or multipoint control on every brand.
- Circumventing vendor encryption, proprietary protocols, or operating-system security boundaries.
- Replacing the operating system's complete audio stack.
- Providing unrestricted system-wide audio processing on iOS.
- Requiring user accounts, cloud sync, or a hosted database for core functionality.
- Uploading device telemetry or personal audio data without explicit consent.

## 5. Target Users

### 5.1 Everyday Listener
Wants a simple way to adjust bass, treble, clarity, and saved sound profiles.

### 5.2 Audio Enthusiast
Wants precise EQ control, custom filters, presets, analysis tools, and repeatable configurations.

### 5.3 Multi-Device User
Uses different earbuds, headphones, headsets, and speakers across computers and phones.

### 5.4 Community Preset Creator
Creates and shares EQ configurations with other UAM users.

## 6. Core User Journeys

### Journey A — Customize Audio
1. User opens UAM.
2. User selects an available audio output or processing target.
3. UAM checks the platform's audio-processing capabilities.
4. User chooses a preset or adjusts EQ bands.
5. User previews/applies the configuration.
6. UAM saves the profile locally.

### Journey B — Inspect a Device
1. User opens Device Manager.
2. UAM lists devices discoverable through supported OS APIs.
3. User selects a device.
4. UAM displays available metadata, connection state, and battery data if exposed.
5. UAM lists hardware controls only if a supported control adapter is available.

### Journey C — Share a Preset
1. User opens a saved preset.
2. User selects Export.
3. UAM creates a versioned `.uam-preset.json` file.
4. User sends the file using any channel.
5. Another user imports the file.
6. UAM validates schema, values, and compatibility before saving it locally.

### Journey D — Use a Shared Preset
1. User receives a preset file or a shared preset link that resolves to a file.
2. User previews its name, author metadata, EQ curve, and notes.
3. UAM validates the file and displays warnings if required features are unsupported.
4. User imports and applies it manually.

## 7. Functional Requirements

Priority definitions:
- **P0:** Required for the first usable MVP.
- **P1:** Important follow-up capability.
- **P2:** Advanced or later capability.

### 7.1 Application Foundation

| ID | Requirement | Priority |
|---|---|---|
| APP-001 | Provide a consistent navigation structure and responsive layouts. | P0 |
| APP-002 | Support light, dark, and system appearance preferences. | P1 |
| APP-003 | Display platform-specific capability and permission explanations. | P0 |
| APP-004 | Provide clear loading, empty, success, and error states. | P0 |
| APP-005 | Keep core functionality usable without signing in. | P0 |

### 7.2 Device Manager

| ID | Requirement | Priority |
|---|---|---|
| DEV-001 | List audio devices available through supported platform APIs. | P0 |
| DEV-002 | Display device name, type, and available connection/output metadata. | P0 |
| DEV-003 | Show connection state where the OS exposes it. | P1 |
| DEV-004 | Show left/right/case battery only when reliably exposed. | P1 |
| DEV-005 | Display codec and transport information only when available. | P2 |
| DEV-006 | Distinguish audio-device discovery from Bluetooth radio scanning. | P0 |
| DEV-007 | Show device-specific control capabilities and their source. | P1 |

### 7.3 Audio Processing

| ID | Requirement | Priority |
|---|---|---|
| AUD-001 | Provide a configurable multi-band equalizer. | P0 |
| AUD-002 | Provide preamp/output gain control with safe limits and clipping warnings. | P0 |
| AUD-003 | Provide bass and treble shaping presets. | P0 |
| AUD-004 | Allow users to create, rename, duplicate, and delete presets. | P0 |
| AUD-005 | Provide bypass and reset controls. | P0 |
| AUD-006 | Implement output peak monitoring and a limiter option. | P1 |
| AUD-007 | Add compressor and stereo-width controls where technically appropriate. | P2 |
| AUD-008 | Provide audio analysis and channel test utilities. | P2 |
| AUD-009 | Clearly identify whether processing is app-local, stream-specific, or system-wide. | P0 |

### 7.4 Hardware Control

| ID | Requirement | Priority |
|---|---|---|
| HW-001 | Use platform adapters for hardware discovery and control. | P0 |
| HW-002 | Report only controls confirmed as supported. | P0 |
| HW-003 | Support ANC/transparency control when a documented or validated adapter exists. | P2 |
| HW-004 | Support touch-control configuration only for explicitly supported devices. | P2 |
| HW-005 | Never send undocumented commands by default. | P0 |
| HW-006 | Explain unavailable controls and the reason where known. | P0 |

### 7.5 Preset and Configuration Management

| ID | Requirement | Priority |
|---|---|---|
| CFG-001 | Store presets and preferences locally. | P0 |
| CFG-002 | Export a preset to a versioned JSON file. | P0 |
| CFG-003 | Import and validate a preset JSON file. | P0 |
| CFG-004 | Preview imported preset metadata before saving. | P1 |
| CFG-005 | Warn about unsupported bands, filters, or device-specific settings. | P0 |
| CFG-006 | Support backup and restore of user configuration. | P1 |
| CFG-007 | Include schema version and application compatibility metadata. | P0 |
| CFG-008 | Allow users to share files through their own messaging or file-sharing services. | P0 |

### 7.6 Audio Laboratory

| ID | Requirement | Priority |
|---|---|---|
| LAB-001 | Provide left/right channel test. | P2 |
| LAB-002 | Provide frequency sweep and tone generator with safe defaults. | P2 |
| LAB-003 | Provide microphone input test where permitted. | P2 |
| LAB-004 | Provide hearing-related calibration only with appropriate safety guidance. | P2 |
| LAB-005 | Avoid claiming medical-grade hearing assessment. | P0 |

## 8. Non-Functional Requirements

### Performance
- UI interactions should remain responsive during audio processing.
- Audio processing must avoid blocking the Flutter UI thread.
- Audio callbacks must avoid memory allocation, locks, and unpredictable work where possible.
- DSP should be benchmarked for CPU use, latency, and glitch-free operation.

### Reliability
- Invalid or incompatible presets must not crash the application.
- Hardware-control failures must leave the device in a safe state.
- Unsupported capabilities must degrade gracefully.
- Configuration writes should be atomic where practical.

### Security and Privacy
- Local-first storage is the default.
- Do not collect audio content.
- Do not store Bluetooth pairing secrets or OS credentials in ordinary application tables.
- Validate imported files and enforce size/value limits.
- If online sharing is introduced, require explicit user action and clear privacy controls.

### Accessibility
- Provide keyboard navigation on desktop.
- Provide accessible labels for sliders and controls.
- Do not rely on color alone to communicate status.
- Respect platform text scaling where possible.

### Portability
- Keep DSP algorithms and domain models platform-independent.
- Isolate native OS APIs behind adapters.
- Use versioned interchange formats for shared presets.

## 9. Compatibility Model

UAM uses a **universal-first, capability-based** model.

### Universal baseline
- Local preset management.
- EQ configuration editing.
- Portable preset import/export.
- Device-independent profile management.
- UI and audio analysis features that do not require privileged system integration.

### Platform-dependent
- System-wide audio processing.
- Output device enumeration details.
- Bluetooth scanning and metadata.
- Battery reporting.
- Codec information.
- Hardware controls such as ANC and touch remapping.

A feature is considered supported only after it passes platform-specific tests. A Bluetooth connection does not automatically imply access to proprietary earbud controls.

## 10. Preset File Format

Suggested extension: `.uam-preset.json`

Example:

```json
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": {
    "name": "Balanced Warm",
    "author": "UAM User",
    "description": "A balanced profile with gentle low-frequency warmth.",
    "createdAt": "2026-01-01T00:00:00Z",
    "tags": ["balanced", "warm"]
  },
  "compatibility": {
    "minimumUamVersion": "0.1.0",
    "deviceIndependent": true
  },
  "audio": {
    "preampDb": -2.0,
    "equalizer": {
      "type": "peaking",
      "bands": [
        { "frequencyHz": 60, "gainDb": 2.0, "q": 1.0 },
        { "frequencyHz": 250, "gainDb": 1.0, "q": 1.0 },
        { "frequencyHz": 1000, "gainDb": 0.0, "q": 1.0 },
        { "frequencyHz": 4000, "gainDb": -1.0, "q": 1.0 },
        { "frequencyHz": 10000, "gainDb": 1.5, "q": 1.0 }
      ]
    }
  }
}
```

This is an illustrative interchange format. The final schema must define allowed ranges, filter types, units, required fields, and validation rules. Device-specific commands must not be embedded in portable presets.

## 11. Local Data Strategy

UAM should use a local database for application state and separate portable files for sharing.

Recommended initial design:
- **SQLite:** structured local records such as presets, profile metadata, app preferences, and device aliases.
- **JSON files:** portable preset exchange and backup.
- **No mandatory cloud database:** the app must work offline.
- **Optional future sharing service:** a separately deployable catalogue for public/community presets, not required for local functionality.

Do not treat a Bluetooth MAC address or other hardware identifier as a universal, stable identity. Use platform-provided identifiers where available and keep device matching best-effort.

## 12. MVP Scope

The MVP should prove the product's core architecture before expanding to every OS.

### MVP includes
- Flutter application shell and navigation.
- Rust core library connected to Flutter.
- Local SQLite persistence.
- Preset CRUD.
- Versioned JSON export/import.
- Equalizer editor and DSP prototype.
- One desktop platform audio backend (recommended: Windows first).
- Device/output enumeration through the selected platform backend.
- Capability reporting and clear unsupported-feature states.

### MVP excludes
- Guaranteed vendor-specific ANC controls.
- Firmware updates.
- Community cloud catalogue.
- Account system.
- Automatic cross-device cloud synchronization.
- Medical hearing assessment.

## 13. MVP Acceptance Criteria

The MVP is acceptable when:

1. The app launches and displays the main dashboard.
2. Flutter can call the Rust core through a stable bridge.
3. Users can create, edit, duplicate, delete, export, and import presets.
4. Imported files are validated and invalid files are rejected safely.
5. EQ changes are reflected in the DSP prototype's output path.
6. The app clearly identifies the audio processing scope and selected output.
7. Device information is shown only when returned by the platform adapter.
8. The application works offline for all MVP functions.
9. No unsupported hardware controls are presented as working features.
10. Automated tests cover core preset validation and DSP parameter handling.

## 14. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| OS audio APIs differ | Uneven feature support | Platform adapter architecture and capability matrix |
| iOS system-wide processing restrictions | Product expectation mismatch | Define iOS scope honestly; focus on app-owned audio paths and supported APIs |
| Vendor protocols are proprietary | Hardware controls unavailable | Prioritize documented protocols and validated integrations |
| Audio glitches or latency | Poor listening experience | Real-time-safe Rust DSP design and platform benchmarks |
| Preset incompatibility | Failed imports or unexpected sound | Versioned schema, validation, preview, and migration |
| Scope becomes too large | Delayed release | Windows-first MVP and release gates |

## 15. Product Success Metrics

- Successful preset creation and application rate.
- Preset import/export success rate.
- DSP processing stability and measured glitch rate.
- Audio processing latency and CPU utilization by platform.
- Device discovery success rate by platform.
- Percentage of displayed hardware controls that pass validation.
- Crash-free sessions.
- User-reported ease of creating and sharing presets.

## 16. Open Decisions

These decisions should be validated during technical spikes:
- Exact audio backend/library for each platform.
- Whether the first Windows MVP processes a selected app stream or the full system output.
- Flutter-to-Rust bridge approach and generated bindings strategy.
- Initial EQ band model and supported filter types.
- Linux packaging and audio-server support matrix.
- iOS product scope within Apple's audio-session restrictions.
- Whether future community sharing uses a hosted service, static catalogue, or user-provided links.
