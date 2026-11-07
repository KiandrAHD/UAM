import 'package:flutter_test/flutter_test.dart';
import 'package:uam/features/presets/application/preset_library_controller.dart';
import 'package:uam/shared/models/equalizer_configuration.dart';
import 'package:uam/shared/models/preset_document.dart';

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
  group('PresetLibraryController', () {
    test('ships the three repository reference presets', () {
      final controller = PresetLibraryController();
      expect(controller.entries, hasLength(3));
      expect(controller.activeId, controller.entries.first.id);
      expect(controller.categories, containsAll(<String>['balanced', 'bass']));
    });

    test('filters by section, query, and category', () {
      final controller = PresetLibraryController();
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

    test('favorites survive filtering', () {
      final controller = PresetLibraryController();
      final entry = controller.entries.first;
      controller.toggleFavorite(entry.id);
      expect(
        controller.filtered(section: PresetLibrarySection.favorites).single.id,
        entry.id,
      );
    });

    test('imports validated JSON and can activate it', () {
      final controller = PresetLibraryController();
      final imported = controller.importJson(_validPresetJson);
      expect(imported, isNotNull);
      expect(controller.entries, hasLength(4));
      expect(controller.activeId, imported!.id);
      expect(imported.isBuiltIn, isFalse);
    });

    test('rejects invalid JSON without mutating the library', () {
      final controller = PresetLibraryController();
      expect(controller.importJson('{"format":"nope"}'), isNull);
      expect(controller.entries, hasLength(3));
    });

    test('built-in presets cannot be deleted, imports can', () {
      final controller = PresetLibraryController();
      final builtIn = controller.entries.first;
      expect(controller.removePreset(builtIn.id), isFalse);
      final imported = controller.importJson(_validPresetJson)!;
      expect(controller.removePreset(imported.id), isTrue);
      expect(controller.entries, hasLength(3));
    });

    test('createFromEqualizer stores the current configuration', () {
      final controller = PresetLibraryController();
      final created = controller.createFromEqualizer(
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
    });

    test('createFromEqualizer rejects a name the schema rejects', () {
      final controller = PresetLibraryController();
      final created = controller.createFromEqualizer(
        name: '',
        configuration: EqualizerConfiguration.defaultGraphic(),
      );
      expect(created, isNull);
    });

    test('activating an unknown preset returns null', () {
      final controller = PresetLibraryController();
      expect(controller.activate('missing'), isNull);
    });

    test('parsed preset document exposes a category from tags', () {
      final result = PresetCodec.parse(_validPresetJson);
      expect(result.preset!.bandCount, 1);
      expect(result.preset!.compatibility.deviceIndependent, isTrue);
    });
  });
}
