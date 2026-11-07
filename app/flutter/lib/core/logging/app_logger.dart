import 'package:flutter/foundation.dart';

/// Minimal diagnostic logger for the Phase 0 shell.
///
/// Only development builds emit messages. Callers must not pass audio samples,
/// credentials, private file paths, or device identifiers.
abstract final class AppLogger {
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('[UAM][INFO] $message');
    }
  }

  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('[UAM][WARN] $message');
    }
  }

  static void error(String message) {
    if (kDebugMode) {
      debugPrint('[UAM][ERROR] $message');
    }
  }
}
