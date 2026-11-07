/// Product and protocol constants that are stable across phases.
///
/// The core engine version is reported by Rust at runtime. It is deliberately
/// not duplicated here, so the UI cannot drift from the compiled core.
abstract final class AppConstants {
  static const String productName = 'Universe Audio Management';
  static const String appVersion = '0.1.0';
  static const String phaseLabel = 'Phase 1';
  static const int expectedBridgeAbiVersion = 1;
  static const String presetExtension = '.uam-preset.json';
  static const String presetMimeType = 'application/json';
  static const String ffiLibraryEnvironmentVariable = 'UAM_FFI_LIBRARY_PATH';
}
