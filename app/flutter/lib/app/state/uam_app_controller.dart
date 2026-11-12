import 'dart:async';

import 'package:flutter/material.dart' hide DiagnosticLevel;

import '../../core/database/app_setting_keys.dart';
import '../../features/audio_engine/application/engine_controller.dart';
import '../../features/audio_engine/domain/diagnostic_entry.dart';
import '../../features/device_manager/application/device_controller.dart';
import '../../features/equalizer/application/equalizer_controller.dart';
import '../../features/presets/application/preset_library_controller.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../shared/models/capability.dart';
import '../../shared/models/equalizer_configuration.dart';
import '../services/uam_services.dart';

/// Appearance preference persisted in the `app_settings` table.
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

  static UamThemePreference fromWire(String? value) {
    for (final preference in values) {
      if (preference.name == value) {
        return preference;
      }
    }
    return UamThemePreference.system;
  }
}

/// Root application state.
///
/// Flutter's built-in [ChangeNotifier] remains the single state-management
/// approach. The controller is now backed by persisted settings and presets:
/// appearance, general preferences, the active preset, and the library all
/// survive a full application restart.
final class UamAppController extends ChangeNotifier {
  UamAppController({
    required this.engine,
    required this.devices,
    required this.equalizer,
    required this.presets,
    required SettingsRepository settings,
    UamThemePreference? initialThemePreference,
    bool? initialReducedMotion,
    bool? initialLaunchAtStartup,
  }) : _settingsRepository = settings,
       _themePreference = initialThemePreference ?? UamThemePreference.system,
       _reducedMotion = initialReducedMotion ?? false,
       _launchAtStartup = initialLaunchAtStartup ?? false {
    engine.addListener(_relay);
    devices.addListener(_relay);
    equalizer.addListener(_relay);
    presets.addListener(_relay);
  }

  /// Build a controller from the application service container.
  factory UamAppController.fromServices({
    required EngineController engine,
    required UamServices services,
    UamThemePreference? initialThemePreference,
    bool? initialReducedMotion,
    bool? initialLaunchAtStartup,
  }) {
    return UamAppController(
      engine: engine,
      devices: DeviceController(),
      equalizer: EqualizerController(),
      presets: PresetLibraryController(
        repository: services.presets,
        exchange: services.exchange,
        settings: services.settings,
        fileGateway: services.fileGateway,
        backup: services.backup,
      ),
      settings: services.settings,
      initialThemePreference: initialThemePreference,
      initialReducedMotion: initialReducedMotion,
      initialLaunchAtStartup: initialLaunchAtStartup,
    );
  }

  final EngineController engine;
  final DeviceController devices;
  final EqualizerController equalizer;
  final PresetLibraryController presets;
  final SettingsRepository _settingsRepository;

  UamThemePreference _themePreference;
  bool _reducedMotion;
  bool _launchAtStartup;
  bool _initialized = false;
  final Map<String, bool> _hardwareValues = <String, bool>{};

  UamThemePreference get themePreference => _themePreference;
  ThemeMode get themeMode => _themePreference.themeMode;
  bool get reducedMotion => _reducedMotion;
  bool get launchAtStartup => _launchAtStartup;
  bool get isInitialized => _initialized;

  bool hardwareValue(String featureId) => _hardwareValues[featureId] ?? false;

  /// Load persisted settings and presets, then initialize the engine.
  ///
  /// Order: settings -> presets -> active preset -> appearance -> controllers.
  Future<void> initialize() async {
    await _loadSettings();
    await presets.load();
    await refreshActivePresetConfiguration();
    await engine.load();
    _initialized = true;
    notifyListeners();
  }

  /// Load the persisted appearance and general preferences.
  Future<void> loadSettingsOnly() => _loadSettings();

  Future<void> _loadSettings() async {
    try {
      final theme = await _settingsRepository.get<String>(
        AppSettingKeys.themeMode,
      );
      final reducedMotion = await _settingsRepository.get<bool>(
        AppSettingKeys.reducedMotion,
      );
      final launchAtStartup = await _settingsRepository.get<bool>(
        AppSettingKeys.launchAtStartup,
      );
      _themePreference = UamThemePreference.fromWire(theme);
      _reducedMotion = reducedMotion ?? false;
      _launchAtStartup = launchAtStartup ?? false;
    } catch (_) {
      // A settings failure must never block startup; defaults are kept.
      _themePreference = UamThemePreference.system;
      _reducedMotion = false;
      _launchAtStartup = false;
    }
    notifyListeners();
  }

  /// Apply the persisted active preset to the desired EQ configuration.
  Future<void> refreshActivePresetConfiguration() async {
    final entry = presets.active;
    if (entry == null) {
      return;
    }
    equalizer.applyConfiguration(
      EqualizerConfiguration.fromGraphicPreset(
        preampDb: entry.document.audio.preampDb,
        presetBands: entry.document.audio.bands,
      ),
    );
  }

  void setThemePreference(UamThemePreference preference) {
    if (_themePreference == preference) {
      return;
    }
    _themePreference = preference;
    notifyListeners();
    unawaited(_persist(AppSettingKeys.themeMode, preference.name));
  }

  void setReducedMotion(bool value) {
    if (_reducedMotion == value) {
      return;
    }
    _reducedMotion = value;
    notifyListeners();
    unawaited(_persist(AppSettingKeys.reducedMotion, value));
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
    unawaited(_persist(AppSettingKeys.launchAtStartup, value));
  }

  /// Update an available hardware control.
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

  /// Activate one preset, persist it, and map it onto the ten-band editor.
  Future<bool> activatePreset(String id) async {
    final activated = await presets.activate(id);
    if (!activated) {
      return false;
    }
    final entry = presets.active;
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

  /// Reset persisted preferences and the equalizer to defaults.
  Future<void> resetPreferences() async {
    await _settingsRepository.resetToDefaults();
    _themePreference = UamThemePreference.system;
    _reducedMotion = false;
    _launchAtStartup = false;
    _hardwareValues.clear();
    engine.addEvent(
      DiagnosticLevel.notice,
      'Preferences were reset to defaults. Presets were not removed.',
    );
    notifyListeners();
  }

  Future<void> _persist(String key, Object? value) async {
    try {
      await _settingsRepository.set(key, value);
    } catch (error) {
      if (_disposed) {
        return;
      }
      engine.addEvent(
        DiagnosticLevel.error,
        'A preference could not be saved and will not survive restart.',
      );
    }
  }

  bool _disposed = false;

  void _relay() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
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
