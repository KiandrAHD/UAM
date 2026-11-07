import 'package:flutter/material.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/audio_engine/presentation/audio_engine_page.dart';
import '../../features/device_manager/presentation/device_manager_page.dart';
import '../../features/equalizer/presentation/equalizer_page.dart';
import '../../features/hardware_controls/presentation/hardware_controls_page.dart';
import '../../features/presets/presentation/presets_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../shell/uam_shell.dart';
import 'app_routes.dart';

/// Route builder that keeps the application shell mounted around every module.
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final route = AppRoutes.all.contains(settings.name)
        ? settings.name!
        : AppRoutes.dashboard;
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: route),
      builder: (_) => UamShell(route: route),
    );
  }

  static Widget pageFor(String route) => switch (route) {
    AppRoutes.dashboard => const DashboardPage(),
    AppRoutes.deviceManager => const DeviceManagerPage(),
    AppRoutes.equalizer => const EqualizerPage(),
    AppRoutes.audioEngine => const AudioEnginePage(),
    AppRoutes.hardwareControls => const HardwareControlsPage(),
    AppRoutes.presets => const PresetsPage(),
    AppRoutes.settings => const SettingsPage(),
    _ => const DashboardPage(),
  };

  static const List<String> primaryMobileRoutes = <String>[
    AppRoutes.dashboard,
    AppRoutes.deviceManager,
    AppRoutes.equalizer,
    AppRoutes.presets,
  ];
}
