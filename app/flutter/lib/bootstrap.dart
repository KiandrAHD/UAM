import 'package:flutter/widgets.dart';

import 'app/services/uam_services.dart';
import 'app/state/uam_app_controller.dart';
import 'app/uam_app.dart';
import 'bridge/rust_api.dart';
import 'core/database/app_setting_keys.dart';
import 'core/database/database_exception.dart';
import 'core/logging/app_logger.dart';

/// Initializes bindings, opens the local SQLite database, loads the persisted
/// appearance, and starts the UAM application shell.
///
/// Startup order (see `docs/DATABASE_DESIGN.md`):
/// 1. database initialization (open + migrate + integrity check);
/// 2. persisted settings read (theme, reduced motion, launch-at-startup);
/// 3. presets loaded and the active preset resolved by the controller;
/// 4. the persisted appearance is applied on the first frame.
///
/// If the database cannot be initialized the process renders an explicit,
/// recoverable error screen. UAM never substitutes volatile in-memory storage.
///
/// The Rust bridge is loaded lazily by [RustApi]; a missing native library is
/// reported in the UI instead of crashing the process.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.info('Starting UAM');

  final UamServices services;
  try {
    services = await UamServices.initialize();
  } on UamDataException catch (error) {
    AppLogger.error('Local database initialization failed: ${error.code.name}');
    runApp(UamBootstrapErrorApp(message: error.message));
    return;
  } catch (_) {
    AppLogger.error(
      'Local database initialization failed with an unknown error.',
    );
    runApp(
      const UamBootstrapErrorApp(
        message: 'The UAM local database could not be initialized.',
      ),
    );
    return;
  }

  // Read the persisted appearance before the first frame so there is no visible
  // flash from the default theme to the saved theme.
  final theme = UamThemePreference.fromWire(
    await services.settings.get<String>(AppSettingKeys.themeMode),
  );
  final reducedMotion =
      await services.settings.get<bool>(AppSettingKeys.reducedMotion) ?? false;
  final launchAtStartup =
      await services.settings.get<bool>(AppSettingKeys.launchAtStartup) ??
      false;

  runApp(
    UamApp(
      engineInfoGateway: RustApi(),
      services: services,
      initialThemePreference: theme,
      initialReducedMotion: reducedMotion,
      initialLaunchAtStartup: launchAtStartup,
    ),
  );
}
