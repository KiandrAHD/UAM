import 'dart:convert';

import '../../../core/database/database_exception.dart';
import '../../../shared/models/equalizer_configuration.dart';
import '../../../shared/models/preset_document.dart';
import '../domain/preset_entry.dart';
import '../domain/preset_source.dart';

/// Converts between [PresetEntry] domain objects and normalized database rows.
///
/// The database stores no single "document blob": identity and queryable fields
/// live in columns, non-columnar metadata in `metadata_json`, the compatibility
/// contract in `compatibility_json`, and the ordered equalizer cascade in
/// `preset_filters`. Export reconstructs the portable document from these rows.
abstract final class PresetRowMapper {
  static const String table = 'presets';
  static const String filterTable = 'preset_filters';

  /// Build the `presets` row for [document].
  static Map<String, Object?> toRow({
    required String id,
    required PresetDocument document,
    required PresetSource source,
    required bool isFavorite,
    required String? createdAt,
    required String updatedAt,
  }) {
    final metadata = document.metadata;
    return <String, Object?>{
      'id': id,
      'name': metadata.name,
      'description': metadata.description,
      'author': metadata.author,
      'category': _categoryOf(metadata.tags),
      'schema_version': PresetDocument.schemaVersion,
      'source': source.wireName,
      'is_builtin': source == PresetSource.builtin ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'preamp_db': document.audio.preampDb,
      'created_at': createdAt ?? metadata.createdAt ?? updatedAt,
      'updated_at': updatedAt,
      'metadata_json': jsonEncode(<String, Object?>{
        if (metadata.createdAt != null) 'createdAt': metadata.createdAt,
        'tags': metadata.tags,
      }),
      'compatibility_json': jsonEncode(document.compatibility.toJson()),
    };
  }

  /// Build the ordered `preset_filters` rows for a preset.
  static List<Map<String, Object?>> toFilterRows({
    required String presetId,
    required List<EqBandConfiguration> bands,
  }) {
    return <Map<String, Object?>>[
      for (var position = 0; position < bands.length; position += 1)
        <String, Object?>{
          'preset_id': presetId,
          'position': position,
          'filter_type': bands[position].filterType.wireName,
          'frequency_hz': bands[position].frequencyHz,
          'gain_db': bands[position].gainDb,
          'q_factor': bands[position].q,
        },
    ];
  }

  /// Rebuild a [PresetEntry] from a preset row and its filter rows.
  ///
  /// The reconstructed document is re-validated against schema version 1, so a
  /// tampered or corrupted row is surfaced as
  /// [UamDataErrorCode.invalidPreset] instead of being loaded into the editor.
  static PresetEntry toEntry(
    Map<String, Object?> row,
    List<Map<String, Object?>> filters,
  ) {
    final id = row['id'] as String? ?? '<unknown>';
    final metadataMap = _decodeObject(row['metadata_json'], 'metadata_json');
    final compatibilityMap = _decodeObject(
      row['compatibility_json'],
      'compatibility_json',
    );

    final tags = <String>[];
    final rawTags = metadataMap['tags'];
    if (rawTags is List<Object?>) {
      for (final tag in rawTags) {
        if (tag is String) {
          tags.add(tag);
        }
      }
    }

    final bands = <EqBandConfiguration>[];
    final ordered = List<Map<String, Object?>>.of(filters)
      ..sort(
        (a, b) =>
            (a['position'] as int? ?? 0).compareTo(b['position'] as int? ?? 0),
      );
    for (final filter in ordered) {
      final type = EqFilterType.tryParse(
        filter['filter_type'] as String? ?? '',
      );
      final frequency = filter['frequency_hz'];
      final gain = filter['gain_db'];
      final q = filter['q_factor'];
      if (type == null || frequency is! num || gain is! num || q is! num) {
        throw UamDataException(
          UamDataErrorCode.invalidPreset,
          'Preset "$id" contains an invalid equalizer band.',
        );
      }
      bands.add(
        EqBandConfiguration(
          filterType: type,
          frequencyHz: frequency.toDouble(),
          gainDb: gain.toDouble(),
          q: q.toDouble(),
        ),
      );
    }

    final document = PresetDocument(
      metadata: PresetMetadata(
        name: row['name'] as String? ?? '',
        author: row['author'] as String?,
        description: row['description'] as String?,
        createdAt: metadataMap['createdAt'] as String?,
        tags: List<String>.unmodifiable(tags),
      ),
      compatibility: PresetCompatibility(
        minimumUamVersion:
            compatibilityMap['minimumUamVersion'] as String? ?? '0.1.0',
        deviceIndependent:
            compatibilityMap['deviceIndependent'] as bool? ?? true,
        requiredCapabilities: <String>[
          if (compatibilityMap['requiredCapabilities'] is List<Object?>)
            for (final capability
                in compatibilityMap['requiredCapabilities'] as List<Object?>)
              if (capability is String) capability,
        ],
      ),
      audio: PresetAudio(
        preampDb: (row['preamp_db'] as num?)?.toDouble() ?? 0,
        bands: List<EqBandConfiguration>.unmodifiable(bands),
      ),
    );

    final validated = PresetCodec.parse(document.toPrettyJson());
    if (!validated.isValid || validated.preset == null) {
      throw UamDataException(
        UamDataErrorCode.invalidPreset,
        'Preset "$id" in the database no longer satisfies schema version 1.',
        cause: validated.errors.join('; '),
      );
    }

    return PresetEntry(
      id: id,
      document: validated.preset!,
      source: PresetSource.fromWire(row['source'] as String? ?? 'user'),
      isFavorite: (row['is_favorite'] as int? ?? 0) != 0,
      createdAt: row['created_at'] as String?,
      updatedAt: row['updated_at'] as String?,
    );
  }

  static String _categoryOf(List<String> tags) =>
      tags.isEmpty ? 'Uncategorised' : tags.first;

  static Map<String, Object?> _decodeObject(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw UamDataException(
        UamDataErrorCode.serialization,
        'Stored preset $field is missing.',
      );
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } on FormatException catch (error) {
      throw UamDataException(
        UamDataErrorCode.serialization,
        'Stored preset $field is not valid JSON.',
        cause: error,
      );
    }
    throw UamDataException(
      UamDataErrorCode.serialization,
      'Stored preset $field is not a JSON object.',
    );
  }
}
