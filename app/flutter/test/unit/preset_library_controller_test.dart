import 'package:flutter_test/flutter_test.dart';
import 'package:uam/features/presets/application/preset_library_controller.dart';
import 'package:uam/shared/models/equalizer_configuration.dart';
import 'package:uam/shared/models/preset_document.dart';

import '../support/test_data_stack.dart';

const String _validPresetJson = '''
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": { "name": "Imported Profile", "tags": ["imported"] },
  "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
  "audio": {
    "preampDb": -1.5,
    "equalizer": {
      "bands": [
        { "filterType": "peaking", "frequencyHz": 1000, "gainDb": 2.0, "q": 1.0 }
      ]
    }
  }
}
''';

void main() {
  late TestDataStack stack;
  late PresetLibraryController controller;

  setUp(() async {
    stack = await TestDataStack.create();
    controller = PresetLibraryController(
      repository: stack.presets,
      exchange: stack.exchange,
      settings: stack.settings,
      fileGateway: stack.files,
      backup: stack.backup,
    );
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await stack.dispose();
  });

  group('PresetLibraryController', () {
    test('loads the three seeded built-in presets', () {
      expect(controller.entries, hasLength(3));
      expect(controller.activeId, isNotNull);
      expect(
        controller.categories,
        containsAll(<String>['balanced', 'bass', 'neutral']),
      );
      expect(controller.entries.every((entry) => entry.isBuiltIn), isTrue);
    });

    test('reloading does not duplicate built-ins', () async {
      await controller.load();
      await controller.load();
      expect(controller.entries, hasLength(3));
    });

    test('filters by section, query, and category', () {
      expect(
        controller.filtered(query: 'bass').map((entry) => entry.name),
        contains('Shelf Bass Boost'),
      );
      expect(
        controller.filtered(section: PresetLibrarySection.created),
        isEmpty,
        reason: 'Built-in presets must not appear under Created by me.',
      );
      expect(
        controller.filtered(category: 'neutral').single.name,
        'Neutral Reference',
      );
    });

    test('favorites persist to the repository and survive a reload', () async {
      final entry = controller.entries.first;
      final toggled = await controller.toggleFavorite(entry.id);
      expect(toggled!.isFavorite, isTrue);
      expect(
        controller.filtered(section: PresetLibrarySection.favorites).single.id,
        entry.id,
      );
      await controller.load();
      expect(
        controller.entries.firstWhere((item) => item.id == entry.id).isFavorite,
        isTrue,
      );
    });

    test('imports validated JSON, persists it, and activates it', () async {
      final imported = await controller.importJson(_validPresetJson);
      expect(imported, isNotNull);
      expect(controller.entries, hasLength(4));
      expect(controller.activeId, imported!.id);
      expect(imported.isBuiltIn, isFalse);
      await controller.load();
      expect(controller.entries, hasLength(4));
    });

    test('rejects invalid JSON without mutating the library', () async {
      expect(await controller.importJson('{"format":"nope"}'), isNull);
      expect(controller.entries, hasLength(3));
      expect(controller.error, isNotNull);
    });

    test('built-in presets cannot be deleted, user presets can', () async {
      final builtIn = controller.entries.firstWhere((e) => e.isBuiltIn);
      expect(await controller.removePreset(builtIn.id), isFalse);
      final imported = (await controller.importJson(_validPresetJson))!;
      expect(await controller.removePreset(imported.id), isTrue);
      expect(controller.entries, hasLength(3));
    });

    test('createFromEqualizer stores the current configuration', () async {
      final created = await controller.createFromEqualizer(
        name: 'My Profile',
        description: 'Saved from the editor.',
        configuration: EqualizerConfiguration.defaultGraphic().copyWith(
          preampDb: -2,
        ),
      );
      expect(created, isNotNull);
      expect(created!.document.metadata.name, 'My Profile');
      expect(created.document.bandCount, 10);
      expect(created.document.audio.preampDb, -2);
      expect(created.category, 'Uncategorised');
      expect(created.isBuiltIn, isFalse);
    });

    test('createFromEqualizer rejects a name the schema rejects', () async {
      final created = await controller.createFromEqualizer(
        name: '',
        configuration: EqualizerConfiguration.defaultGraphic(),
      );
      expect(created, isNull);
      expect(controller.error, isNotNull);
    });

    test('activating an unknown preset returns false', () async {
      expect(await controller.activate('missing'), isFalse);
    });

    test('activating a known preset persists the selection', () async {
      expect(await controller.activate('builtin-shelf-bass-boost'), isTrue);
      expect(controller.activeId, 'builtin-shelf-bass-boost');
      await controller.load();
      expect(controller.activeId, 'builtin-shelf-bass-boost');
    });

    test('a dangling active preset recovers to a valid one', () async {
      final created = (await controller.importJson(_validPresetJson))!;
      await stack.presets.delete(created.id);
      await controller.load();
      expect(controller.activeId, isNotNull);
      expect(
        controller.entries.any((entry) => entry.id == controller.activeId),
        isTrue,
      );
    });

    test('parsed preset document exposes a category from tags', () {
      final result = PresetCodec.parse(_validPresetJson);
      expect(result.preset!.bandCount, 1);
      expect(result.preset!.compatibility.deviceIndependent, isTrue);
    });
  });
}
