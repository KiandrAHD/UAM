import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

Future<void> _openHardwareControls(WidgetTester tester) async {
  await pumpUamApp(tester, size: const Size(1400, 1200));
  final sidebar = find.byKey(const Key('uam-sidebar'));
  await tester.tap(
    find.descendant(of: sidebar, matching: find.text('Hardware Controls')),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('hardware controls', () {
    testWidgets('no actionable control renders without a device', (
      tester,
    ) async {
      await _openHardwareControls(tester);

      expect(find.byKey(const Key('page-hardware-controls')), findsOneWidget);
      expect(find.text('No device connected'), findsWidgets);
      expect(find.text('Active noise cancellation'), findsOneWidget);
      expect(find.text('DISCONNECTED'), findsWidgets);

      // The whole page must not expose an interactive toggle when no adapter
      // reports an available feature.
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Available'), findsNothing);

      final permission = find.widgetWithText(
        OutlinedButton,
        'Review permission',
      );
      expect(permission, findsOneWidget);
      expect(tester.widget<OutlinedButton>(permission).onPressed, isNull);
    });

    testWidgets('capability states stay explanatory, not actionable', (
      tester,
    ) async {
      await _openHardwareControls(tester);

      expect(
        find.text('Connect and select a device to evaluate this feature.'),
        findsWidgets,
      );
      expect(find.byType(Switch), findsNothing);
    });
  });
}
