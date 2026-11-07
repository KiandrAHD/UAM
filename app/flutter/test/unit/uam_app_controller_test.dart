import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/state/uam_app_controller.dart';
import 'package:uam/bridge/rust_api.dart';
import 'package:uam/core/result/result.dart';
import 'package:uam/features/audio_engine/application/engine_controller.dart';
import 'package:uam/shared/models/capability.dart';
import 'package:uam/shared/models/engine_runtime_state.dart';

import '../support/test_harness.dart';

UamAppController _controller() => UamAppController.create(
  engine: EngineController(
    const FakeEngineGateway(Result<EngineInfo>.success(testEngineInfo)),
  ),
);

void main() {
  group('UamAppController', () {
    test('theme preferences map to Flutter theme modes', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      expect(controller.themePreference, UamThemePreference.system);
      expect(controller.themeMode, ThemeMode.system);
      controller.setThemePreference(UamThemePreference.dark);
      expect(controller.themeMode, ThemeMode.dark);
      controller.setThemePreference(UamThemePreference.light);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('reduced motion is stored without touching the engine', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      expect(controller.reducedMotion, isFalse);
      controller.setReducedMotion(true);
      expect(controller.reducedMotion, isTrue);
    });

    test('initialising loads the engine gateway', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.engine.state.coreReachable, isTrue);
      expect(controller.engine.state.status, EngineProcessingStatus.ready);
      expect(controller.engine.state.processingVerified, isFalse);
      expect(controller.engine.entries, isNotEmpty);
    });

    test('unavailable hardware controls cannot mutate local state', () {
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

    test('activating a preset maps it onto the graphic equalizer', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      expect(controller.equalizer.configuration.bands, hasLength(10));
      final applied = controller.activatePreset('builtin-balanced-warm');
      expect(applied, isTrue);
      expect(controller.presets.activeId, 'builtin-balanced-warm');
      expect(controller.equalizer.configuration.preampDb, -2);
      expect(
        controller.equalizer.configuration.bands.first.gainDb,
        anyOf(2.0, 0.0),
      );
    });

    test(
      'activating the neutral preset yields a flat graphic configuration',
      () {
        final controller = _controller();
        addTearDown(controller.dispose);
        controller.activatePreset('builtin-balanced-warm');
        controller.activatePreset('builtin-neutral-reference');
        expect(controller.equalizer.configuration.preampDb, 0);
        for (final band in controller.equalizer.configuration.bands) {
          expect(band.gainDb, 0);
        }
      },
    );

    test('unknown preset ids do not mutate configuration', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      final before = controller.equalizer.configuration;
      expect(controller.activatePreset('missing'), isFalse);
      expect(controller.equalizer.configuration.preampDb, before.preampDb);
    });

    test('resetPreferences clears in-memory preferences', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.setThemePreference(UamThemePreference.dark);
      controller.setReducedMotion(true);
      controller.setLaunchAtStartup(true);
      controller.setHardwareValue(
        'anc',
        CapabilityAvailability.available,
        true,
      );
      controller.resetPreferences();
      expect(controller.themePreference, UamThemePreference.system);
      expect(controller.reducedMotion, isFalse);
      expect(controller.launchAtStartup, isFalse);
      expect(controller.hardwareValue('anc'), isFalse);
    });
  });
}
