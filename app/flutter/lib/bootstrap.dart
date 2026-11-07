import 'package:flutter/widgets.dart';

import 'app/uam_app.dart';
import 'bridge/rust_api.dart';
import 'core/logging/app_logger.dart';

/// Initializes bindings and starts the Phase 0 application shell.
///
/// The Rust bridge is loaded lazily by [RustApi]; a missing native library is
/// reported in the UI instead of crashing the process.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.info('Starting UAM Phase 0 prototype');
  runApp(UamApp(engineInfoGateway: RustApi()));
}
