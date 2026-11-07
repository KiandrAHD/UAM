import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/router/app_routes.dart';
import 'package:uam/app/shell/uam_destinations.dart';

import '../support/test_harness.dart';

Key _pageKey(UamDestination destination) {
  return switch (destination) {
    UamDestination.dashboard => const Key('page-dashboard'),
    UamDestination.deviceManager => const Key('page-device-manager'),
    UamDestination.equalizer => const Key('page-equalizer'),
    UamDestination.audioEngine => const Key('page-audio-engine'),
    UamDestination.hardwareControls => const Key('page-hardware-controls'),
    UamDestination.presets => const Key('page-presets'),
    UamDestination.settings => const Key('page-settings'),
  };
}

void main() {
  group('navigation', () {
    testWidgets('sidebar reaches all seven modules', (tester) async {
      await pumpUamApp(tester, size: const Size(1400, 1200));
      expect(find.byKey(const Key('page-dashboard')), findsOneWidget);

      for (final destination in UamDestination.values) {
        if (destination == UamDestination.dashboard) {
          continue;
        }
        final sidebar = find.byKey(const Key('uam-sidebar'));
        await tester.tap(
          find.descendant(of: sidebar, matching: find.text(destination.label)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(_pageKey(destination)),
          findsOneWidget,
          reason: '${destination.label} should render its page',
        );
      }

      expect(
        AppRoutes.all,
        containsAll(<String>[
          AppRoutes.dashboard,
          AppRoutes.deviceManager,
          AppRoutes.equalizer,
          AppRoutes.audioEngine,
          AppRoutes.hardwareControls,
          AppRoutes.presets,
          AppRoutes.settings,
        ]),
      );
    });

    testWidgets('mobile bottom navigation reaches primary and More modules', (
      tester,
    ) async {
      await pumpUamApp(tester, size: const Size(600, 1000));
      final nav = find.byKey(const Key('uam-mobile-nav'));
      expect(nav, findsOneWidget);

      await tester.tap(
        find.descendant(of: nav, matching: find.text('Devices')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-device-manager')), findsOneWidget);

      await tester.tap(find.descendant(of: nav, matching: find.text('EQ')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-equalizer')), findsOneWidget);

      await tester.tap(find.descendant(of: nav, matching: find.text('Home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-dashboard')), findsOneWidget);

      await tester.tap(find.descendant(of: nav, matching: find.text('More')));
      await tester.pumpAndSettle();
      expect(find.text('Secondary destinations'), findsOneWidget);
      expect(find.text('Audio Engine'), findsOneWidget);
      expect(find.text('Hardware Controls'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Audio Engine'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-audio-engine')), findsOneWidget);

      await tester.tap(find.descendant(of: nav, matching: find.text('More')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-settings')), findsOneWidget);
    });
  });
}
