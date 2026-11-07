import 'dart:convert';

import 'equalizer_configuration.dart';

/// Portable preset metadata.
final class PresetMetadata {
  const PresetMetadata({
    required this.name,
    this.author,
    this.description,
    this.createdAt,
    this.tags = const <String>[],
  });

  final String name;
  final String? author;
  final String? description;
  final String? createdAt;
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (author != null) 'author': author,
    if (description != null) 'description': description,
    if (createdAt != null) 'createdAt': createdAt,
    if (tags.isNotEmpty) 'tags': tags,
  };
}

/// Portable preset compatibility metadata.
final class PresetCompatibility {
  const PresetCompatibility({
    this.minimumUamVersion = '0.1.0',
    this.deviceIndependent = true,
    this.requiredCapabilities = const <String>[],
  });

  final String minimumUamVersion;
  final bool deviceIndependent;
  final List<String> requiredCapabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'minimumUamVersion': minimumUamVersion,
    'deviceIndependent': deviceIndependent,
    if (requiredCapabilities.isNotEmpty)
      'requiredCapabilities': requiredCapabilities,
  };
}

/// Portable preset audio section.
final class PresetAudio {
  const PresetAudio({required this.preampDb, required this.bands});

  final double preampDb;
  final List<EqBandConfiguration> bands;

  Map<String, Object?> toJson() => <String, Object?>{
    'preampDb': preampDb,
    'equalizer': <String, Object?>{
      'bands': <Map<String, Object?>>[for (final band in bands) band.toJson()],
    },
  };
}

/// Versioned `.uam-preset.json` document.
final class PresetDocument {
  const PresetDocument({
    required this.metadata,
    required this.compatibility,
    required this.audio,
  });

  static const String formatId = 'uam-preset';
  static const int schemaVersion = 1;
  static const String fileExtension = '.uam-preset.json';
  static const int maxBytes = 256 * 1024;

  final PresetMetadata metadata;
  final PresetCompatibility compatibility;
  final PresetAudio audio;

  int get bandCount => audio.bands.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': formatId,
    'schemaVersion': schemaVersion,
    'metadata': metadata.toJson(),
    'compatibility': compatibility.toJson(),
    'audio': audio.toJson(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Build a preset from the current graphic editor state.
  factory PresetDocument.fromEqualizer({
    required String name,
    required String? author,
    required String? description,
    required EqualizerConfiguration configuration,
  }) {
    return PresetDocument(
      metadata: PresetMetadata(
        name: name.trim(),
        author: author?.trim().isEmpty ?? true ? null : author!.trim(),
        description: description?.trim().isEmpty ?? true
            ? null
            : description!.trim(),
      ),
      compatibility: const PresetCompatibility(),
      audio: PresetAudio(
        preampDb: configuration.preampDb,
        bands: configuration.bands,
      ),
    );
  }
}

/// Parse outcome for untrusted preset input.
final class PresetParseResult {
  const PresetParseResult._({this.preset, required this.errors});

  factory PresetParseResult.success(PresetDocument preset) =>
      PresetParseResult._(preset: preset, errors: const <String>[]);

  factory PresetParseResult.invalid(List<String> errors) =>
      PresetParseResult._(errors: List<String>.unmodifiable(errors));

  final PresetDocument? preset;
  final List<String> errors;

  bool get isValid => preset != null && errors.isEmpty;
}

/// Strict parser mirroring the published schema and Rust validation contract.
///
/// The Rust crate remains the authoritative import boundary in later phases.
/// Phase 1 has no preset-validation FFI symbol, so this Dart implementation
/// mirrors the same field names, limits, and filter definitions and is tested
/// against the repository fixtures. The UI labels this as local schema
/// validation, never as a Rust call.
abstract final class PresetCodec {
  static PresetParseResult parse(String source) {
    final errors = <String>[];
    if (utf8.encode(source).length > PresetDocument.maxBytes) {
      return PresetParseResult.invalid(<String>[
        'The preset exceeds the 256 KiB import limit.',
      ]);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      return PresetParseResult.invalid(<String>[
        'Invalid JSON: ${error.message}',
      ]);
    }
    final root = _map(decoded);
    if (root == null) {
      return PresetParseResult.invalid(<String>[
        'The preset root must be a JSON object.',
      ]);
    }
    _rejectUnknown(
      root,
      const <String>{
        'format',
        'schemaVersion',
        'metadata',
        'compatibility',
        'audio',
      },
      '',
      errors,
    );

    if (root['format'] != PresetDocument.formatId) {
      errors.add('format must be "${PresetDocument.formatId}".');
    }
    final version = _integer(root['schemaVersion']);
    if (version != PresetDocument.schemaVersion) {
      errors.add(
        'schemaVersion ${version ?? 'missing'} is not supported; '
        'this build implements schema version ${PresetDocument.schemaVersion}.',
      );
    }

    final metadata = _parseMetadata(root['metadata'], errors);
    final compatibility = _parseCompatibility(root['compatibility'], errors);
    final audio = _parseAudio(root['audio'], errors);

    if (errors.isNotEmpty ||
        metadata == null ||
        compatibility == null ||
        audio == null) {
      return PresetParseResult.invalid(errors);
    }
    return PresetParseResult.success(
      PresetDocument(
        metadata: metadata,
        compatibility: compatibility,
        audio: audio,
      ),
    );
  }

  static PresetMetadata? _parseMetadata(Object? value, List<String> errors) {
    final map = _map(value);
    if (map == null) {
      errors.add('metadata must be an object.');
      return null;
    }
    _rejectUnknown(
      map,
      const <String>{'name', 'author', 'description', 'createdAt', 'tags'},
      'metadata.',
      errors,
    );
    final name = _string(map['name']);
    if (name == null || name.trim().isEmpty) {
      errors.add('metadata.name is required.');
    } else if (name.characters > 80) {
      errors.add('metadata.name must contain at most 80 characters.');
    }
    final author = _optionalString(map['author']);
    if (map['author'] != null &&
        (author == null || author.isEmpty || author.characters > 80)) {
      errors.add('metadata.author must contain 1–80 characters.');
    }
    final description = _optionalString(map['description']);
    if (map['description'] != null &&
        (description == null || description.characters > 1000)) {
      errors.add('metadata.description must contain at most 1,000 characters.');
    }
    final createdAt = _optionalString(map['createdAt']);
    if (map['createdAt'] != null &&
        (createdAt == null ||
            createdAt.length > 40 ||
            DateTime.tryParse(createdAt) == null)) {
      errors.add('metadata.createdAt must be an RFC 3339 timestamp.');
    }
    final tags = <String>[];
    if (map['tags'] != null) {
      final rawTags = map['tags'];
      if (rawTags is! List<Object?>) {
        errors.add('metadata.tags must be an array.');
      } else if (rawTags.length > 10) {
        errors.add('metadata.tags may contain at most 10 entries.');
      } else {
        final seen = <String>{};
        for (final rawTag in rawTags) {
          final tag = _string(rawTag);
          if (tag == null || tag.isEmpty || tag.characters > 32) {
            errors.add('Each tag must contain 1–32 characters.');
          } else if (!seen.add(tag)) {
            errors.add('metadata.tags must not contain duplicates.');
          } else {
            tags.add(tag);
          }
        }
      }
    }
    if (errors.isNotEmpty) {
      return null;
    }
    return PresetMetadata(
      name: name!,
      author: author,
      description: description,
      createdAt: createdAt,
      tags: List<String>.unmodifiable(tags),
    );
  }

  static PresetCompatibility? _parseCompatibility(
    Object? value,
    List<String> errors,
  ) {
    final map = _map(value);
    if (map == null) {
      errors.add('compatibility must be an object.');
      return null;
    }
    _rejectUnknown(
      map,
      const <String>{
        'minimumUamVersion',
        'deviceIndependent',
        'requiredCapabilities',
      },
      'compatibility.',
      errors,
    );
    final minimumVersion = _string(map['minimumUamVersion']);
    if (minimumVersion == null || !_isSemver(minimumVersion)) {
      errors.add(
        'compatibility.minimumUamVersion must be a three-component numeric version.',
      );
    }
    final deviceIndependent = map['deviceIndependent'];
    if (deviceIndependent != true) {
      errors.add('compatibility.deviceIndependent must be true.');
    }
    final required = <String>[];
    if (map['requiredCapabilities'] != null) {
      final rawRequired = map['requiredCapabilities'];
      if (rawRequired is! List<Object?>) {
        errors.add('compatibility.requiredCapabilities must be an array.');
      } else if (rawRequired.length > 16) {
        errors.add(
          'compatibility.requiredCapabilities may contain at most 16 entries.',
        );
      } else {
        final seen = <String>{};
        final pattern = RegExp(r'^[a-z0-9._:-]{1,64}$');
        for (final rawCapability in rawRequired) {
          final capability = _string(rawCapability);
          if (capability == null || !pattern.hasMatch(capability)) {
            errors.add('Capability identifiers must match [a-z0-9._:-]{1,64}.');
          } else if (!seen.add(capability)) {
            errors.add(
              'compatibility.requiredCapabilities must not contain duplicates.',
            );
          } else {
            required.add(capability);
          }
        }
      }
    }
    if (errors.isNotEmpty) {
      return null;
    }
    return PresetCompatibility(
      minimumUamVersion: minimumVersion!,
      deviceIndependent: true,
      requiredCapabilities: List<String>.unmodifiable(required),
    );
  }

  static PresetAudio? _parseAudio(Object? value, List<String> errors) {
    final map = _map(value);
    if (map == null) {
      errors.add('audio must be an object.');
      return null;
    }
    _rejectUnknown(
      map,
      const <String>{'preampDb', 'equalizer'},
      'audio.',
      errors,
    );
    final preamp = _number(map['preampDb']);
    if (preamp == null ||
        !preamp.isFinite ||
        preamp < EqConstraints.minPreampDb ||
        preamp > EqConstraints.maxPreampDb) {
      errors.add('audio.preampDb must be within -24 to +12 dB.');
    }
    final equalizer = _map(map['equalizer']);
    if (equalizer == null) {
      errors.add('audio.equalizer must be an object.');
      return null;
    }
    _rejectUnknown(
      equalizer,
      const <String>{'bands'},
      'audio.equalizer.',
      errors,
    );
    final rawBands = equalizer['bands'];
    if (rawBands is! List<Object?>) {
      errors.add('audio.equalizer.bands must be an array.');
      return null;
    }
    if (rawBands.length > EqConstraints.maxBands) {
      errors.add('audio.equalizer.bands may contain at most 32 bands.');
      return null;
    }
    final bands = <EqBandConfiguration>[];
    for (var index = 0; index < rawBands.length; index += 1) {
      final bandMap = _map(rawBands[index]);
      if (bandMap == null) {
        errors.add('audio.equalizer.bands[$index] must be an object.');
        continue;
      }
      _rejectUnknown(
        bandMap,
        const <String>{'filterType', 'frequencyHz', 'gainDb', 'q'},
        'audio.equalizer.bands[$index].',
        errors,
      );
      final typeValue = _string(bandMap['filterType']);
      final type = typeValue == null ? null : EqFilterType.tryParse(typeValue);
      if (type == null) {
        errors.add(
          'audio.equalizer.bands[$index].filterType must be peaking, low_shelf, or high_shelf.',
        );
      }
      final frequency = _number(bandMap['frequencyHz']);
      final gain = _number(bandMap['gainDb']);
      final q = _number(bandMap['q']);
      final band =
          type == null || frequency == null || gain == null || q == null
          ? null
          : EqBandConfiguration(
              filterType: type,
              frequencyHz: frequency,
              gainDb: gain,
              q: q,
            );
      final error = band?.validate();
      if (band == null || error != null) {
        errors.add(
          'audio.equalizer.bands[$index]: ${error ?? 'invalid numeric field'}.',
        );
      } else {
        bands.add(band);
      }
    }
    if (errors.isNotEmpty || preamp == null) {
      return null;
    }
    return PresetAudio(
      preampDb: preamp,
      bands: List<EqBandConfiguration>.unmodifiable(bands),
    );
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    return value;
  }

  static String? _string(Object? value) => value is String ? value : null;

  static String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }
    return _string(value);
  }

  static double? _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static int? _integer(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static bool _isSemver(String value) {
    final parts = value.split('.');
    if (parts.length != 3) {
      return false;
    }
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(part)) {
        return false;
      }
    }
    return true;
  }

  static void _rejectUnknown(
    Map<String, Object?> map,
    Set<String> allowed,
    String prefix,
    List<String> errors,
  ) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        errors.add(
          '${prefix.isEmpty ? '' : prefix}$key is not a recognized field.',
        );
      }
    }
  }
}

extension on String {
  int get characters => runes.length;
}
