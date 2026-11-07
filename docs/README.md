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
11. `adr/` — Architecture Decision Records (ADR-001 through ADR-006).
12. `platform/` — Per-platform notes for Windows, macOS, Linux, Android, and iOS.
13. `testing/` — Test strategy, audio testing method, and hardware matrix.

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
