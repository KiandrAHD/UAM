import 'dart:convert';
import 'dart:typed_data';

import '../../../core/database/database_exception.dart';
import '../../../shared/models/equalizer_configuration.dart';
import '../../../shared/models/preset_document.dart';
import '../domain/preset_entry.dart';
import '../domain/preset_source.dart';
import 'preset_repository.dart';

/// How the user wants an import conflict resolved.
enum DuplicateResolution {
  /// Do nothing; the existing preset stays as it is.
  keepExisting,

  /// Overwrite an existing user-created or imported preset.
  replaceExisting,

  /// Store the document under a freshly generated identifier.
  importAsNew,
}

/// Why a prepared import needs a decision before it can be written.
enum ImportConflict {
  /// No conflict: the identifier is free.
  none,

  /// The document identifier already exists in the library.
  identifierInUse,

  /// A different preset already carries the same name.
  nameInUse,

  /// An identical document already exists under a different identifier.
  identicalContent,

  /// The document carries a reserved built-in identifier.
  builtInCollision,
}

/// A fully validated import awaiting a duplicate decision.
final class PresetImportCandidate {
  const PresetImportCandidate({
    required this.document,
    required this.conflict,
    this.existingId,
    this.existingName,
  });

  final PresetDocument document;
  final ImportConflict conflict;

  /// Identifier of the conflicting preset, when any.
  final String? existingId;

  /// Display name of the conflicting preset, when any.
  final String? existingName;

  bool get needsDecision => conflict != ImportConflict.none;

  /// Schema-valid but capability/page differences the user should see.
  ///
  /// These are exported for the preview UI. They are intentionally computed
  /// from the document alone: no device has been detected, so UAM never claims
  /// device compatibility, only whether the document itself is well formed.
  List<String> get compatibilityWarnings => _compatibilityWarnings(document);

  static List<String> _compatibilityWarnings(PresetDocument document) {
    final warnings = <String>[];
    if (document.compatibility.requiredCapabilities.isNotEmpty) {
      warnings.add(
        'Requires capabilities: '
        '${document.compatibility.requiredCapabilities.join(', ')}. '
        'No device capability check is performed during import.',
      );
    }
    final shelving = document.audio.bands
        .where((band) => band.filterType != EqFilterType.peaking)
        .length;
    if (shelving > 0) {
      warnings.add(
        'The ten-band graphic editor maps shelving bands onto the nearest '
        'peaking band; the portable document keeps the original filters.',
      );
    }
    if (document.bandCount > EqConstraints.graphicFrequenciesHz.length) {
      warnings.add(
        'The document has ${document.bandCount} bands; the graphic editor '
        'displays ten.',
      );
    }
    return List<String>.unmodifiable(warnings);
  }
}

/// Outcome of preparing an import. Either a candidate or a list of errors.
final class PresetImportResult {
  const PresetImportResult._({this.candidate, required this.errors});

  factory PresetImportResult.invalid(List<String> errors) =>
      PresetImportResult._(errors: List<String>.unmodifiable(errors));

  factory PresetImportResult.ready(PresetImportCandidate candidate) =>
      PresetImportResult._(candidate: candidate, errors: const <String>[]);

  final PresetImportCandidate? candidate;
  final List<String> errors;

  bool get isValid => errors.isEmpty && candidate != null;
}

/// Portable `.uam-preset.json` file bytes ready to be written.
final class PresetFileExport {
  const PresetFileExport({required this.fileName, required this.utf8Bytes});

  /// Suggested file name ending in `.uam-preset.json`.
  final String fileName;

  /// UTF-8 encoded validated preset document.
  final Uint8List utf8Bytes;

  String get mimeType => 'application/json';
}

/// Validates and materializes portable preset imports and exports.
///
/// Validation always runs before any database write: a rejected import leaves
/// the library untouched.
final class PresetExchangeService {
  PresetExchangeService({required this.repository, this.maxImportBytes});

  final PresetRepository repository;

  /// Defaults to the schema contract limit (256 KiB).
  final int? maxImportBytes;

  int get _limit => maxImportBytes ?? PresetDocument.maxBytes;

  /// Build deterministic, pretty-printed export bytes for [entry].
  PresetFileExport buildExport(PresetEntry entry) {
    final document = entry.document;
    final text = const JsonEncoder.withIndent('  ').convert(document.toJson());
    return PresetFileExport(
      fileName: _fileNameFor(entry.name),
      utf8Bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }

  /// Parse and validate import [bytes] without touching the database writes.
  ///
  /// Duplicate detection performs read-only repository lookups.
  Future<PresetImportResult> prepareImport(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return PresetImportResult.invalid(const <String>[
        'The file is empty. Select a non-empty .uam-preset.json document.',
      ]);
    }
    if (bytes.length > _limit) {
      return PresetImportResult.invalid(<String>[
        'The file is ${_formatBytes(bytes.length)}, '
            'above the ${_formatBytes(_limit)} import limit.',
      ]);
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return PresetImportResult.invalid(const <String>[
        'The file is not valid UTF-8 text.',
      ]);
    }
    if (text.trim().isEmpty) {
      return PresetImportResult.invalid(const <String>[
        'The file contains no JSON content.',
      ]);
    }
    final parsed = PresetCodec.parse(text);
    if (!parsed.isValid || parsed.preset == null) {
      return PresetImportResult.invalid(parsed.errors);
    }
    final document = parsed.preset!;
    final id = await _resolveConflicts(document);
    return PresetImportResult.ready(
      PresetImportCandidate(
        document: document,
        conflict: id.conflict,
        existingId: id.existingId,
        existingName: id.existingName,
      ),
    );
  }

  /// Apply a user decision and persist the import.
  ///
  /// Returns the stored entry, or null when the user chose [keepExisting].
  Future<PresetEntry?> commitImport(
    PresetImportCandidate candidate,
    DuplicateResolution resolution,
  ) async {
    final conflict = candidate.conflict;
    switch (resolution) {
      case DuplicateResolution.keepExisting:
        // "Keep existing" never writes a new row, so callers receive null and
        // report that nothing was imported.
        return null;
      case DuplicateResolution.replaceExisting:
        if (candidate.existingId == null) {
          throw const UamDataException(
            UamDataErrorCode.constraintViolation,
            'There is no existing preset to replace.',
          );
        }
        if (conflict == ImportConflict.builtInCollision) {
          throw const UamDataException(
            UamDataErrorCode.constraintViolation,
            'Built-in presets cannot be replaced.',
          );
        }
        return repository.update(candidate.existingId!, candidate.document);
      case DuplicateResolution.importAsNew:
        return repository.create(
          candidate.document,
          source: PresetSource.imported,
        );
    }
  }

  Future<({ImportConflict conflict, String? existingId, String? existingName})>
  _resolveConflicts(PresetDocument document) async {
    final id = document.metadata.name.toLowerCase();
    // Reserved built-in identifiers collide with imported documents that use
    // the same explicit id; imports never carry explicit ids, so the reserved
    // prefix is the collision signal.
    const builtInPrefix = 'builtin-';

    final sameContent = await repository.search(document.metadata.name);
    for (final entry in sameContent) {
      if (_isIdenticalContent(entry.document, document)) {
        // A built-in match is surfaced as a built-in collision so the UI can
        // never offer to replace it.
        return (
          conflict: entry.isBuiltIn
              ? ImportConflict.builtInCollision
              : ImportConflict.identicalContent,
          existingId: entry.id,
          existingName: entry.name,
        );
      }
    }

    if (document.metadata.name.trim().toLowerCase().startsWith(builtInPrefix) ||
        id.startsWith(builtInPrefix)) {
      // The name mimics a reserved identifier; treat as a name collision with
      // the built-in namespace but do not block the import.
      final builtin = await repository.search(document.metadata.name);
      if (builtin.any((entry) => entry.isBuiltIn)) {
        final match = builtin.firstWhere((entry) => entry.isBuiltIn);
        return (
          conflict: ImportConflict.builtInCollision,
          existingId: match.id,
          existingName: match.name,
        );
      }
    }

    if (await repository.nameExists(document.metadata.name)) {
      final rows = await repository.search(document.metadata.name);
      final match = rows.firstOrNull;
      return (
        conflict: ImportConflict.nameInUse,
        existingId: match?.id,
        existingName: match?.name,
      );
    }
    return (
      conflict: ImportConflict.none,
      existingId: null,
      existingName: null,
    );
  }

  bool _isIdenticalContent(PresetDocument a, PresetDocument b) {
    if (a.audio.preampDb != b.audio.preampDb ||
        a.audio.bands.length != b.audio.bands.length) {
      return false;
    }
    for (var index = 0; index < a.audio.bands.length; index += 1) {
      if (a.audio.bands[index] != b.audio.bands[index]) {
        return false;
      }
    }
    return a.metadata.name.toLowerCase() == b.metadata.name.toLowerCase();
  }

  String _fileNameFor(String name) {
    final safe = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final base = safe.isEmpty ? 'preset' : safe;
    return '$base.uam-preset.json';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
