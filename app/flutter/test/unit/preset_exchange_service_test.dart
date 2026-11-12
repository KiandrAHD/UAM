import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uam/core/database/database_exception.dart';
import 'package:uam/features/presets/data/preset_exchange_service.dart';
import 'package:uam/features/presets/data/sqlite_preset_repository.dart';
import 'package:uam/features/presets/domain/preset_entry.dart';
import 'package:uam/features/presets/domain/preset_source.dart';
import 'package:uam/shared/models/equalizer_configuration.dart';
import 'package:uam/shared/models/preset_document.dart';

import '../support/test_data_stack.dart';

const String _validPresetJson = '''
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": { "name": "Exchange Profile", "tags": ["exchange"] },
  "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
  "audio": {
    "preampDb": -1.5,
    "equalizer": {
      "bands": [
        { "filterType": "peaking", "frequencyHz": 1000, "gainDb": 2.0, "q": 1.0 },
        { "filterType": "high_shelf", "frequencyHz": 8000, "gainDb": -2.0, "q": 0.7 }
      ]
    }
  }
}
''';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

PresetDocument _document({
  String name = 'Exchange Profile',
  List<String> tags = const <String>['exchange'],
  double preamp = -1.5,
}) {
  final result = PresetCodec.parse(
    PresetDocument(
      metadata: PresetMetadata(name: name, tags: tags),
      compatibility: const PresetCompatibility(),
      audio: PresetAudio(
        preampDb: preamp,
        bands: const <EqBandConfiguration>[
          EqBandConfiguration(
            filterType: EqFilterType.peaking,
            frequencyHz: 1000,
            gainDb: 2,
            q: 1,
          ),
        ],
      ),
    ).toPrettyJson(),
  );
  expect(result.isValid, isTrue, reason: result.errors.join('; '));
  return result.preset!;
}

void main() {
  late TestDataStack stack;
  late SqlitePresetRepository repo;
  late PresetExchangeService exchange;

  setUp(() async {
    stack = await TestDataStack.create();
    repo = stack.presets as SqlitePresetRepository;
    exchange = stack.exchange;
    await repo.ensureBuiltinsSeeded();
  });

  tearDown(() async {
    await stack.dispose();
  });

  group('export', () {
    test('builds deterministic bytes with a safe file name', () async {
      final entry = (await repo.getAll()).firstWhere((e) => e.isBuiltIn);
      final export = exchange.buildExport(entry);
      expect(export.fileName, endsWith('.uam-preset.json'));
      expect(export.mimeType, 'application/json');

      final text = utf8.decode(export.utf8Bytes);
      final decoded = jsonDecode(text) as Map<String, Object?>;
      expect(decoded['format'], 'uam-preset');
      expect(decoded['schemaVersion'], 1);

      // The exported bytes must parse back into an identical document.
      final parsed = PresetCodec.parse(text);
      expect(parsed.isValid, isTrue);
      expect(parsed.preset!.metadata.name, entry.name);

      // Exporting twice yields byte-identical output.
      expect(exchange.buildExport(entry).utf8Bytes, export.utf8Bytes);
    });

    test('sanitizes characters that are illegal in file names', () {
      final entry = PresetEntry(
        id: 'user-weird',
        document: _document(name: 'a/b:c*?"<>|'),
        source: PresetSource.user,
      );
      final export = exchange.buildExport(entry);
      expect(export.fileName, isNot(contains('/')));
      expect(export.fileName, isNot(contains(':')));
      expect(export.fileName, endsWith('.uam-preset.json'));
    });

    test('export then import round-trips every field', () async {
      final created = await repo.create(
        _document(
          name: 'Round Trip Exchange',
          tags: const <String>['alpha', 'beta'],
          preamp: -3.25,
        ),
        id: 'user-export-src',
      );
      final export = exchange.buildExport(created);
      final result = await exchange.prepareImport(export.utf8Bytes);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
      final candidate = result.candidate!;
      expect(candidate.document.metadata.name, 'Round Trip Exchange');
      expect(candidate.document.metadata.tags, <String>['alpha', 'beta']);
      expect(candidate.document.audio.preampDb, -3.25);
    });
  });

  group('import validation', () {
    test('accepts a valid v1 document', () async {
      final result = await exchange.prepareImport(_bytes(_validPresetJson));
      expect(result.isValid, isTrue);
      expect(result.candidate!.conflict, ImportConflict.none);
      expect(result.candidate!.needsDecision, isFalse);
    });

    test('rejects empty input', () async {
      final result = await exchange.prepareImport(Uint8List(0));
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('empty'));
    });

    test('rejects whitespace-only input', () async {
      final result = await exchange.prepareImport(_bytes('   \n  '));
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('no JSON content'));
    });

    test('rejects invalid UTF-8', () async {
      final result = await exchange.prepareImport(
        Uint8List.fromList(<int>[0xff, 0xfe, 0x00, 0x41]),
      );
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('UTF-8'));
    });

    test('rejects malformed JSON', () async {
      final result = await exchange.prepareImport(_bytes('{ not json'));
      expect(result.isValid, isFalse);
      expect(result.errors.single.toLowerCase(), contains('json'));
    });

    test('rejects a document missing required fields', () async {
      final result = await exchange.prepareImport(
        _bytes('{"format":"uam-preset","schemaVersion":1}'),
      );
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('rejects bad types', () async {
      final result = await exchange.prepareImport(
        _bytes('''
        {
          "format": "uam-preset",
          "schemaVersion": 1,
          "metadata": { "name": 42 },
          "compatibility": { "minimumUamVersion": "0.1.0", "deviceIndependent": true },
          "audio": { "preampDb": 0, "equalizer": { "bands": [] } }
        }
        '''),
      );
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('rejects an unsupported schema version', () async {
      final document = jsonDecode(_validPresetJson) as Map<String, Object?>;
      document['schemaVersion'] = 2;
      final result = await exchange.prepareImport(_bytes(jsonEncode(document)));
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('schemaVersion'));
    });

    test('rejects invalid filter parameters', () async {
      final document = jsonDecode(_validPresetJson) as Map<String, Object?>;
      (document['audio']! as Map<String, Object?>)['preampDb'] = 999;
      final result = await exchange.prepareImport(_bytes(jsonEncode(document)));
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('preampDb'));
    });

    test('rejects an oversized document before parsing', () async {
      final service = PresetExchangeService(
        repository: repo,
        maxImportBytes: 16,
      );
      final result = await service.prepareImport(_bytes(_validPresetJson));
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('import limit'));
    });

    test('preparing an import writes nothing', () async {
      final before = (await repo.getAll()).length;
      await exchange.prepareImport(_bytes(_validPresetJson));
      expect(await repo.getAll(), hasLength(before));
    });
  });

  group('duplicate resolution', () {
    test('detects an identical document under a different id', () async {
      final created = await repo.create(
        _document(name: 'Duplicate Name'),
        id: 'user-dup-src',
      );
      final export = exchange.buildExport(created);
      final result = await exchange.prepareImport(export.utf8Bytes);
      final candidate = result.candidate!;
      expect(candidate.conflict, ImportConflict.identicalContent);
      expect(candidate.existingId, 'user-dup-src');
      expect(candidate.needsDecision, isTrue);
    });

    test(
      'identical content matching a built-in is a built-in collision',
      () async {
        final builtIn = (await repo.getAll()).firstWhere((e) => e.isBuiltIn);
        final export = exchange.buildExport(builtIn);
        final result = await exchange.prepareImport(export.utf8Bytes);
        expect(result.candidate!.conflict, ImportConflict.builtInCollision);
      },
    );

    test(
      'a same-name different-content document is a name collision',
      () async {
        await repo.create(_document(name: 'Shared Name'), id: 'user-shared');
        final other = _document(name: 'Shared Name', preamp: -6.0);
        final result = await exchange.prepareImport(
          _bytes(other.toPrettyJson()),
        );
        expect(result.candidate!.conflict, ImportConflict.nameInUse);
        expect(result.candidate!.existingId, 'user-shared');
      },
    );
  });

  group('commitImport', () {
    test('keepExisting writes nothing and returns null', () async {
      final created = await repo.create(
        _document(name: 'Keep Me'),
        id: 'user-keep',
      );
      final before = (await repo.getAll()).length;
      final prepared = await exchange.prepareImport(
        exchange.buildExport(created).utf8Bytes,
      );
      final committed = await exchange.commitImport(
        prepared.candidate!,
        DuplicateResolution.keepExisting,
      );
      expect(committed, isNull);
      expect(await repo.getAll(), hasLength(before));
    });

    test('replaceExisting overwrites the matched user preset', () async {
      final created = await repo.create(
        _document(name: 'Replace Me'),
        id: 'user-replace',
      );
      final prepared = await exchange.prepareImport(
        exchange.buildExport(created).utf8Bytes,
      );
      final replacement = prepared.candidate!;
      final overwritten = await exchange.commitImport(
        replacement,
        DuplicateResolution.replaceExisting,
      );
      expect(overwritten!.id, 'user-replace');
      expect(await repo.getAll(), hasLength(4));
    });

    test('replaceExisting refuses a built-in collision', () async {
      final builtIn = (await repo.getAll()).firstWhere((e) => e.isBuiltIn);
      final prepared = await exchange.prepareImport(
        exchange.buildExport(builtIn).utf8Bytes,
      );
      await expectLater(
        exchange.commitImport(
          prepared.candidate!,
          DuplicateResolution.replaceExisting,
        ),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.constraintViolation,
          ),
        ),
      );
    });

    test('replaceExisting without an existing id throws', () async {
      final prepared = await exchange.prepareImport(_bytes(_validPresetJson));
      await expectLater(
        exchange.commitImport(
          prepared.candidate!,
          DuplicateResolution.replaceExisting,
        ),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.constraintViolation,
          ),
        ),
      );
    });

    test('importAsNew stores the document with an imported source', () async {
      final prepared = await exchange.prepareImport(_bytes(_validPresetJson));
      final imported = await exchange.commitImport(
        prepared.candidate!,
        DuplicateResolution.importAsNew,
      );
      expect(imported, isNotNull);
      expect(imported!.source, PresetSource.imported);
      expect(imported.id, startsWith('imported-'));
      expect(imported.isBuiltIn, isFalse);
      expect(await repo.getById(imported.id), isNotNull);
    });

    test('a cancelled import leaves the library untouched', () async {
      final before = await repo.getAll();
      final prepared = await exchange.prepareImport(_bytes(_validPresetJson));
      // Simulate the user dismissing the dialog: no commit is called.
      expect(prepared.isValid, isTrue);
      expect(await repo.getAll(), hasLength(before.length));
    });
  });

  group('compatibility warnings', () {
    test(
      'warns about shelving bands the graphic editor cannot show directly',
      () async {
        final result = await exchange.prepareImport(_bytes(_validPresetJson));
        expect(
          result.candidate!.compatibilityWarnings.any(
            (warning) => warning.contains('shelving'),
          ),
          isTrue,
        );
      },
    );

    test('warns about required capabilities', () async {
      final document = jsonDecode(_validPresetJson) as Map<String, Object?>;
      (document['compatibility']!
          as Map<String, Object?>)['requiredCapabilities'] = <String>[
        'dsp.eq.peaking',
      ];
      final result = await exchange.prepareImport(_bytes(jsonEncode(document)));
      expect(
        result.candidate!.compatibilityWarnings.any(
          (warning) => warning.contains('dsp.eq.peaking'),
        ),
        isTrue,
      );
    });

    test('a plain peaking document produces no warnings', () async {
      final result = await exchange.prepareImport(
        _bytes(_document().toPrettyJson()),
      );
      expect(result.candidate!.compatibilityWarnings, isEmpty);
    });
  });
}
