import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/state/uam_app_controller.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/database/app_setting_keys.dart';
import 'package:uam/core/result/result.dart';
import 'package:uam/features/audio_engine/application/engine_controller.dart';
import 'package:uam/features/device_manager/application/device_controller.dart';
import 'package:uam/features/equalizer/application/equalizer_controller.dart';
import 'package:uam/features/presets/application/preset_library_controller.dart';
import 'package:uam/shared/models/capability.dart';
import 'package:uam/shared/models/engine_runtime_state.dart';

import '../support/test_data_stack.dart';
import '../support/test_harness.dart';

late TestDataStack _stack;

UamAppController _controller() => UamAppController(
  engine: EngineController(
    const FakeEngineGateway(Result<EngineInfo>.success(testEngineInfo)),
  ),
  devices: DeviceController(),
  equalizer: EqualizerController(),
  presets: PresetLibraryController(
    repository: _stack.presets,
    exchange: _stack.exchange,
    settings: _stack.settings,
    fileGateway: _stack.files,
    backup: _stack.backup,
  ),
  settings: _stack.settings,
);

void main() {
  setUp(() async {
    _stack = await TestDataStack.create();
  });

  tearDown(() async {
    await _stack.dispose();
  });

  group('UamAppController', () {
    test('theme preferences map to Flutter theme modes', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.themePreference, UamThemePreference.system);
      expect(controller.themeMode, ThemeMode.system);
      controller.setThemePreference(UamThemePreference.dark);
      expect(controller.themeMode, ThemeMode.dark);
      controller.setThemePreference(UamThemePreference.light);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('theme and reduced motion are persisted for the next start', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setThemePreference(UamThemePreference.dark);
      controller.setReducedMotion(true);
      // Allow the fire-and-forget writes to reach SQLite.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await _stack.settings.get<String>(AppSettingKeys.themeMode),
        'dark',
      );
      expect(
        await _stack.settings.get<bool>(AppSettingKeys.reducedMotion),
        true,
      );

      // A brand new controller over the same database restores the values.
      final reloaded = _controller();
      addTearDown(reloaded.dispose);
      await reloaded.loadSettingsOnly();
      expect(reloaded.themePreference, UamThemePreference.dark);
      expect(reloaded.reducedMotion, isTrue);
    });

    test('initialising loads the engine gateway', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.engine.state.coreReachable, isTrue);
      expect(controller.engine.state.status, EngineProcessingStatus.ready);
      expect(controller.engine.state.processingVerified, isFalse);
      expect(controller.engine.entries, isNotEmpty);
      expect(controller.isInitialized, isTrue);
    });

    test('unavailable hardware controls cannot mutate local state', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.setHardwareValue(
        'anc',
        CapabilityAvailability.unsupported,
        true,
      );
      expect(controller.hardwareValue('anc'), isFalse);
      controller.setHardwareValue(
        'anc',
        CapabilityAvailability.available,
        true,
      );
      expect(controller.hardwareValue('anc'), isTrue);
    });

    test('activating a preset maps it onto the graphic equalizer', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.equalizer.configuration.bands, hasLength(10));
      final applied = await controller.activatePreset('builtin-balanced-warm');
      expect(applied, isTrue);
      expect(controller.presets.activeId, 'builtin-balanced-warm');
      expect(controller.equalizer.configuration.preampDb, -2);
      expect(
        controller.equalizer.configuration.bands.first.gainDb,
        anyOf(2.0, 0.0),
      );
    });

    test('activating the neutral preset yields a flat configuration', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.activatePreset('builtin-balanced-warm');
      await controller.activatePreset('builtin-neutral-reference');
      expect(controller.equalizer.configuration.preampDb, 0);
      for (final band in controller.equalizer.configuration.bands) {
        expect(band.gainDb, 0);
      }
    });

    test('unknown preset ids do not mutate configuration', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.equalizer.configuration;
      expect(await controller.activatePreset('missing'), isFalse);
      expect(controller.equalizer.configuration.preampDb, before.preampDb);
    });

    test('initialize restores the persisted active preset', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.activatePreset('builtin-shelf-bass-boost');

      final reloaded = _controller();
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.presets.activeId, 'builtin-shelf-bass-boost');
      expect(reloaded.equalizer.configuration.preampDb, -4.5);
    });

    test('resetPreferences clears persisted preferences', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setThemePreference(UamThemePreference.dark);
      controller.setReducedMotion(true);
      controller.setLaunchAtStartup(true);
      controller.setHardwareValue(
        'anc',
        CapabilityAvailability.available,
        true,
      );
      await controller.resetPreferences();
      expect(controller.themePreference, UamThemePreference.system);
      expect(controller.reducedMotion, isFalse);
      expect(controller.launchAtStartup, isFalse);
      expect(controller.hardwareValue('anc'), isFalse);
      expect(
        await _stack.settings.get<String>(AppSettingKeys.themeMode),
        isNull,
      );
    });
  });
}
