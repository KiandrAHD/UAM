import 'package:flutter_test/flutter_test.dart';
import 'package:uam/core/database/app_setting_keys.dart';
import 'package:uam/core/database/database_exception.dart';
import 'package:uam/features/presets/data/sqlite_preset_repository.dart';
import 'package:uam/features/presets/domain/preset_entry.dart';
import 'package:uam/features/presets/domain/preset_source.dart';
import 'package:uam/shared/models/equalizer_configuration.dart';
import 'package:uam/shared/models/preset_document.dart';

import '../support/test_data_stack.dart';

PresetDocument _document({
  String name = 'Round Trip',
  double preamp = -1.0,
  List<EqBandConfiguration>? bands,
}) {
  final result = PresetCodec.parse(
    PresetDocument(
      metadata: PresetMetadata(
        name: name,
        description: 'A round-trip preset.',
        author: 'UAM Tests',
        tags: const <String>['round', 'trip'],
      ),
      compatibility: const PresetCompatibility(
        minimumUamVersion: '0.1.0',
        deviceIndependent: true,
      ),
      audio: PresetAudio(
        preampDb: preamp,
        bands:
            bands ??
            const <EqBandConfiguration>[
              EqBandConfiguration(
                filterType: EqFilterType.peaking,
                frequencyHz: 1000,
                gainDb: 3,
                q: 1,
              ),
              EqBandConfiguration(
                filterType: EqFilterType.lowShelf,
                frequencyHz: 100,
                gainDb: 2,
                q: 0.7,
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

  setUp(() async {
    stack = await TestDataStack.create();
    repo = stack.presets as SqlitePresetRepository;
    // Production seeds built-ins during library load, not at database open.
    await repo.ensureBuiltinsSeeded();
  });

  tearDown(() async {
    await stack.dispose();
  });

  group('built-in seeding', () {
    test('seeds exactly three built-ins on first open', () async {
      final all = await repo.getAll();
      expect(all, hasLength(3));
      expect(all.every((entry) => entry.isBuiltIn), isTrue);
      expect(all.map((entry) => entry.id).toSet(), <String>{
        'builtin-balanced-warm',
        'builtin-neutral-reference',
        'builtin-shelf-bass-boost',
      });
    });

    test('re-seeding is idempotent and preserves favorites', () async {
      await repo.setFavorite('builtin-balanced-warm', true);
      await repo.ensureBuiltinsSeeded();
      await repo.ensureBuiltinsSeeded();
      final all = await repo.getAll();
      expect(all.where((entry) => entry.isBuiltIn), hasLength(3));
      expect(
        all
            .firstWhere((entry) => entry.id == 'builtin-balanced-warm')
            .isFavorite,
        isTrue,
      );
    });

    test(
      'a stale seed version triggers a re-seed without duplication',
      () async {
        await stack.services.database.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: <Object?>[AppSettingKeys.builtinSeedVersion],
        );
        await repo.ensureBuiltinsSeeded();
        expect((await repo.getAll()).where((e) => e.isBuiltIn), hasLength(3));
      },
    );

    test('the persisted seed version matches the config', () async {
      await repo.ensureBuiltinsSeeded();
      final rows = await stack.services.database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[AppSettingKeys.builtinSeedVersion],
      );
      expect(rows, hasLength(1));
      expect(rows.single['value_json'], '1');
    });
  });

  group('preset CRUD', () {
    test('create stores a document and round-trips every field', () async {
      final document = _document();
      final created = await repo.create(
        document,
        id: 'user-round-trip',
        source: PresetSource.user,
      );
      expect(created.id, 'user-round-trip');
      expect(created.name, 'Round Trip');
      expect(created.category, 'round');
      expect(created.isBuiltIn, isFalse);
      expect(created.source, PresetSource.user);

      final reloaded = await repo.getById('user-round-trip');
      expect(reloaded, isNotNull);
      expect(reloaded!.document.audio.preampDb, -1.0);
      expect(reloaded.document.bandCount, 2);
      expect(
        reloaded.document.audio.bands.first.filterType,
        EqFilterType.peaking,
      );
      expect(
        reloaded.document.audio.bands[1].filterType,
        EqFilterType.lowShelf,
      );
      expect(reloaded.document.metadata.tags, <String>['round', 'trip']);
    });

    test('create rejects a duplicate identifier', () async {
      await repo.create(_document(), id: 'dup-1');
      await expectLater(
        repo.create(_document(), id: 'dup-1'),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.duplicateId,
          ),
        ),
      );
    });

    test('create rejects an invalid document', () async {
      final invalid = PresetDocument(
        metadata: const PresetMetadata(name: ''),
        compatibility: const PresetCompatibility(),
        audio: const PresetAudio(
          preampDb: 0,
          bands: <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 1000,
              gainDb: 0,
              q: 1,
            ),
          ],
        ),
      );
      await expectLater(
        repo.create(invalid, id: 'invalid'),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.invalidPreset,
          ),
        ),
      );
    });

    test('generated identifiers are unique and source-prefixed', () async {
      final first = await repo.create(_document(name: 'First'));
      final second = await repo.create(_document(name: 'Second'));
      expect(first.id, isNot(second.id));
      expect(first.id, startsWith('user-'));
    });

    test('update replaces the document and the filter cascade', () async {
      await repo.create(_document(name: 'Before'), id: 'user-edit');
      await repo.update(
        'user-edit',
        _document(
          name: 'After',
          preamp: -4.0,
          bands: const <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.highShelf,
              frequencyHz: 8000,
              gainDb: -3,
              q: 0.9,
            ),
          ],
        ),
      );
      final updated = await repo.getById('user-edit');
      expect(updated!.name, 'After');
      expect(updated.document.bandCount, 1);
      expect(
        updated.document.audio.bands.single.filterType,
        EqFilterType.highShelf,
      );
      final filters = await stack.services.database.query(
        'preset_filters',
        where: 'preset_id = ?',
        whereArgs: <Object?>['user-edit'],
      );
      expect(
        filters,
        hasLength(1),
        reason: 'Old filter rows must be replaced.',
      );
    });

    test('update rejects built-ins and unknown ids', () async {
      await expectLater(
        repo.update('builtin-balanced-warm', _document()),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.constraintViolation,
          ),
        ),
      );
      await expectLater(
        repo.update('missing', _document()),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.notFound,
          ),
        ),
      );
    });

    test('delete removes a user preset and cascades filters', () async {
      await repo.create(_document(), id: 'user-delete');
      expect(await repo.delete('user-delete'), isTrue);
      expect(await repo.getById('user-delete'), isNull);
      final filters = await stack.services.database.query(
        'preset_filters',
        where: 'preset_id = ?',
        whereArgs: <Object?>['user-delete'],
      );
      expect(filters, isEmpty);
    });

    test('delete refuses built-ins and missing ids', () async {
      expect(await repo.delete('builtin-neutral-reference'), isFalse);
      expect(await repo.getById('builtin-neutral-reference'), isNotNull);
      expect(await repo.delete('missing'), isFalse);
    });

    test('deleting the active preset clears the selection', () async {
      await repo.create(_document(), id: 'user-active');
      await repo.setActivePreset('user-active');
      expect(await repo.getActivePresetId(), 'user-active');
      await repo.delete('user-active');
      expect(await repo.getActivePresetId(), isNull);
    });

    test('favorites toggle and list', () async {
      await repo.create(_document(name: 'Fav'), id: 'user-fav');
      expect(await repo.setFavorite('user-fav', true), isTrue);
      expect(await repo.getFavorites(), hasLength(1));
      expect((await repo.getFavorites()).single.id, 'user-fav');
      expect(await repo.setFavorite('user-fav', false), isTrue);
      expect(await repo.getFavorites(), isEmpty);
      expect(await repo.setFavorite('missing', true), isFalse);
    });

    test(
      'search matches name, description, author, category and tags',
      () async {
        await repo.create(_document(name: 'Warm Night'), id: 'user-search');
        expect(
          (await repo.search('warm')).map((e) => e.id),
          contains('user-search'),
        );
        expect(
          (await repo.search('UAM Tests')).map((e) => e.id),
          contains('user-search'),
        );
        expect(
          (await repo.search('round')).map((e) => e.id),
          contains('user-search'),
        );
        expect(await repo.search('  '), hasLength(4));
      },
    );

    test('getByCategory returns only that category', () async {
      await repo.create(_document(name: 'Categorized'), id: 'user-cat');
      final rows = await repo.getByCategory('round');
      expect(rows.map((e) => e.id), <String>['user-cat']);
      expect(await repo.getByCategory('missing'), isEmpty);
    });

    test('nameExists is case-insensitive and can exclude an id', () async {
      await repo.create(_document(name: 'Night Mode'), id: 'user-name');
      expect(await repo.nameExists('night mode'), isTrue);
      expect(await repo.nameExists('NIGHT MODE'), isTrue);
      expect(await repo.nameExists('missing'), isFalse);
      expect(
        await repo.nameExists('night mode', excludeId: 'user-name'),
        isFalse,
      );
    });

    test('exists distinguishes known from unknown ids', () async {
      expect(await repo.exists('builtin-balanced-warm'), isTrue);
      expect(await repo.exists('nope'), isFalse);
    });
  });

  group('active preset persistence', () {
    test('an active preset survives a reopen', () async {
      await repo.create(_document(), id: 'user-persist');
      await repo.setActivePreset('user-persist');

      final reopened = await stack.reopen();
      addTearDown(() => reopened.dispose(deleteDirectory: false));
      expect(await reopened.presets.getActivePresetId(), 'user-persist');
    });

    test('setting a missing preset as active throws notFound', () async {
      await expectLater(
        repo.setActivePreset('missing'),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.notFound,
          ),
        ),
      );
    });

    test('a dangling active reference clears itself', () async {
      await repo.create(_document(), id: 'user-dangling');
      await repo.setActivePreset('user-dangling');
      await stack.services.database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[AppSettingKeys.activePresetId],
      );
      expect(await repo.getActivePresetId(), isNull);
    });

    test('malformed active preset JSON reads as unset', () async {
      await stack.services.database.rawInsert(
        'INSERT INTO app_settings (key, value_json, updated_at) '
        'VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json',
        <Object?>[
          AppSettingKeys.activePresetId,
          '{not json',
          '2026-01-01T00:00:00.000Z',
        ],
      );
      expect(await repo.getActivePresetId(), isNull);
    });
  });

  group('ordering and immutability', () {
    test('getAll sorts built-ins first then by name', () async {
      await repo.create(_document(name: 'AAA User'), id: 'user-aaa');
      final all = await repo.getAll();
      final builtinCount = all.where((entry) => entry.isBuiltIn).length;
      expect(all.take(builtinCount).every((entry) => entry.isBuiltIn), isTrue);
      expect(all.skip(builtinCount).first.name, 'AAA User');
    });

    test('returned lists are unmodifiable', () async {
      final all = await repo.getAll();
      expect(() => all.add(all.first), throwsA(isA<UnsupportedError>()));
    });

    test('an entry exposes a stable category from its first tag', () async {
      final created = await repo.create(_document(), id: 'user-entry');
      expect(created.category, 'round');
      expect(created, isA<PresetEntry>());
    });

    test('a preset with no tags is uncategorised', () async {
      final document = PresetDocument(
        metadata: const PresetMetadata(name: 'No Tags'),
        compatibility: const PresetCompatibility(),
        audio: const PresetAudio(
          preampDb: 0,
          bands: <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 500,
              gainDb: 0,
              q: 1,
            ),
          ],
        ),
      );
      final result = PresetCodec.parse(document.toPrettyJson());
      final created = await repo.create(result.preset!, id: 'user-notags');
      expect(created.category, 'Uncategorised');
    });
  });
}
