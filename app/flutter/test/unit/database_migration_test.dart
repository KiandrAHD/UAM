import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uam/core/database/database.dart';
import 'package:uam/core/database/database_config.dart';
import 'package:uam/core/database/database_exception.dart';
import 'package:uam/core/database/database_factory.dart';
import 'package:uam/core/database/migrations/migration.dart';
import 'package:uam/core/database/migrations/migration_001_initial.dart';
import 'package:uam/core/database/migrations/migrations.dart';

Directory _createTempDir(String prefix) =>
    Directory.systemTemp.createTempSync(prefix);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final factory = UamDatabaseFactory.resolveNoIsolate();

  setUp(() async {
    await UamDatabase.resetOpenCache();
  });

  tearDown(() async {
    await UamDatabase.resetOpenCache();
  });

  group('MigrationRegistry', () {
    test('the shipped registry starts at version 1', () {
      expect(uamMigrations.startsAtOne, isTrue);
      expect(uamMigrations.latestVersion, 1);
      expect(uamMigrations.migrations, hasLength(1));
      expect(uamMigrations.migrations.first, same(migration001Initial));
    });

    test('rejects a registry that does not start at version 1', () {
      final registry = MigrationRegistry(const <Migration>[]);
      expect(registry.startsAtOne, isFalse);
      expect(registry.latestVersion, 0);
    });

    test('rejects duplicate versions', () {
      const duplicate = Migration(
        version: 1,
        description: 'duplicate',
        apply: _noop,
      );
      expect(
        () => MigrationRegistry(<Migration>[migration001Initial, duplicate]),
        throwsArgumentError,
      );
    });

    test('rejects non-positive versions', () {
      const zero = Migration(version: 0, description: 'zero', apply: _noop);
      expect(() => MigrationRegistry(<Migration>[zero]), throwsArgumentError);
    });

    test('pendingFrom returns only newer migrations', () {
      expect(uamMigrations.pendingFrom(0), hasLength(1));
      expect(uamMigrations.pendingFrom(1), isEmpty);
      expect(uamMigrations.pendingFrom(2), isEmpty);
    });

    test('migrate refuses a target newer than the registry', () async {
      final directory = _createTempDir('uam-mig-target-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final db = await factory.openDatabase(
        '${directory.path}${Platform.pathSeparator}target.db',
        options: OpenDatabaseOptions(singleInstance: true),
      );
      addTearDown(db.close);
      await expectLater(
        uamMigrations.migrate(db, from: 0, to: 2),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.unsupportedSchema,
          ),
        ),
      );
    });
  });

  group('UamDatabase', () {
    test('creates the version 1 schema on a fresh database', () async {
      final directory = _createTempDir('uam-mig-fresh-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final database = await UamDatabase.open(
        factory: factory,
        path: '${directory.path}${Platform.pathSeparator}uam.db',
      );
      addTearDown(database.close);

      expect(await database.schemaVersion(), 1);
      expect(database.isInMemory, isFalse);
      expect(database.isClosed, isFalse);

      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      final names = tables
          .map((row) => row['name'] as String)
          .where((name) => !name.startsWith('sqlite_'))
          .toList();
      expect(
        names,
        containsAll(<String>[
          'app_settings',
          'device_aliases',
          'preset_filters',
          'presets',
          'profiles',
        ]),
      );

      final journal = await database.rawQuery('PRAGMA journal_mode');
      expect(
        journal.first.values.first.toString().toLowerCase(),
        'wal',
        reason: 'File databases must use WAL for concurrent reads.',
      );

      final foreignKeys = await database.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeys.first.values.first, 1);
    });

    test('reopening an existing database is a no-op migration', () async {
      final directory = _createTempDir('uam-mig-reopen-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}uam.db';
      final first = await UamDatabase.open(factory: factory, path: path);
      await first.insert('app_settings', <String, Object?>{
        'key': 'appearance.themeMode',
        'value_json': '"dark"',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      await first.close();

      final second = await UamDatabase.open(factory: factory, path: path);
      addTearDown(second.close);
      expect(await second.schemaVersion(), 1);
      final rows = await second.query('app_settings');
      expect(rows, hasLength(1));
      expect(rows.first['value_json'], '"dark"');
    });

    test('refuses to open a database from a newer schema', () async {
      final directory = _createTempDir('uam-mig-newer-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}uam.db';

      final raw = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: true),
      );
      await raw.execute('PRAGMA user_version = 99');
      await raw.close();

      await expectLater(
        UamDatabase.open(factory: factory, path: path),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.unsupportedSchema,
          ),
        ),
        reason: 'A newer schema must never be silently downgraded.',
      );
      // A failed open must not poison the cache with a half-open handle.
      await UamDatabase.resetOpenCache();
    });

    test('foreign keys are enforced for preset_filters', () async {
      final directory = _createTempDir('uam-mig-fk-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final database = await UamDatabase.open(
        factory: factory,
        path: '${directory.path}${Platform.pathSeparator}uam.db',
      );
      addTearDown(database.close);

      await expectLater(
        database.insert('preset_filters', <String, Object?>{
          'preset_id': 'does-not-exist',
          'position': 0,
          'filter_type': 'peaking',
          'frequency_hz': 1000.0,
          'gain_db': 0.0,
          'q_factor': 1.0,
        }),
        throwsA(isA<DatabaseException>()),
        reason: 'ON DELETE CASCADE requires foreign keys to actually be on.',
      );
    });

    test('deleting a preset cascades to its filters', () async {
      final directory = _createTempDir('uam-mig-cascade-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final database = await UamDatabase.open(
        factory: factory,
        path: '${directory.path}${Platform.pathSeparator}uam.db',
      );
      addTearDown(database.close);

      await database.insert('presets', _presetRow('preset-a'));
      await database.insert('preset_filters', <String, Object?>{
        'preset_id': 'preset-a',
        'position': 0,
        'filter_type': 'peaking',
        'frequency_hz': 1000.0,
        'gain_db': 3.0,
        'q_factor': 1.0,
      });
      expect(await database.query('preset_filters'), hasLength(1));

      await database.delete(
        'presets',
        where: 'id = ?',
        whereArgs: ['preset-a'],
      );
      expect(await database.query('preset_filters'), isEmpty);
    });

    test('a successful extra migration advances user_version', () async {
      final directory = _createTempDir('uam-mig-v2-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}uam.db';

      final registry = MigrationRegistry(<Migration>[
        migration001Initial,
        const Migration(
          version: 2,
          description: 'add a probe table',
          apply: _probeMigration,
        ),
      ]);

      final opened = await UamDatabase.open(
        factory: factory,
        path: path,
        registry: registry,
      );
      addTearDown(opened.close);

      expect(await opened.schemaVersion(), 2);
      final tables = await opened.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'probe'",
      );
      expect(tables, hasLength(1));
    });

    test(
      'a thrown migration leaves the database at the previous version',
      () async {
        final directory = _createTempDir('uam-mig-roll-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final path = '${directory.path}${Platform.pathSeparator}uam.db';

        // Pre-create a v1 database, then attempt to open it with a registry whose
        // v2 migration fails. The failure must not leave user_version at 2.
        final v1 = await UamDatabase.open(factory: factory, path: path);
        expect(await v1.schemaVersion(), 1);
        await v1.insert('app_settings', <String, Object?>{
          'key': 'appearance.themeMode',
          'value_json': '"light"',
          'updated_at': '2026-01-01T00:00:00.000Z',
        });
        await v1.close();

        final broken = MigrationRegistry(<Migration>[
          migration001Initial,
          const Migration(
            version: 2,
            description: 'intentionally broken',
            apply: _brokenMigration,
          ),
        ]);

        final failedOpen = UamDatabase.open(
          factory: factory,
          path: path,
          registry: broken,
        );
        await expectLater(
          failedOpen,
          throwsA(
            isA<UamDataException>().having(
              (error) => error.code,
              'code',
              UamDataErrorCode.migrationFailure,
            ),
          ),
        );
        await UamDatabase.resetOpenCache();

        final reopened = await UamDatabase.open(factory: factory, path: path);
        addTearDown(reopened.close);
        expect(await reopened.schemaVersion(), 1);
        expect(
          await reopened.query('app_settings'),
          hasLength(1),
          reason: 'A rolled-back migration must not lose existing data.',
        );
        final survived = await reopened.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = "
          "'should_not_survive'",
        );
        expect(
          survived,
          isEmpty,
          reason: 'The migration DDL must roll back too.',
        );
      },
    );

    test(
      'a corrupt database file reports corruption instead of opening',
      () async {
        final directory = _createTempDir('uam-mig-corrupt-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}${Platform.pathSeparator}uam.db');
        final garbage = List<int>.generate(4096, (index) => index % 251);
        await file.writeAsBytes(garbage);

        await expectLater(
          UamDatabase.open(factory: factory, path: file.path),
          throwsA(
            isA<UamDataException>().having(
              (error) => error.code,
              'code',
              anyOf(
                UamDataErrorCode.corruptDatabase,
                UamDataErrorCode.databaseUnavailable,
              ),
            ),
          ),
        );
        await UamDatabase.resetOpenCache();
      },
    );

    test('a transaction rollback leaves earlier rows untouched', () async {
      final directory = _createTempDir('uam-mig-txn-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final database = await UamDatabase.open(
        factory: factory,
        path: '${directory.path}${Platform.pathSeparator}uam.db',
      );
      addTearDown(database.close);

      await database.insert('presets', _presetRow('kept'));

      await expectLater(
        database.transaction((txn) async {
          await txn.insert('presets', _presetRow('discarded'));
          throw StateError('simulated failure');
        }),
        throwsStateError,
      );

      final rows = await database.query('presets');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'kept');
    });

    test('in-memory databases report isInMemory and skip WAL', () async {
      final database = await UamDatabase.open(
        factory: factory,
        path: inMemoryDatabasePath,
        isInMemory: true,
      );
      addTearDown(database.close);
      expect(database.isInMemory, isTrue);
      expect(await database.schemaVersion(), 1);
    });

    test('opening the same path twice reuses one connection', () async {
      final directory = _createTempDir('uam-mig-single-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}uam.db';
      final a = await UamDatabase.open(factory: factory, path: path);
      final b = await UamDatabase.open(factory: factory, path: path);
      expect(identical(a, b), isTrue);
      await a.close();
      expect(b.isClosed, isTrue);
    });

    test('DatabaseConfig exposes the documented schema and file name', () {
      expect(DatabaseConfig.schemaVersion, uamMigrations.latestVersion);
      expect(DatabaseConfig.fileName, 'uam.db');
      expect(DatabaseConfig.busyTimeoutMs, greaterThan(0));
      expect(DatabaseConfig.builtinSeedVersion, greaterThanOrEqualTo(1));
    });
  });
}

Future<void> _noop(DatabaseExecutor db) async {}

Future<void> _probeMigration(DatabaseExecutor db) async {
  await db.execute('CREATE TABLE probe (id INTEGER)');
}

Future<void> _brokenMigration(DatabaseExecutor db) async {
  await db.execute('CREATE TABLE should_not_survive (id INTEGER)');
  throw StateError('simulated migration failure');
}

Map<String, Object?> _presetRow(String id) => <String, Object?>{
  'id': id,
  'name': 'Preset $id',
  'description': null,
  'author': null,
  'category': 'test',
  'schema_version': 1,
  'source': 'user',
  'is_builtin': 0,
  'is_favorite': 0,
  'preamp_db': 0.0,
  'created_at': '2026-01-01T00:00:00.000Z',
  'updated_at': '2026-01-01T00:00:00.000Z',
  'metadata_json': '{"tags":[]}',
  'compatibility_json':
      '{"minimumUamVersion":"0.1.0",'
      '"deviceIndependent":true,"requiredCapabilities":[]}',
};
