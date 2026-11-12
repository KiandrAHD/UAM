import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uam/core/database/app_setting_keys.dart';
import 'package:uam/core/database/database_config.dart';
import 'package:uam/core/database/database_exception.dart';
import 'package:uam/features/backup/data/backup_service.dart';
import 'package:uam/features/backup/domain/backup_package.dart';
import 'package:uam/features/presets/data/sqlite_preset_repository.dart';
import 'package:uam/features/presets/domain/preset_source.dart';
import 'package:uam/shared/models/equalizer_configuration.dart';
import 'package:uam/shared/models/preset_document.dart';

import '../support/test_data_stack.dart';

PresetDocument _document({
  String name = 'Backup Preset',
  List<String> tags = const <String>['backup'],
  double preamp = -2.0,
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
  late BackupService backup;

  setUp(() async {
    stack = await TestDataStack.create();
    repo = stack.presets as SqlitePresetRepository;
    backup = stack.backup;
    await repo.ensureBuiltinsSeeded();
  });

  tearDown(() async {
    await stack.dispose();
  });

  group('package creation', () {
    test('captures presets, settings, and the active preset', () async {
      await repo.create(_document(), id: 'user-backup');
      await repo.setFavorite('user-backup', true);
      await repo.setActivePreset('user-backup');
      await stack.settings.set<String>(AppSettingKeys.themeMode, 'dark');

      final package = await backup.createPackage();
      expect(package.backupFormatVersion, BackupFormat.currentVersion);
      expect(package.databaseSchemaVersion, DatabaseConfig.schemaVersion);
      expect(package.presets, hasLength(4));
      expect(package.activePresetId, 'user-backup');
      expect(package.settings[AppSettingKeys.themeMode], 'dark');
      expect(package.userPresetCount, 1);
      expect(package.favoriteCount, 1);
      expect(package.summary, contains('4 presets'));
    });

    test('excludes internal bookkeeping settings from the package', () async {
      await stack.settings.set<String>('internal.secret', 'hidden');
      final package = await backup.createPackage();
      expect(package.settings.containsKey('internal.secret'), isFalse);
    });

    test('suggested file name ends with the backup extension', () {
      expect(backup.suggestedFileName(), endsWith('.uam-backup'));
      expect(backup.suggestedFileName(), startsWith('uam-backup-'));
    });

    test('buildBytes refuses to produce an empty backup', () async {
      // Delete every user preset and pretend the built-ins are absent by using
      // a database emptied of presets.
      await stack.services.database.delete('preset_filters');
      await stack.services.database.delete('presets');
      await expectLater(
        backup.buildBytes(),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.notFound,
          ),
        ),
      );
    });

    test(
      'buildBytes produces a container that re-parses identically',
      () async {
        await repo.create(_document(), id: 'user-bytes');
        final built = await backup.buildBytes();
        final parsed = BackupCodec.parse(built.bytes);
        expect(parsed.presets.length, built.package.presets.length);
        expect(parsed.activePresetId, built.package.activePresetId);
      },
    );
  });

  group('writing a backup file', () {
    test('writes a file and records the last backup metadata', () async {
      await repo.create(_document(), id: 'user-write');
      final destination = p.join(stack.directory.path, 'manual.uam-backup');

      final result = await backup.writeBackup(destination);

      expect(result.path, destination);
      expect(result.presetCount, 4);
      expect(result.bytes, greaterThan(0));
      expect(await File(destination).exists(), isTrue);
      expect(
        await stack.settings.get<String>(AppSettingKeys.lastBackupPath),
        'manual.uam-backup',
      );
      expect(
        await stack.settings.get<String>(AppSettingKeys.lastBackupAt),
        isNotNull,
      );

      final inspected = await backup.inspectBackup(destination);
      expect(inspected.presets, hasLength(4));
    });

    test('writing over an existing file replaces it atomically', () async {
      await repo.create(_document(), id: 'user-write2');
      final destination = p.join(stack.directory.path, 'overwrite.uam-backup');
      await File(destination).writeAsString('stale content');
      await backup.writeBackup(destination);
      final inspected = await backup.inspectBackup(destination);
      expect(inspected.presets, hasLength(4));
    });

    test('inspecting a missing file reports fileNotFound', () async {
      await expectLater(
        backup.inspectBackup(p.join(stack.directory.path, 'nope.uam-backup')),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.fileNotFound,
          ),
        ),
      );
    });
  });

  group('container validation', () {
    test('rejects an empty container', () {
      expect(
        () => BackupCodec.parse(Uint8List(0)),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.corruptData,
          ),
        ),
      );
    });

    test('rejects non-UTF-8 bytes', () {
      expect(
        () => BackupCodec.parse(Uint8List.fromList(<int>[0xff, 0x00, 0xfe])),
        throwsA(isA<UamDataException>()),
      );
    });

    test('rejects a non-JSON file', () {
      expect(
        () => BackupCodec.parse(Uint8List.fromList(utf8.encode('not json'))),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.corruptData,
          ),
        ),
      );
    });

    test('rejects a JSON document with the wrong format id', () async {
      final built = await backup.buildBytes();
      final map = jsonDecode(utf8.decode(built.bytes)) as Map<String, Object?>;
      map['format'] = 'something-else';
      expect(
        () =>
            BackupCodec.parse(Uint8List.fromList(utf8.encode(jsonEncode(map)))),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.corruptData,
          ),
        ),
      );
    });

    test('rejects a checksum mismatch', () async {
      final built = await backup.buildBytes();
      final map = jsonDecode(utf8.decode(built.bytes)) as Map<String, Object?>;
      final data = map['data']! as Map<String, Object?>;
      (data['settings']! as Map<String, Object?>)['appearance.themeMode'] =
          'dark';
      expect(
        () =>
            BackupCodec.parse(Uint8List.fromList(utf8.encode(jsonEncode(map)))),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.corruptData,
          ),
        ),
      );
    });

    test('rejects a newer backup format version', () async {
      final built = await backup.buildBytes();
      final map = jsonDecode(utf8.decode(built.bytes)) as Map<String, Object?>;
      map['backupFormatVersion'] = BackupFormat.currentVersion + 1;
      expect(
        () =>
            BackupCodec.parse(Uint8List.fromList(utf8.encode(jsonEncode(map)))),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.unsupportedSchema,
          ),
        ),
      );
    });

    test('rejects an unsupported older backup format version', () async {
      final built = await backup.buildBytes();
      final map = jsonDecode(utf8.decode(built.bytes)) as Map<String, Object?>;
      map['backupFormatVersion'] = 0;
      expect(
        () =>
            BackupCodec.parse(Uint8List.fromList(utf8.encode(jsonEncode(map)))),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.corruptData,
          ),
        ),
      );
    });

    test('rejects duplicate preset identifiers inside a container', () {
      final package = BackupPackage(
        backupFormatVersion: BackupFormat.currentVersion,
        createdAt: '2026-01-01T00:00:00.000Z',
        appVersion: '0.1.0',
        databaseSchemaVersion: 1,
        presets: <BackupPresetRecord>[
          BackupPresetRecord(
            id: 'dup',
            document: _document(name: 'One'),
            source: PresetSource.user,
            isFavorite: false,
          ),
          BackupPresetRecord(
            id: 'dup',
            document: _document(name: 'Two'),
            source: PresetSource.user,
            isFavorite: false,
          ),
        ],
        settings: const <String, Object?>{},
      );
      expect(
        () => BackupCodec.parse(BackupCodec.encode(package)),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.duplicateId,
          ),
        ),
      );
    });

    test('rejects an invalid embedded preset document', () {
      final package = BackupPackage(
        backupFormatVersion: BackupFormat.currentVersion,
        createdAt: '2026-01-01T00:00:00.000Z',
        appVersion: '0.1.0',
        databaseSchemaVersion: 1,
        presets: <BackupPresetRecord>[
          BackupPresetRecord(
            id: 'bad',
            document: const PresetDocument(
              metadata: PresetMetadata(name: ''),
              compatibility: PresetCompatibility(),
              audio: PresetAudio(preampDb: 0, bands: <EqBandConfiguration>[]),
            ),
            source: PresetSource.user,
            isFavorite: false,
          ),
        ],
        settings: const <String, Object?>{},
      );
      expect(
        () => BackupCodec.parse(BackupCodec.encode(package)),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.invalidPreset,
          ),
        ),
      );
    });

    test('documentsMatch compares cascades field by field', () {
      final a = _document(name: 'Same');
      final b = _document(name: 'Same');
      expect(BackupCodec.documentsMatch(a, b), isTrue);
      expect(BackupCodec.documentsMatch(a, _document(name: 'Other')), isFalse);
      expect(
        BackupCodec.documentsMatch(a, _document(name: 'Same', preamp: -9)),
        isFalse,
      );
    });
  });

  group('restore', () {
    test('refuses to restore without explicit confirmation', () async {
      final built = await backup.buildBytes();
      await expectLater(
        backup.restore(built.package, confirmed: false),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.cancelled,
          ),
        ),
      );
    });

    test('refuses a backup from a newer database schema', () async {
      final package = await backup.createPackage();
      final futurePackage = BackupPackage(
        backupFormatVersion: package.backupFormatVersion,
        createdAt: package.createdAt,
        appVersion: package.appVersion,
        databaseSchemaVersion: DatabaseConfig.schemaVersion + 1,
        presets: package.presets,
        settings: package.settings,
        activePresetId: package.activePresetId,
      );
      await expectLater(
        backup.restore(futurePackage, confirmed: true),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.unsupportedSchema,
          ),
        ),
      );
    });

    test('refuses a package with an invalid preset before writing', () async {
      final package = await backup.createPackage();
      final broken = BackupPackage(
        backupFormatVersion: package.backupFormatVersion,
        createdAt: package.createdAt,
        appVersion: package.appVersion,
        databaseSchemaVersion: package.databaseSchemaVersion,
        presets: <BackupPresetRecord>[
          ...package.presets,
          BackupPresetRecord(
            id: 'broken',
            document: const PresetDocument(
              metadata: PresetMetadata(name: ''),
              compatibility: PresetCompatibility(),
              audio: PresetAudio(preampDb: 0, bands: <EqBandConfiguration>[]),
            ),
            source: PresetSource.user,
            isFavorite: false,
          ),
        ],
        settings: package.settings,
        activePresetId: package.activePresetId,
      );
      final before = (await repo.getAll()).length;
      await expectLater(
        backup.restore(broken, confirmed: true),
        throwsA(
          isA<UamDataException>().having(
            (error) => error.code,
            'code',
            UamDataErrorCode.invalidPreset,
          ),
        ),
      );
      expect(await repo.getAll(), hasLength(before));
    });

    test(
      'round-trips data equivalence and writes a pre-restore snapshot',
      () async {
        await repo.create(_document(name: 'Snapshot Me'), id: 'user-snap');
        await repo.setFavorite('user-snap', true);
        await repo.setActivePreset('user-snap');
        await stack.settings.set<String>(AppSettingKeys.themeMode, 'dark');

        final built = await backup.buildBytes();

        // Mutate the live data so the restore has something to undo.
        await repo.delete('user-snap');
        await stack.settings.set<String>(AppSettingKeys.themeMode, 'light');

        final report = await backup.restore(built.package, confirmed: true);

        expect(report.presetsRestored, built.package.presets.length);
        expect(report.activePresetId, 'user-snap');
        expect(report.preRestoreBackupPath, isNotNull);
        expect(await File(report.preRestoreBackupPath!).exists(), isTrue);

        final restored = await repo.getById('user-snap');
        expect(restored, isNotNull);
        expect(restored!.isFavorite, isTrue);
        expect(
          BackupCodec.documentsMatch(
            restored.document,
            _document(name: 'Snapshot Me'),
          ),
          isTrue,
        );
        expect(await repo.getActivePresetId(), 'user-snap');
        expect(
          await stack.settings.get<String>(AppSettingKeys.themeMode),
          'dark',
        );
      },
    );

    test(
      'restore removes user presets that are absent from the backup',
      () async {
        await repo.create(_document(name: 'In Backup'), id: 'user-in');
        final built = await backup.buildBytes();

        await repo.create(_document(name: 'Not In Backup'), id: 'user-out');

        final report = await backup.restore(built.package, confirmed: true);
        expect(report.presetsRestored, built.package.presets.length);
        expect(await repo.getById('user-out'), isNull);
        expect(await repo.getById('user-in'), isNotNull);
        expect(
          (await repo.getAll()).where((e) => e.source != PresetSource.builtin),
          hasLength(1),
        );
      },
    );

    test('a restore preserves the built-in rows', () async {
      final built = await backup.buildBytes();
      await backup.restore(built.package, confirmed: true);
      final builtins = (await repo.getAll()).where((e) => e.isBuiltIn);
      expect(builtins, hasLength(3));
    });
  });
}
