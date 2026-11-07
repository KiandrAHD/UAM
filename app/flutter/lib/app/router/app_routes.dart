/// Central named routes for every Phase 1 module.
abstract final class AppRoutes {
  static const String dashboard = '/';
  static const String deviceManager = '/devices';
  static const String equalizer = '/equalizer';
  static const String audioEngine = '/audio-engine';
  static const String hardwareControls = '/hardware-controls';
  static const String presets = '/presets';
  static const String settings = '/settings';

  /// Backwards-compatible Phase 0 alias.
  static const String home = dashboard;

  static const List<String> all = <String>[
    dashboard,
    deviceManager,
    equalizer,
    audioEngine,
    hardwareControls,
    presets,
    settings,
  ];

  static String labelFor(String route) => switch (route) {
    dashboard => 'Dashboard',
    deviceManager => 'Device Manager',
    equalizer => 'Equalizer',
    audioEngine => 'Audio Engine',
    hardwareControls => 'Hardware Controls',
    presets => 'Presets',
    settings => 'Settings',
    _ => 'UAM',
  };
}
