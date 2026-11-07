import 'dart:io';

import '../constants/app_constants.dart';

/// Locates the UAM native library without hard-coded machine paths.
///
/// Resolution order:
/// 1. Explicit path supplied by the caller (tests and desktop bundles).
/// 2. `UAM_FFI_LIBRARY_PATH` environment variable.
/// 3. Platform bundle name next to the executable / current directory.
/// 4. Monorepo Cargo output directories for development.
abstract final class RustLibraryLocator {
  /// Returns a path that exists, or null when no candidate is present.
  static String? resolve({String? explicitPath}) {
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath).existsSync() ? explicitPath : null;
    }

    final environmentPath =
        Platform.environment[AppConstants.ffiLibraryEnvironmentVariable];
    if (environmentPath != null &&
        environmentPath.isNotEmpty &&
        File(environmentPath).existsSync()) {
      return environmentPath;
    }

    for (final candidate in _candidates()) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static Iterable<String> _candidates() sync* {
    final operatingSystem = Platform.operatingSystem;
    final bundleName = switch (operatingSystem) {
      'windows' => 'uam_ffi.dll',
      'macos' => 'libuam_ffi.dylib',
      _ => 'libuam_ffi.so',
    };
    final relativeDirectories = <String>[
      '.',
      'crates/target/debug',
      'crates/target/release',
      '../../crates/target/debug',
      '../../crates/target/release',
      '../../../crates/target/debug',
      '../../../crates/target/release',
    ];
    for (final directory in relativeDirectories) {
      yield directory == '.'
          ? bundleName
          : '$directory${Platform.pathSeparator}$bundleName';
    }
  }
}
