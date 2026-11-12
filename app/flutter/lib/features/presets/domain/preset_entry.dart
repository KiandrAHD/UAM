import '../../../shared/models/preset_document.dart';
import 'preset_source.dart';

/// One preset in the local library, backed by a database row.
final class PresetEntry {
  const PresetEntry({
    required this.id,
    required this.document,
    required this.source,
    this.isFavorite = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Stable identifier. Built-ins use fixed IDs such as
  /// `builtin-balanced-warm`; user presets use `user-<micros>` and imported
  /// presets use `imported-<micros>`.
  final String id;

  final PresetDocument document;

  final PresetSource source;

  final bool isFavorite;

  /// RFC 3339 timestamps stored in the database.
  final String? createdAt;
  final String? updatedAt;

  /// Built-ins cannot be deleted or overwritten.
  bool get isBuiltIn => source == PresetSource.builtin;

  String get name => document.metadata.name;

  /// First metadata tag, or `Uncategorised` when the preset has no tags.
  String get category => document.metadata.tags.isEmpty
      ? 'Uncategorised'
      : document.metadata.tags.first;

  PresetEntry copyWith({
    PresetDocument? document,
    bool? isFavorite,
    String? updatedAt,
  }) {
    return PresetEntry(
      id: id,
      document: document ?? this.document,
      source: source,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
