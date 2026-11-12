import '../../../shared/models/preset_document.dart';
import '../domain/preset_entry.dart';
import '../domain/preset_source.dart';

/// Persistence contract for the local preset library.
///
/// Implementations must validate documents before writing, protect built-in
/// presets, and keep multi-row writes transactional.
abstract interface class PresetRepository {
  /// All presets, built-ins first then user/imported by name.
  Future<List<PresetEntry>> getAll();

  /// One preset by [id], or null.
  Future<PresetEntry?> getById(String id);

  /// Insert a validated [document].
  ///
  /// When [id] is null a stable identifier is generated from [source]. Throws
  /// [UamDataException] with `duplicateId` when the identifier already exists.
  Future<PresetEntry> create(
    PresetDocument document, {
    String? id,
    PresetSource source,
    bool isFavorite,
  });

  /// Replace the document for [id]. Built-in presets cannot be updated.
  Future<PresetEntry> update(String id, PresetDocument document);

  /// Delete a user/imported preset. Returns false for built-ins or missing ids.
  Future<bool> delete(String id);

  /// Set the favorite flag. Returns false when [id] does not exist.
  Future<bool> setFavorite(String id, bool favorite);

  Future<List<PresetEntry>> getFavorites();

  Future<List<PresetEntry>> search(String query);

  Future<List<PresetEntry>> getByCategory(String category);

  /// Persist the active preset id. `null` clears the selection.
  Future<void> setActivePreset(String? presetId);

  /// The persisted active preset id, or null when unset or dangling.
  Future<String?> getActivePresetId();

  Future<bool> exists(String id);

  /// Whether any preset already uses [name] (case-insensitive).
  Future<bool> nameExists(String name, {String? excludeId});

  /// Idempotently insert or update the shipped built-in presets.
  Future<void> ensureBuiltinsSeeded();
}
