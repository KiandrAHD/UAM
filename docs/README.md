# Universe Audio Management (UAM) — Project Blueprint

**Product codename:** UAM  
**Product category:** Universal Audio Management & Customization Platform  
**Primary stack:** Flutter + Rust  
**Compatibility strategy:** Universal-first  
**Document language:** English

## Included documents

1. `PRD.md` — Product vision, requirements, scope, user stories, and acceptance criteria.
2. `Roadmap.md` — Phased delivery plan, milestones, dependencies, and release gates.
3. `Architecture.md` — System architecture, module boundaries, platform adapters, and data flows.
4. `Tech_Stack.md` — Technology choices, libraries to evaluate, and implementation guidance.
5. `Structure_File.md` — Proposed monorepo layout and responsibilities of key directories.
6. `COMPATIBILITY.md` — Five-platform capability matrix with honest status labels.
7. `DEVELOPMENT.md` — Setup, build, test, and troubleshooting guide.
8. `DEPENDENCY_AUDIT.md` — Phase 0 dependency and license inventory.
9. `PHASE_0_REPORT.md` — Phase 0 results, evidence, blockers, and next steps.
10. `PHASE_1_REPORT.md` — Phase 1 foundation, responsive UX, state model, tests, and limitations.
11. `PHASE_1_1_REPORT.md` — Phase 1.1 stabilization audit and (updated) Windows closure.
12. `PHASE_2_READINESS.md` — Phase 2 DSP gap audit and proposed design.
13. `PHASE_2_IMPLEMENTATION_REPORT.md` — Phase 2.1–2.2 DSP configuration foundation, evidence, and next steps.
14. `PHASE_2_3_DESIGN.md` — Phase 2.3A–2.3D + 2.6 technical design and explicit guarantees/limitations.
15. `PHASE_2_3_IMPLEMENTATION_REPORT.md` — Phase 2.3 and 2.6 implementation status, validation evidence, and remaining work.
16. `adr/` — Architecture Decision Records (ADR-001 through ADR-007).
17. `platform/` — Per-platform notes for Windows, macOS, Linux, Android, and iOS.
18. `testing/` — Test strategy, audio testing method, hardware matrix, and measured DSP benchmarks (`BENCHMARKS.md`).
19. `ANDROID_SETUP.md` — Android SDK/NDK setup, Rust target installation, build script usage, native library packaging, and device testing.
20. `ANDROID_BUILD_REPORT.md` — Android platform-support implementation status, build evidence, ABI verification, and explicit limitations.
21. `PHASE_2_7_STABILIZATION_REPORT.md` — Android CI root-cause repair, local cross-compilation/APK evidence, Windows/Rust/Flutter regressions, and deferred device validation.
22. `platform/ANDROID.md` — Android capability and validation notes.
23. `BRANDING.md` — official UAM logo source, generated platform icons, regeneration, and validation.
24. `DATABASE_DESIGN.md` — implemented SQLite v1 schema, connection policy, and validation.
25. `DATABASE_MIGRATIONS.md` — migration/versioning policy and failure behavior.
26. `PRESET_EXCHANGE.md` — schema-v1 import/export and duplicate-resolution behavior.
27. `BACKUP_RESTORE.md` — backup container, checksum, and restore workflow.
28. `PHASE_3_IMPLEMENTATION_REPORT.md` — implementation scope, evidence, usage, and limitations.
29. `PHASE_3_READINESS.md` — Phase 3 readiness gates, evidence, and remaining platform validation.

## Core product decisions

- UAM is designed for Windows, macOS, Linux, Android, and iOS.
- Audio processing and hardware control are both product goals.
- Universal compatibility means common audio features should work wherever the operating system permits them. Vendor-specific hardware controls are capability-gated and must never be falsely advertised as universally available.
- User settings, device profiles, and presets are stored locally by default.
- Presets can be exported and imported as portable files. Sharing does not require an account or cloud database.
- A future optional community catalogue may be added, but it must be separate from the local-first core.

## Important feasibility principle

A cross-platform UI does not imply unrestricted system-wide audio processing or complete access to every Bluetooth device feature. Each operating system exposes different audio and Bluetooth APIs. UAM must use platform adapters, report capability limitations clearly, and provide graceful fallbacks.

## Suggested first implementation target

Start with **Windows desktop** to validate the Rust audio engine, device selection, processing pipeline, local preset persistence, and application UX. Keep interfaces portable so Linux and macOS adapters can follow. Android and iOS require separate feasibility validation before promising system-wide processing or third-party hardware control.
