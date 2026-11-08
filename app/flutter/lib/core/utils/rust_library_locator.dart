import 'dart:io';

import '../constants/app_constants.dart';

/// Locates the UAM native library without hard-coded machine paths.
///
/// Resolution order:
/// 1. Explicit path supplied by the caller (tests and desktop bundles).
/// 2. `UAM_FFI_LIBRARY_PATH` environment variable.
/// 3. Android: the bundled SONAME resolved by the Android dynamic linker.
/// 4. Other platforms: platform bundle name next to the executable / current
///    directory, then monorepo Cargo output directories for development.
abstract final class RustLibraryLocator {
  /// Returns an argument suitable for `DynamicLibrary.open`, or null when no
  /// candidate is present.
  ///
  /// On Android this is the bare bundled SONAME (`libuam_ffi.so`), not a
  /// filesystem path: the library is packaged inside the APK and installed into
  /// the application native library directory, which is searched by the Android
  /// dynamic linker. On desktop platforms it is an absolute or relative path to
  /// a file that exists.
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

    if (Platform.isAndroid) {
      // A packaged Android library is not visible on the Dart filesystem.
      // Return the SONAME unconditionally so the loader can attempt a load;
      // a genuine failure surfaces as an `ArgumentError` from
      // `DynamicLibrary.open`.
      //
      // `DynamicLibrary.process()` is deliberately NOT used: it resolves
      // symbols from the already-loaded global symbol table (RTLD_DEFAULT), and
      // a bundled library is not guaranteed to be loaded before this call.
      return AppConstants.androidNativeLibraryName;
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
      'windows' => AppConstants.windowsNativeLibraryName,
      'macos' => AppConstants.macosNativeLibraryName,
      _ => AppConstants.linuxNativeLibraryName,
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
