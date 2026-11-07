import 'package:flutter/material.dart' hide DiagnosticLevel;

import '../../features/audio_engine/application/engine_controller.dart';
import '../../features/audio_engine/domain/diagnostic_entry.dart';
import '../../features/device_manager/application/device_controller.dart';
import '../../features/equalizer/application/equalizer_controller.dart';
import '../../features/presets/application/preset_library_controller.dart';
import '../../shared/models/capability.dart';
import '../../shared/models/equalizer_configuration.dart';

/// Appearance preference persisted only in memory during Phase 1.
enum UamThemePreference {
  system('System'),
  dark('Dark'),
  light('Light');

  const UamThemePreference(this.label);

  final String label;

  ThemeMode get themeMode => switch (this) {
    UamThemePreference.system => ThemeMode.system,
    UamThemePreference.dark => ThemeMode.dark,
    UamThemePreference.light => ThemeMode.light,
  };
}

/// Root application state.
///
/// Flutter's built-in [ChangeNotifier] is the single state-management approach
/// selected for Phase 1. It adds no dependency, keeps the state observable in
/// widget tests, and can be replaced only with a documented ADR if application
/// complexity later requires it.
final class UamAppController extends ChangeNotifier {
  UamAppController({
    required this.engine,
    required this.devices,
    required this.equalizer,
    required this.presets,
  }) {
    engine.addListener(_relay);
    devices.addListener(_relay);
    equalizer.addListener(_relay);
    presets.addListener(_relay);
  }

  factory UamAppController.create({required EngineController engine}) {
    return UamAppController(
      engine: engine,
      devices: DeviceController(),
      equalizer: EqualizerController(),
      presets: PresetLibraryController(),
    );
  }

  final EngineController engine;
  final DeviceController devices;
  final EqualizerController equalizer;
  final PresetLibraryController presets;

  UamThemePreference _themePreference = UamThemePreference.system;
  bool _reducedMotion = false;
  bool _launchAtStartup = false;
  final Map<String, bool> _hardwareValues = <String, bool>{};

  UamThemePreference get themePreference => _themePreference;
  ThemeMode get themeMode => _themePreference.themeMode;
  bool get reducedMotion => _reducedMotion;
  bool get launchAtStartup => _launchAtStartup;

  bool hardwareValue(String featureId) => _hardwareValues[featureId] ?? false;

  Future<void> initialize() => engine.load();

  void setThemePreference(UamThemePreference preference) {
    if (_themePreference == preference) {
      return;
    }
    _themePreference = preference;
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    if (_reducedMotion == value) {
      return;
    }
    _reducedMotion = value;
    notifyListeners();
  }

  void setLaunchAtStartup(bool value) {
    if (_launchAtStartup == value) {
      return;
    }
    _launchAtStartup = value;
    engine.addEvent(
      DiagnosticLevel.notice,
      'Launch-at-startup is a local preference only; no platform integration is active.',
    );
    notifyListeners();
  }

  /// Update an available hardware control.
  ///
  /// Caller must pass the adapter-derived availability so unsupported controls
  /// cannot mutate local state through this method.
  void setHardwareValue(
    String featureId,
    CapabilityAvailability availability,
    bool value,
  ) {
    if (!availability.isActionable) {
      return;
    }
    _hardwareValues[featureId] = value;
    engine.addEvent(
      DiagnosticLevel.notice,
      '$featureId changed in UI configuration; no hardware adapter command was sent.',
    );
    notifyListeners();
  }

  /// Activate one preset and map it onto the ten-band editor.
  bool activatePreset(String id) {
    final entry = presets.activate(id);
    if (entry == null) {
      return false;
    }
    equalizer.applyConfiguration(
      EqualizerConfiguration.fromGraphicPreset(
        preampDb: entry.document.audio.preampDb,
        presetBands: entry.document.audio.bands,
      ),
    );
    engine.addEvent(
      DiagnosticLevel.info,
      'Preset "${entry.name}" applied to desired EQ configuration.',
    );
    notifyListeners();
    return true;
  }

  void resetPreferences() {
    _themePreference = UamThemePreference.system;
    _reducedMotion = false;
    _launchAtStartup = false;
    _hardwareValues.clear();
    engine.addEvent(
      DiagnosticLevel.notice,
      'In-memory Phase 1 preferences were reset. No persisted data was removed.',
    );
    notifyListeners();
  }

  void _relay() => notifyListeners();

  @override
  void dispose() {
    engine
      ..removeListener(_relay)
      ..dispose();
    devices
      ..removeListener(_relay)
      ..dispose();
    equalizer
      ..removeListener(_relay)
      ..dispose();
    presets
      ..removeListener(_relay)
      ..dispose();
    super.dispose();
  }
}

/// Inherited access to the one app-wide controller.
class UamAppScope extends InheritedNotifier<UamAppController> {
  const UamAppScope({
    required UamAppController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static UamAppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UamAppScope>();
    assert(scope != null, 'UamAppScope is missing above this widget.');
    return scope!.notifier!;
  }

  static UamAppController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<UamAppScope>();
    final scope = element?.widget as UamAppScope?;
    assert(scope != null, 'UamAppScope is missing above this widget.');
    return scope!.notifier!;
  }
}
