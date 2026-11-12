import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/database/database_exception.dart';
import '../../../core/serialization/canonical_json.dart';
import '../../../shared/models/equalizer_configuration.dart';
import '../../../shared/models/preset_document.dart';
import '../../presets/domain/preset_entry.dart';
import '../../presets/domain/preset_source.dart';

/// Versioned `.uam-backup` container.
///
/// Format (UTF-8 JSON, canonical key order):
/// ```json
/// {
///   "format": "uam-backup",
///   "backupFormatVersion": 1,
///   "createdAt": "2026-01-01T00:00:00.000Z",
///   "appVersion": "0.1.0",
///   "databaseSchemaVersion": 1,
///   "presetSchemaVersion": 1,
///   "data": {
///     "presets": [ PresetRecord... ],
///     "settings": { "appearance.themeMode": "dark" },
///     "activePresetId": "builtin-balanced-warm"
///   },
///   "checksum": { "algorithm": "sha256", "value": "<hex of data section>" }
/// }
/// ```
///
/// Only user-relevant data is included. Internal bookkeeping keys, caches,
/// logs, secrets, and native binaries are excluded by construction.
abstract final class BackupFormat {
  static const String formatId = 'uam-backup';
  static const int currentVersion = 1;

  /// Supported backup format versions, newest first.
  static const List<int> supportedVersions = <int>[1];

  static const String fileExtension = '.uam-backup';
  static const String checksumAlgorithm = 'sha256';

  /// Upper bound applied before parsing, and after bounded decompression.
  static const int maxBytes = 8 * 1024 * 1024;

  /// Settings keys excluded from user backups.
  static const String excludedSettingsPrefix = 'internal.';
}

/// One preset inside a backup container.
final class BackupPresetRecord {
  const BackupPresetRecord({
    required this.id,
    required this.document,
    required this.source,
    required this.isFavorite,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final PresetDocument document;
  final PresetSource source;
  final bool isFavorite;
  final String? createdAt;
  final String? updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source': source.wireName,
    'isFavorite': isFavorite,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'document': document.toJson(),
  };

  static BackupPresetRecord? tryFromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    final id = value['id'];
    final document = value['document'];
    if (id is! String || id.isEmpty || document is! Map<String, Object?>) {
      return null;
    }
    final parsed = PresetCodec.parse(jsonEncode(document));
    if (!parsed.isValid || parsed.preset == null) {
      return null;
    }
    return BackupPresetRecord(
      id: id,
      document: parsed.preset!,
      source: PresetSource.fromWire(value['source'] as String? ?? 'user'),
      isFavorite: value['isFavorite'] == true,
      createdAt: value['createdAt'] as String?,
      updatedAt: value['updatedAt'] as String?,
    );
  }
}

/// Parsed backup container.
final class BackupPackage {
  const BackupPackage({
    required this.backupFormatVersion,
    required this.createdAt,
    required this.appVersion,
    required this.databaseSchemaVersion,
    required this.presets,
    required this.settings,
    this.activePresetId,
  });

  final int backupFormatVersion;
  final String createdAt;
  final String appVersion;
  final int databaseSchemaVersion;
  final List<BackupPresetRecord> presets;
  final Map<String, Object?> settings;
  final String? activePresetId;

  int get userPresetCount =>
      presets.where((record) => record.source != PresetSource.builtin).length;

  int get favoriteCount => presets.where((record) => record.isFavorite).length;

  /// Human-readable restore summary shown before confirmation.
  String get summary =>
      '${presets.length} presets '
      '($userPresetCount user/imported), '
      '$favoriteCount favorites, '
      '${settings.length} settings, '
      'active preset ${activePresetId ?? 'none'}, '
      'created $createdAt with app $appVersion.';
}

/// Builder, parser, and checksum verifier for `.uam-backup` containers.
abstract final class BackupCodec {
  /// Build the container bytes for [package].
  static Uint8List encode(BackupPackage package) {
    final data = <String, Object?>{
      'presets': <Map<String, Object?>>[
        for (final record in package.presets) record.toJson(),
      ],
      'settings': package.settings,
      'activePresetId': package.activePresetId,
    };
    final checksum = computeChecksum(data);
    final container = <String, Object?>{
      'format': BackupFormat.formatId,
      'backupFormatVersion': package.backupFormatVersion,
      'createdAt': package.createdAt,
      'appVersion': package.appVersion,
      'databaseSchemaVersion': package.databaseSchemaVersion,
      'presetSchemaVersion': PresetDocument.schemaVersion,
      'data': data,
      'checksum': <String, Object?>{
        'algorithm': BackupFormat.checksumAlgorithm,
        'value': checksum,
      },
    };
    final text = const JsonEncoder.withIndent('  ').convert(container);
    return Uint8List.fromList(utf8.encode(text));
  }

  /// SHA-256 over the canonical JSON of [data].
  static String computeChecksum(Map<String, Object?> data) {
    final canonical = encodeCanonicalJson(data);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Parse and fully validate a backup container.
  ///
  /// Throws [UamDataException] with `corruptData` for a malformed container,
  /// `unsupportedSchema` for a future backup format, and `invalidPreset` when a
  /// preset inside the container no longer satisfies schema version 1.
  static BackupPackage parse(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The selected backup file is empty.',
      );
    }
    if (bytes.length > BackupFormat.maxBytes) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The selected backup file exceeds the supported size limit.',
      );
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The selected backup file is not valid UTF-8 text.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The selected backup file is not valid JSON.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup root must be a JSON object.',
      );
    }
    if (decoded['format'] != BackupFormat.formatId) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The selected file is not a UAM backup container.',
      );
    }
    final version = decoded['backupFormatVersion'];
    if (version is! int) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup container has no valid backup format version.',
      );
    }
    if (!BackupFormat.supportedVersions.contains(version)) {
      throw UamDataException(
        version > BackupFormat.currentVersion
            ? UamDataErrorCode.unsupportedSchema
            : UamDataErrorCode.corruptData,
        version > BackupFormat.currentVersion
            ? 'This backup was created by a newer UAM backup format '
                  '($version). This build supports up to '
                  '${BackupFormat.currentVersion}.'
            : 'Backup format version $version is not supported by this build.',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup container has no data section.',
      );
    }
    final checksum = decoded['checksum'];
    if (checksum is! Map<String, Object?> ||
        checksum['algorithm'] != BackupFormat.checksumAlgorithm ||
        checksum['value'] is! String) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup container has no supported integrity checksum.',
      );
    }
    final actual = computeChecksum(data);
    if (actual != checksum['value']) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup checksum does not match its contents. The file was '
        'modified or damaged.',
      );
    }

    final rawPresets = data['presets'];
    if (rawPresets is! List<Object?>) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup container has no preset list.',
      );
    }
    final presets = <BackupPresetRecord>[];
    final ids = <String>{};
    for (final raw in rawPresets) {
      final record = BackupPresetRecord.tryFromJson(raw);
      if (record == null) {
        throw const UamDataException(
          UamDataErrorCode.invalidPreset,
          'The backup contains a preset that does not satisfy schema '
          'version 1.',
        );
      }
      if (!ids.add(record.id)) {
        throw UamDataException(
          UamDataErrorCode.duplicateId,
          'The backup contains duplicate preset identifiers (${record.id}).',
        );
      }
      presets.add(record);
    }

    final rawSettings = data['settings'];
    final settings = <String, Object?>{};
    if (rawSettings is Map<String, Object?>) {
      for (final entry in rawSettings.entries) {
        if (entry.key.startsWith(BackupFormat.excludedSettingsPrefix)) {
          continue;
        }
        settings[entry.key] = entry.value;
      }
    }

    final activePresetId = data['activePresetId'];
    if (activePresetId != null && activePresetId is! String) {
      throw const UamDataException(
        UamDataErrorCode.corruptData,
        'The backup active preset identifier is not a string.',
      );
    }

    return BackupPackage(
      backupFormatVersion: version,
      createdAt: decoded['createdAt'] as String? ?? 'unknown',
      appVersion: decoded['appVersion'] as String? ?? 'unknown',
      databaseSchemaVersion: decoded['databaseSchemaVersion'] as int? ?? 0,
      presets: List<BackupPresetRecord>.unmodifiable(presets),
      settings: Map<String, Object?>.unmodifiable(settings),
      activePresetId: activePresetId as String?,
    );
  }

  /// Compare a preset document's filter cascade with a restored record.
  static bool documentsMatch(PresetDocument a, PresetDocument b) {
    if (a.metadata.name != b.metadata.name ||
        a.metadata.author != b.metadata.author ||
        a.metadata.description != b.metadata.description ||
        a.metadata.createdAt != b.metadata.createdAt ||
        a.audio.preampDb != b.audio.preampDb ||
        a.audio.bands.length != b.audio.bands.length ||
        !_listEquals(a.metadata.tags, b.metadata.tags) ||
        !_listEquals(
          a.compatibility.requiredCapabilities,
          b.compatibility.requiredCapabilities,
        ) ||
        a.compatibility.minimumUamVersion !=
            b.compatibility.minimumUamVersion ||
        a.compatibility.deviceIndependent !=
            b.compatibility.deviceIndependent) {
      return false;
    }
    for (var index = 0; index < a.audio.bands.length; index += 1) {
      final left = a.audio.bands[index];
      final right = b.audio.bands[index];
      if (left.filterType != right.filterType ||
          left.frequencyHz != right.frequencyHz ||
          left.gainDb != right.gainDb ||
          left.q != right.q) {
        return false;
      }
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

  /// Whether two entries represent the same stored preset.
  static bool entriesMatch(PresetEntry a, BackupPresetRecord b) {
    return a.id == b.id &&
        a.isFavorite == b.isFavorite &&
        a.source == b.source &&
        documentsMatch(a.document, b.document);
  }

  /// Convenience accessor used by validation tests.
  static List<EqBandConfiguration> bandsOf(PresetEntry entry) =>
      entry.document.audio.bands;
}
