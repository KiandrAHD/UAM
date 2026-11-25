import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/app/shell/uam_destinations.dart';

import '../support/test_harness.dart';

Future<void> _openEngine(WidgetTester tester) async {
  final sidebar = find.byKey(const Key('uam-sidebar'));
  await tester.tap(
    find.descendant(
      of: sidebar,
      matching: find.text(UamDestination.audioEngine.label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('audio engine page exposes live stream controls', (tester) async {
    await pumpUamApp(tester);
    await _openEngine(tester);

    expect(find.byKey(const Key('page-audio-engine')), findsOneWidget);
    expect(find.byKey(const Key('engine-start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('engine-start')));
    await tester.pumpAndSettle();

    // With a running fake stream the engine reports verified processing.
    expect(find.text('Processing'), findsWidgets);
  });

  testWidgets('diagnostics shows Unavailable before a stream runs', (
    tester,
  ) async {
    await pumpUamApp(tester);
    await _openEngine(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Audio diagnostics'), findsWidgets);
    expect(find.text('CALLBACK AVG'), findsOneWidget);
    expect(find.text('No live measurements'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
  });

  testWidgets('diagnostics shows measured values once streaming', (
    tester,
  ) async {
    await pumpUamApp(tester);
    await _openEngine(tester);
    await tester.tap(find.byKey(const Key('engine-start')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Live measurements'), findsOneWidget);
    expect(find.text('FRAMES RENDERED'), findsOneWidget);
    expect(find.textContaining('µs'), findsWidgets);
  });
}
