import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_setting_keys.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_config.dart';
import '../../../core/database/database_exception.dart';
import '../../../core/files/atomic_file_writer.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/preset_document.dart';
import '../../presets/data/preset_repository.dart';
import '../../presets/domain/preset_entry.dart';
import '../../presets/domain/preset_source.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/backup_package.dart';

/// Result of writing a backup file.
final class BackupWriteResult {
  const BackupWriteResult({
    required this.path,
    required this.bytes,
    required this.presetCount,
    required this.checksum,
  });

  final String path;
  final int bytes;
  final int presetCount;
  final String checksum;
}

/// Result of completing a restore.
final class RestoreReport {
  const RestoreReport({
    required this.presetsRestored,
    required this.settingsRestored,
    required this.activePresetId,
    this.preRestoreBackupPath,
  });

  final int presetsRestored;
  final int settingsRestored;
  final String? activePresetId;

  /// Path of the automatic backup written before the restore, when feasible.
  final String? preRestoreBackupPath;
}

/// Where the automatic pre-restore snapshot is stored.
typedef BackupDirectoryProvider = Future<Directory> Function();

/// Local backup and restore for the UAM data subsystem.
///
/// Safety model:
/// 1. Read the container with a size bound and verify its checksum.
/// 2. Validate every embedded preset before any write.
/// 3. Ask the caller to confirm using [BackupPackage.summary].
/// 4. Write an automatic pre-restore snapshot when possible.
/// 5. Replace data inside one SQLite transaction.
/// 6. Run post-restore integrity checks and report data equivalence.
///
/// A failure at any step leaves the previous data intact because SQLite rolls
/// the transaction back and the original database file is never deleted.
final class BackupService {
  BackupService({
    required UamDatabase database,
    required PresetRepository presets,
    required SettingsRepository settings,
    required BackupDirectoryProvider directoryProvider,
    DateTime Function()? clock,
    String? appVersion,
    int? schemaVersion,
  }) : _db = database,
       _presetRepository = presets,
       _settingsRepository = settings,
       _backupDirectoryProvider = directoryProvider,
       _clock = clock ?? DateTime.now,
       _appVersion = appVersion ?? AppConstants.appVersion,
       _schemaVersion = schemaVersion ?? DatabaseConfig.schemaVersion;

  final UamDatabase _db;
  final PresetRepository _presetRepository;
  final SettingsRepository _settingsRepository;
  final BackupDirectoryProvider _backupDirectoryProvider;
  final DateTime Function() _clock;
  final String _appVersion;
  final int _schemaVersion;

  /// Collect current state into a [BackupPackage].
  Future<BackupPackage> createPackage() async {
    final entries = await _presetRepository.getAll();
    final allSettings = await _settingsRepository.getAll();
    final settings = <String, Object?>{
      for (final entry in allSettings.entries)
        if (!entry.key.startsWith(BackupFormat.excludedSettingsPrefix))
          entry.key: entry.value,
    };
    final active = await _presetRepository.getActivePresetId();
    return BackupPackage(
      backupFormatVersion: BackupFormat.currentVersion,
      createdAt: _clock().toUtc().toIso8601String(),
      appVersion: _appVersion,
      databaseSchemaVersion: _schemaVersion,
      presets: <BackupPresetRecord>[
        for (final entry in entries)
          BackupPresetRecord(
            id: entry.id,
            document: entry.document,
            source: entry.source,
            isFavorite: entry.isFavorite,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
          ),
      ],
      settings: Map<String, Object?>.unmodifiable(settings),
      activePresetId: active,
    );
  }

  /// Default file name for a new backup.
  String suggestedFileName() {
    final now = _clock().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'uam-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${BackupFormat.fileExtension}';
  }

  /// Build and self-verify the backup bytes for the current state.
  ///
  /// The container is parsed again before it is returned, so a corrupt backup
  /// file is never produced or written.
  Future<({Uint8List bytes, BackupPackage package})> buildBytes() async {
    final package = await createPackage();
    if (package.presets.isEmpty) {
      throw const UamDataException(
        UamDataErrorCode.notFound,
        'There is nothing to back up: the library contains no presets.',
      );
    }
    final bytes = BackupCodec.encode(package);
    final roundTripped = BackupCodec.parse(bytes);
    if (roundTripped.presets.length != package.presets.length) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The generated backup failed its own validation and was not written.',
      );
    }
    return (bytes: bytes, package: package);
  }

  /// Record that a backup was written to [destinationPath].
  Future<void> recordBackup(String destinationPath, int byteCount) async {
    await _settingsRepository.set(
      AppSettingKeys.lastBackupAt,
      _clock().toUtc().toIso8601String(),
    );
    await _settingsRepository.set(
      AppSettingKeys.lastBackupPath,
      p.basename(destinationPath),
    );
    AppLogger.info('Backup written ($byteCount bytes).');
  }

  /// Write a validated backup container to [destinationPath].
  Future<BackupWriteResult> writeBackup(String destinationPath) async {
    final built = await buildBytes();
    await AtomicFileWriter.writeBytes(destinationPath, built.bytes);
    await recordBackup(destinationPath, built.bytes.length);
    return BackupWriteResult(
      path: destinationPath,
      bytes: built.bytes.length,
      presetCount: built.package.presets.length,
      checksum: BackupCodec.computeChecksum(<String, Object?>{
        'presets': <Map<String, Object?>>[
          for (final record in built.package.presets) record.toJson(),
        ],
        'settings': built.package.settings,
        'activePresetId': built.package.activePresetId,
      }),
    );
  }

  /// Read and validate a backup file without modifying anything.
  Future<BackupPackage> inspectBackup(String path) async {
    final bytes = await AtomicFileWriter.readBounded(
      path,
      maxBytes: BackupFormat.maxBytes,
    );
    return BackupCodec.parse(Uint8List.fromList(bytes));
  }

  /// Restore [package].
  ///
  /// [confirmed] must be true; the function refuses to touch data otherwise so a
  /// caller can never restore without an explicit user decision.
  Future<RestoreReport> restore(
    BackupPackage package, {
    required bool confirmed,
    String? preRestoreDestination,
  }) async {
    if (!confirmed) {
      throw const UamDataException(
        UamDataErrorCode.cancelled,
        'The restore was cancelled before any data was changed.',
      );
    }
    if (package.databaseSchemaVersion > _schemaVersion) {
      throw UamDataException.unsupportedSchema(
        found: package.databaseSchemaVersion,
        supported: _schemaVersion,
      );
    }
    // Re-validate every document before writing.
    for (final record in package.presets) {
      final parsed = PresetCodec.parse(record.document.toPrettyJson());
      if (!parsed.isValid) {
        throw const UamDataException(
          UamDataErrorCode.invalidPreset,
          'A preset inside the backup is invalid; nothing was restored.',
        );
      }
    }

    String? preRestorePath;
    try {
      preRestorePath = await _writePreRestoreSnapshot(
        preferredDestination: preRestoreDestination,
      );
    } on UamDataException catch (error) {
      AppLogger.warning(
        'Pre-restore snapshot could not be written (${error.code.name}); '
        'the restore uses a database transaction instead.',
      );
    }

    await _db.transaction((txn) async {
      // 1. Remove every non-built-in preset (filters cascade).
      await txn.delete(
        'preset_filters',
        where: 'preset_id IN (SELECT id FROM presets WHERE is_builtin = 0)',
      );
      await txn.delete('presets', where: 'is_builtin = 0');

      // 2. Upsert every preset from the backup. Built-ins keep their local row
      //    identity but adopt the backed-up content, favorites and timestamps.
      for (final record in package.presets) {
        final timestamp =
            record.updatedAt ?? _clock().toUtc().toIso8601String();
        final row = <String, Object?>{
          'id': record.id,
          'name': record.document.metadata.name,
          'description': record.document.metadata.description,
          'author': record.document.metadata.author,
          'category': record.document.metadata.tags.isEmpty
              ? 'Uncategorised'
              : record.document.metadata.tags.first,
          'schema_version': PresetDocument.schemaVersion,
          'source': record.source.wireName,
          'is_builtin': record.source == PresetSource.builtin ? 1 : 0,
          'is_favorite': record.isFavorite ? 1 : 0,
          'preamp_db': record.document.audio.preampDb,
          'created_at':
              record.createdAt ??
              record.document.metadata.createdAt ??
              timestamp,
          'updated_at': timestamp,
          'metadata_json': _encodeMetadata(record.document),
          'compatibility_json': _encodeCompatibility(record.document),
        };
        await txn.rawInsert(
          '''
          INSERT INTO presets (
            id, name, description, author, category, schema_version, source,
            is_builtin, is_favorite, preamp_db, created_at, updated_at,
            metadata_json, compatibility_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            description = excluded.description,
            author = excluded.author,
            category = excluded.category,
            schema_version = excluded.schema_version,
            source = excluded.source,
            is_favorite = excluded.is_favorite,
            preamp_db = excluded.preamp_db,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            metadata_json = excluded.metadata_json,
            compatibility_json = excluded.compatibility_json
          ''',
          <Object?>[
            row['id'],
            row['name'],
            row['description'],
            row['author'],
            row['category'],
            row['schema_version'],
            row['source'],
            row['is_builtin'],
            row['is_favorite'],
            row['preamp_db'],
            row['created_at'],
            row['updated_at'],
            row['metadata_json'],
            row['compatibility_json'],
          ],
        );
        await txn.delete(
          'preset_filters',
          where: 'preset_id = ?',
          whereArgs: <Object?>[record.id],
        );
        final bands = record.document.audio.bands;
        for (var position = 0; position < bands.length; position += 1) {
          final band = bands[position];
          await txn.insert('preset_filters', <String, Object?>{
            'preset_id': record.id,
            'position': position,
            'filter_type': band.filterType.wireName,
            'frequency_hz': band.frequencyHz,
            'gain_db': band.gainDb,
            'q_factor': band.q,
          });
        }
      }

      // 3. Replace user-facing settings (keep internal bookkeeping).
      await txn.delete(
        'app_settings',
        where: "key LIKE 'appearance.%' OR key LIKE 'general.%'",
      );
      final now = _clock().toUtc().toIso8601String();
      for (final entry in package.settings.entries) {
        if (entry.key.startsWith(BackupFormat.excludedSettingsPrefix)) {
          continue;
        }
        await txn.rawInsert(
          '''
          INSERT INTO app_settings (key, value_json, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at
          ''',
          <Object?>[entry.key, _encodeJson(entry.value), now],
        );
      }
      await txn.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[AppSettingKeys.activePresetId],
      );
      final activeId = package.activePresetId;
      if (activeId != null) {
        final present = await txn.query(
          'presets',
          columns: const <String>['id'],
          where: 'id = ?',
          whereArgs: <Object?>[activeId],
          limit: 1,
        );
        if (present.isNotEmpty) {
          await txn.rawInsert(
            '''
            INSERT INTO app_settings (key, value_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
              value_json = excluded.value_json,
              updated_at = excluded.updated_at
            ''',
            <Object?>[
              AppSettingKeys.activePresetId,
              _encodeJson(activeId),
              now,
            ],
          );
        }
      }
    });

    // Post-restore verification. A failed check throws so the caller reports a
    // real problem rather than a fake success message.
    await _db.verifyIntegrity();
    final restored = await _presetRepository.getAll();
    final byId = <String, PresetEntry>{
      for (final entry in restored) entry.id: entry,
    };
    for (final record in package.presets) {
      final entry = byId[record.id];
      if (entry == null || !BackupCodec.entriesMatch(entry, record)) {
        throw UamDataException(
          UamDataErrorCode.corruptData,
          'The restored preset "${record.id}" does not match the backup.',
        );
      }
    }

    return RestoreReport(
      presetsRestored: package.presets.length,
      settingsRestored: package.settings.length,
      activePresetId: await _presetRepository.getActivePresetId(),
      preRestoreBackupPath: preRestorePath,
    );
  }

  Future<String?> _writePreRestoreSnapshot({
    String? preferredDestination,
  }) async {
    final package = await createPackage();
    final bytes = BackupCodec.encode(package);
    String destination;
    if (preferredDestination != null) {
      destination = preferredDestination;
    } else {
      final directory = await _backupDirectoryProvider();
      final stamp = _clock().toUtc().toIso8601String().replaceAll(':', '-');
      destination = p.join(directory.path, 'pre-restore-$stamp.uam-backup');
    }
    await AtomicFileWriter.writeBytes(destination, bytes);
    return destination;
  }

  String _encodeMetadata(PresetDocument document) {
    final metadata = document.metadata;
    return _encodeJson(<String, Object?>{
      if (metadata.createdAt != null) 'createdAt': metadata.createdAt,
      'tags': metadata.tags,
    });
  }

  String _encodeCompatibility(PresetDocument document) =>
      _encodeJson(document.compatibility.toJson());

  String _encodeJson(Object? value) => jsonEncode(value);
}
