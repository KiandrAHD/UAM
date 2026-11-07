import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

const String _validPreset = '''
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": {
    "name": "Imported Warm",
    "author": "Widget Test",
    "tags": ["balanced"]
  },
  "compatibility": {
    "minimumUamVersion": "0.1.0",
    "deviceIndependent": true
  },
  "audio": {
    "preampDb": -1.5,
    "equalizer": {
      "bands": [
        {"filterType": "peaking", "frequencyHz": 120, "gainDb": 2.5, "q": 1.0},
        {"filterType": "peaking", "frequencyHz": 4000, "gainDb": -1.0, "q": 1.0}
      ]
    }
  }
}
''';

Future<void> _openPresets(WidgetTester tester) async {
  await pumpUamApp(tester, size: const Size(1400, 1200));
  final sidebar = find.byKey(const Key('uam-sidebar'));
  await tester.tap(
    find.descendant(of: sidebar, matching: find.text('Presets')),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('preset import', () {
    testWidgets('invalid JSON is rejected and cannot be imported', (
      tester,
    ) async {
      await _openPresets(tester);
      expect(find.byKey(const Key('page-presets')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Import preset'));
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('preset-import-field'));
      expect(field, findsOneWidget);

      await tester.enterText(field, '{ not valid json');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Validate'));
      await tester.pumpAndSettle();

      expect(find.text('Validation failed'), findsOneWidget);
      final importButton = find.widgetWithText(FilledButton, 'Import');
      expect(tester.widget<FilledButton>(importButton).onPressed, isNull);
    });

    testWidgets('valid JSON validates, enables import, and adds to library', (
      tester,
    ) async {
      await _openPresets(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Import preset'));
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('preset-import-field'));
      await tester.enterText(field, _validPreset);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Validate'));
      await tester.pumpAndSettle();

      expect(find.text('Valid preset'), findsOneWidget);
      final importButton = find.widgetWithText(FilledButton, 'Import');
      expect(tester.widget<FilledButton>(importButton).onPressed, isNotNull);

      await tester.tap(importButton);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('imported to the local library'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('page-presets')), findsOneWidget);
      expect(find.text('Imported Warm'), findsOneWidget);
    });
  });
}
