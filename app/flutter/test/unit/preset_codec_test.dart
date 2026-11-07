import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uam/shared/models/preset_document.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('PresetCodec', () {
    test('parses every repository reference preset', () {
      const fixtures = <String>[
        '../../presets/examples/balanced-warm.uam-preset.json',
        '../../presets/examples/neutral-reference.uam-preset.json',
        '../../presets/examples/shelf-bass-boost.uam-preset.json',
      ];
      for (final path in fixtures) {
        final result = PresetCodec.parse(_read(path));
        expect(result.isValid, isTrue, reason: '$path: ${result.errors}');
        expect(result.preset, isNotNull);
        expect(result.preset!.metadata.name, isNotEmpty);
      }
    });

    test('labels shelf-bass-boost with its actual bands and capabilities', () {
      final result = PresetCodec.parse(
        _read('../../presets/examples/shelf-bass-boost.uam-preset.json'),
      );
      final preset = result.preset!;
      expect(preset.bandCount, 2);
      expect(preset.audio.bands.first.filterType.name, 'lowShelf');
      expect(
        preset.compatibility.requiredCapabilities,
        contains('dsp.eq.shelving'),
      );
    });

    test('rejects every invalid repository fixture', () {
      final directory = Directory('../../database/fixtures/sample-presets');
      final invalid = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('invalid-'))
          .toList(growable: false);
      expect(invalid, isNotEmpty);
      for (final file in invalid) {
        final result = PresetCodec.parse(file.readAsStringSync());
        expect(
          result.isValid,
          isFalse,
          reason: '${file.path} should be rejected',
        );
        expect(result.errors, isNotEmpty);
      }
    });

    test('round-trips a valid preset through pretty JSON', () {
      final original = PresetCodec.parse(
        _read('../../presets/examples/balanced-warm.uam-preset.json'),
      ).preset!;
      final reparsed = PresetCodec.parse(original.toPrettyJson());
      expect(reparsed.isValid, isTrue);
      expect(reparsed.preset!.bandCount, original.bandCount);
      expect(reparsed.preset!.audio.preampDb, original.audio.preampDb);
    });

    test('rejects unknown fields, bad versions, and oversized input', () {
      final unknownField = PresetCodec.parse('''
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": { "name": "Test" },
  "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
  "audio": { "preampDb": 0, "equalizer": { "bands": [] } },
  "extra": true
}
''');
      expect(unknownField.isValid, isFalse);
      expect(unknownField.errors.join(), contains('extra'));

      final badVersion = PresetCodec.parse('''
{
  "format": "uam-preset",
  "schemaVersion": 2,
  "metadata": { "name": "Test" },
  "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
  "audio": { "preampDb": 0, "equalizer": { "bands": [] } }
}
''');
      expect(badVersion.isValid, isFalse);

      final oversized = PresetCodec.parse(' ' * (PresetDocument.maxBytes + 1));
      expect(oversized.isValid, isFalse);
      expect(oversized.errors.first, contains('256 KiB'));
    });
  });
}
