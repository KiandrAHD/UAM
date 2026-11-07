/// Immutable application configuration for the Phase 0 shell.
abstract final class AppConfig {
  static const String applicationTitle = 'Universe Audio Management';
  static const String phaseLabel = 'Phase 0';
  static const String coreBuildHint =
      'Build the Rust core with scripts/build/build_rust.ps1';
  static const String processingScopeNotice =
      'Configuration only. Phase 0 does not attach UAM to a system audio '
      'output or process audio from other applications.';
  static const String deviceNotice =
      'Audio-device discovery and hardware controls are not implemented in '
      'Phase 0. They will be added behind capability-gated platform adapters.';
}
