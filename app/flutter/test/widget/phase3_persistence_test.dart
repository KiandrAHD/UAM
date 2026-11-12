import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uam/platform/files/preset_file_gateway.dart';

import '../support/fake_preset_file_gateway.dart';
import '../support/test_harness.dart';

const String _importJson = '''
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": {"name": "Widget Exchange", "tags": ["widget"]},
  "compatibility": {"minimumUamVersion": "0.1.0", "deviceIndependent": true},
  "audio": {"preampDb": -1, "equalizer": {"bands": [
    {"filterType": "peaking", "frequencyHz": 1000, "gainDb": 2, "q": 1}
  ]}}
}
''';

Future<void> _openPage(WidgetTester tester, String label) async {
  await pumpUamApp(tester);
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('uam-sidebar')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pasteAndValidate(WidgetTester tester, String json) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Import preset'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('preset-import-field')), json);
  await tester.tap(find.widgetWithText(OutlinedButton, 'Validate'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a valid paste validates and commits a preset', (tester) async {
    await _openPage(tester, 'Presets');
    await _pasteAndValidate(tester, _importJson);
    expect(find.text('Valid preset'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Widget Exchange'), findsOneWidget);
    expect(
      find.textContaining('imported to the local library'),
      findsOneWidget,
    );
  });

  testWidgets('a duplicate import offers resolution and can keep existing', (
    tester,
  ) async {
    await _openPage(tester, 'Presets');

    // First import: no conflict.
    await _pasteAndValidate(tester, _importJson);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    // Let the first snackbar auto-dismiss so the next one is not queued.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Second import of the identical document: a conflict is detected and the
    // resolution selector is shown before anything is written.
    await _pasteAndValidate(tester, _importJson);
    expect(
      find.text('This document conflicts with an existing preset'),
      findsOneWidget,
    );
    expect(find.text('Keep the existing preset'), findsOneWidget);
    expect(
      find.text('Import as a new preset with a new identifier'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep the existing preset'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('The existing preset was kept.'), findsOneWidget);
  });

  testWidgets('exporting through a cancelled save shows no false success', (
    tester,
  ) async {
    await _openPage(tester, 'Presets');
    final exportIcons = find.byIcon(Icons.save_alt_outlined);
    expect(exportIcons, findsWidgets);
    await tester.tap(exportIcons.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('exported as'), findsNothing);
  });

  testWidgets('settings toggles reduced motion and switches theme', (
    tester,
  ) async {
    await _openPage(tester, 'Settings');
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('settings shows the backup section with no false last backup', (
    tester,
  ) async {
    await _openPage(tester, 'Settings');
    await tester.tap(find.text('Preset Management'));
    await tester.pumpAndSettle();
    expect(find.text('Backup and restore'), findsOneWidget);
    expect(find.byKey(const Key('settings-create-backup')), findsOneWidget);
    expect(find.byKey(const Key('settings-restore-backup')), findsOneWidget);
    expect(
      find.text('No backup has been created from this installation yet.'),
      findsOneWidget,
    );
  });

  testWidgets('creating a backup writes through the gateway and reports it', (
    tester,
  ) async {
    final files = FakePresetFileGateway();
    await pumpUamApp(tester, fileGateway: files);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('uam-sidebar')),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preset Management'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-create-backup')));
    await tester.pumpAndSettle();

    expect(files.lastSavedBackupName, isNotNull);
    expect(files.lastSavedBackupName, endsWith('.uam-backup'));
    expect(files.lastSavedBackupBytes, isNotNull);
    expect(find.textContaining('Backup written: 3 presets'), findsOneWidget);
  });

  testWidgets('restoring a backup requires confirmation and reports success', (
    tester,
  ) async {
    final files = FakePresetFileGateway();
    final services = await createWidgetTestServices(tester, fileGateway: files);
    final built = await tester.runAsync(() async {
      await services.presets.ensureBuiltinsSeeded();
      return services.backup.buildBytes();
    });
    files.backupFile = PickedFile(
      name: 'snapshot.uam-backup',
      bytes: built!.bytes,
    );

    await pumpUamApp(tester, services: services, fileGateway: files);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('uam-sidebar')),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preset Management'));
    await tester.pumpAndSettle();

    // Cancelling the confirmation dialog performs no restore.
    await tester.tap(find.byKey(const Key('settings-restore-backup')));
    await tester.pumpAndSettle();
    expect(find.text('Restore from backup'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restored'), findsNothing);

    // Confirming performs the restore and reports the real counts.
    await tester.tap(find.byKey(const Key('settings-restore-backup')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pump();
    // The restore writes a real pre-restore snapshot file. Alternate a real
    // event-loop slice (runAsync) with frames so the file I/O can complete
    // without pumpAndSettle waiting on the busy progress animation forever.
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (find.textContaining('Restored 3 presets').evaluate().isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Restored 3 presets'), findsOneWidget);
  });

  testWidgets('a corrupt backup file is rejected without a change', (
    tester,
  ) async {
    final files = FakePresetFileGateway();
    files.backupFile = PickedFile(
      name: 'broken.uam-backup',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
    );
    await pumpUamApp(tester, fileGateway: files);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('uam-sidebar')),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preset Management'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-restore-backup')));
    await tester.pumpAndSettle();
    expect(find.text('Restore from backup'), findsNothing);
    expect(find.textContaining('not valid JSON'), findsOneWidget);
  });
}
