import 'package:flutter/material.dart';

import '../router/app_routes.dart';

/// One navigable product module.
enum UamDestination {
  dashboard(
    route: AppRoutes.dashboard,
    label: 'Dashboard',
    shortLabel: 'Home',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
    mobilePrimary: true,
  ),
  deviceManager(
    route: AppRoutes.deviceManager,
    label: 'Device Manager',
    shortLabel: 'Devices',
    icon: Icons.headphones_outlined,
    selectedIcon: Icons.headphones,
    mobilePrimary: true,
  ),
  equalizer(
    route: AppRoutes.equalizer,
    label: 'Equalizer',
    shortLabel: 'EQ',
    icon: Icons.graphic_eq_outlined,
    selectedIcon: Icons.graphic_eq,
    mobilePrimary: true,
  ),
  audioEngine(
    route: AppRoutes.audioEngine,
    label: 'Audio Engine',
    shortLabel: 'Engine',
    icon: Icons.memory_outlined,
    selectedIcon: Icons.memory,
  ),
  hardwareControls(
    route: AppRoutes.hardwareControls,
    label: 'Hardware Controls',
    shortLabel: 'Hardware',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
  ),
  presets(
    route: AppRoutes.presets,
    label: 'Presets',
    shortLabel: 'Presets',
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    mobilePrimary: true,
  ),
  settings(
    route: AppRoutes.settings,
    label: 'Settings',
    shortLabel: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  );

  const UamDestination({
    required this.route,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.selectedIcon,
    this.mobilePrimary = false,
  });

  final String route;
  final String label;
  final String shortLabel;
  final IconData icon;
  final IconData selectedIcon;
  final bool mobilePrimary;

  bool get isSecondaryMobile =>
      !mobilePrimary && this != UamDestination.dashboard;

  static UamDestination? tryFromRoute(String route) {
    for (final destination in values) {
      if (destination.route == route) {
        return destination;
      }
    }
    return null;
  }

  static List<UamDestination> get primaryMobile => values
      .where((destination) => destination.mobilePrimary)
      .toList(growable: false);

  static List<UamDestination> get secondaryMobile => values
      .where((destination) => destination.isSecondaryMobile)
      .toList(growable: false);
}
