import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

Future<void> _openSettings(WidgetTester tester) async {
  await pumpUamApp(tester, size: const Size(1400, 1200));
  final sidebar = find.byKey(const Key('uam-sidebar'));
  await tester.tap(
    find.descendant(of: sidebar, matching: find.text('Settings')),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('settings', () {
    testWidgets('appearance changes theme and reduced motion preference', (
      tester,
    ) async {
      await _openSettings(tester);
      expect(find.byKey(const Key('page-settings')), findsOneWidget);
      expect(find.text('Launch at startup'), findsOneWidget);

      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('THEME'), findsOneWidget);
      expect(find.text('Reduced motion'), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
    });

    testWidgets('undesigned categories show an explicit placeholder', (
      tester,
    ) async {
      await _openSettings(tester);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      expect(find.text('Audio is not designed yet'), findsOneWidget);
      expect(find.textContaining('instead of inventing'), findsOneWidget);
    });
  });
}
