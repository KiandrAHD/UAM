# ADR-001: Flutter for the shared user interface

- **Status:** Accepted
- **Date:** 2026-11-07
- **Supersedes:** none

## Context

UAM targets Windows, macOS, Linux, Android, and iOS. Rebuilding the UI five
times is not sustainable for a small team. The product needs a dashboard,
device lists, EQ sliders, a preset editor, and settings, all of which are
conventional, form-heavy interfaces rather than novel rendering.

The UI must not own DSP or operating-system integration; it must display
application state and call typed use cases.

## Decision

Use Flutter (stable channel) for all five target platforms. Dart owns the
presentation and application layers only:

- Widgets and navigation.
- Use cases and application state.
- Calls to the Flutter–Rust bridge and repositories.

Dart must not implement DSP algorithms and must not call operating-system APIs
directly from widgets.

## Consequences

Positive:

- One UI codebase for desktop and mobile.
- Mature widget and layout system for control-heavy screens.
- `dart:ffi` and platform channels cover the native integration UAM needs.
- Analyzer and widget tests are available in CI.

Negative:

- Flutter desktop on Windows requires the Visual Studio C++ build tools; this
  host does not yet have that workload, so the desktop binary is not built yet
  (see `docs/platform/WINDOWS.md`).
- Desktop binary size and startup cost are higher than a native toolkit.
- Mobile operating-system restrictions on system-wide audio still apply
  regardless of the UI toolkit.

## Evidence

- Application shell created at `app/flutter/`; `flutter analyze` and
  `flutter test` pass (10 tests).
- Analyzer lint rules configured in `app/flutter/analysis_options.yaml`.
- Widget test at `app/flutter/test/widget/uam_app_test.dart` verifies the shell
  renders engine information from the core.
