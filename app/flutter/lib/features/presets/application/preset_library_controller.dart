import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/app_setting_keys.dart';
import '../../../core/database/database_exception.dart';
import '../../../features/backup/data/backup_service.dart';
import '../../../features/backup/domain/backup_package.dart';
import '../../../features/presets/data/preset_exchange_service.dart';
import '../../../features/presets/data/preset_repository.dart';
import '../../../features/presets/domain/preset_entry.dart';
import '../../../features/presets/domain/preset_source.dart';
import '../../../features/settings/data/settings_repository.dart';
import '../../../platform/files/preset_file_gateway.dart';
import '../../../shared/models/equalizer_configuration.dart';
import '../../../shared/models/preset_document.dart';

/// State of a multi-step import preview.
final class ImportPreviewState {
  ImportPreviewState({
    required this.candidate,
    required this.selectedResolution,
  });

  final PresetImportCandidate candidate;

  /// The resolution the user has currently selected in the preview dialog.
  DuplicateResolution selectedResolution;
}

/// Application-layer controller for the local preset library.
///
/// This replaces the Phase 1 in-memory implementation. It is backed by a
/// [PresetRepository] for persistence and a [PresetExchangeService] for
/// validation and import/export. All public methods are async and safe to call
/// from widgets.
final class PresetLibraryController extends ChangeNotifier {
  PresetLibraryController({
    required PresetRepository repository,
    required PresetExchangeService exchange,
    required SettingsRepository settings,
    PresetFileGateway? fileGateway,
    required BackupService backup,
  }) : _presetRepository = repository,
       _presetExchange = exchange,
       _settingsRepository = settings,
       _fileGateway = fileGateway ?? const NativePresetFileGateway(),
       _backupService = backup;

  final PresetRepository _presetRepository;
  final PresetExchangeService _presetExchange;
  final SettingsRepository _settingsRepository;
  final PresetFileGateway _fileGateway;
  final BackupService _backupService;

  List<PresetEntry> _entries = <PresetEntry>[];
  String? _activeId;
  bool _loading = false;
  Object? _error;

  List<PresetEntry> get entries => List<PresetEntry>.unmodifiable(_entries);
  String? get activeId => _activeId;
  bool get isLoading => _loading;
  Object? get error => _error;

  PresetEntry? get active {
    if (_activeId == null) {
      return null;
    }
    for (final entry in _entries) {
      if (entry.id == _activeId) {
        return entry;
      }
    }
    return null;
  }

  List<String> get categories {
    final values = <String>{};
    for (final entry in _entries) {
      values.add(entry.category);
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  /// Load presets from the repository and resolve the active preset.
  ///
  /// Called during app startup. Built-ins are seeded idempotently first.
  Future<void> load() async {
    _setLoading(true);
    try {
      await _presetRepository.ensureBuiltinsSeeded();
      _entries = await _presetRepository.getAll();
      _activeId = await _presetRepository.getActivePresetId();
      if (_activeId != null && !await _presetRepository.exists(_activeId!)) {
        _activeId = null;
      }
      if (_activeId == null && _entries.isNotEmpty) {
        _activeId = _entries.first.id;
        await _presetRepository.setActivePreset(_activeId);
      }
      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      _setLoading(false);
    }
  }

  /// Pull the persisted active preset id from the repository.
  Future<void> refreshActivePreset() async {
    try {
      _activeId = await _presetRepository.getActivePresetId();
      notifyListeners();
    } on UamDataException catch (_) {
      // Keep existing UI state if the database is transiently unavailable.
    }
  }

  List<PresetEntry> filtered({
    String query = '',
    PresetLibrarySection section = PresetLibrarySection.all,
    String? category,
  }) {
    final normalized = query.trim().toLowerCase();
    return _entries
        .where((entry) {
          if (section == PresetLibrarySection.favorites && !entry.isFavorite) {
            return false;
          }
          if (section == PresetLibrarySection.created && entry.isBuiltIn) {
            return false;
          }
          if (category != null &&
              category != 'All' &&
              entry.category != category) {
            return false;
          }
          if (normalized.isEmpty) {
            return true;
          }
          final metadata = entry.document.metadata;
          return entry.name.toLowerCase().contains(normalized) ||
              (metadata.description?.toLowerCase().contains(normalized) ??
                  false) ||
              (metadata.author?.toLowerCase().contains(normalized) ?? false) ||
              metadata.tags.any(
                (tag) => tag.toLowerCase().contains(normalized),
              );
        })
        .toList(growable: false);
  }

  /// Persist the active preset id.
  Future<bool> activate(String id) async {
    if (!await _presetRepository.exists(id)) {
      return false;
    }
    await _presetRepository.setActivePreset(id);
    _activeId = id;
    notifyListeners();
    return true;
  }

  /// Toggle favorite and refresh the in-memory entry.
  ///
  /// The repository is updated first: the UI never shows a favorite state that
  /// was not persisted. On failure the previous entry is restored and the error
  /// is recorded for the page to report.
  Future<PresetEntry?> toggleFavorite(String id) async {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      return null;
    }
    final entry = _entries[index];
    final next = !entry.isFavorite;
    try {
      final persisted = await _presetRepository.setFavorite(id, next);
      if (!persisted) {
        return entry;
      }
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return entry;
    }
    final updated = entry.copyWith(isFavorite: next);
    _entries = List<PresetEntry>.of(_entries)..[index] = updated;
    _error = null;
    notifyListeners();
    return updated;
  }

  /// Create a new user preset.
  ///
  /// [id] may be supplied for deterministic tests; normally leave it null.
  Future<PresetEntry?> addPreset(
    PresetDocument document, {
    String? id,
    bool activate = false,
  }) async {
    try {
      final entry = await _presetRepository.create(
        document,
        id: id,
        source: PresetSource.user,
      );
      _entries = await _presetRepository.getAll();
      if (activate) {
        _activeId = entry.id;
        await _presetRepository.setActivePreset(entry.id);
      }
      notifyListeners();
      return entry;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Import a validated document from a string.
  Future<PresetEntry?> importJson(String source, {bool activate = true}) async {
    final bytes = Uint8List.fromList(utf8.encode(source));
    final result = await _presetExchange.prepareImport(bytes);
    if (!result.isValid || result.candidate == null) {
      _error = result.errors.join('\n');
      notifyListeners();
      return null;
    }
    return importCandidate(result.candidate!, DuplicateResolution.importAsNew);
  }

  /// Persist a prepared import candidate.
  Future<PresetEntry?> importCandidate(
    PresetImportCandidate candidate,
    DuplicateResolution resolution,
  ) async {
    try {
      final entry = await _presetExchange.commitImport(candidate, resolution);
      _entries = await _presetRepository.getAll();
      if (entry != null) {
        _activeId = entry.id;
        await _presetRepository.setActivePreset(entry.id);
      }
      _error = null;
      notifyListeners();
      return entry;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Let the user pick a preset file, validate it, and return a candidate for
  /// confirmation. Returns null when the user cancels the picker.
  Future<PresetImportResult?> pickImport() async {
    final picked = await _fileGateway.pickPresetFile();
    if (picked == null) {
      return null;
    }
    return _presetExchange.prepareImport(picked.bytes);
  }

  /// Validate a pasted `.uam-preset.json` document without writing anything.
  Future<PresetImportResult> prepareImport(String source) {
    final bytes = Uint8List.fromList(utf8.encode(source));
    return _presetExchange.prepareImport(bytes);
  }

  /// Export one preset to a user-chosen file.
  Future<String?> exportPreset(PresetEntry entry) async {
    try {
      final export = _presetExchange.buildExport(entry);
      return _fileGateway.savePresetFile(
        suggestedName: export.fileName,
        bytes: export.utf8Bytes,
      );
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Copy the preset JSON to the clipboard as a convenience fallback.
  String exportPresetToString(PresetEntry entry) =>
      utf8.decode(_presetExchange.buildExport(entry).utf8Bytes);

  /// Create a preset from the current equalizer configuration.
  Future<PresetEntry?> createFromEqualizer({
    required String name,
    required EqualizerConfiguration configuration,
    String? author,
    String? description,
    bool activate = true,
  }) async {
    final document = PresetDocument.fromEqualizer(
      name: name,
      author: author,
      description: description,
      configuration: configuration,
    );
    return addPreset(document, activate: activate);
  }

  /// Delete a user/imported preset. Built-ins are protected.
  Future<bool> removePreset(String id) async {
    final entry = _find(id);
    if (entry == null || entry.isBuiltIn) {
      return false;
    }
    try {
      final removed = await _presetRepository.delete(id);
      if (removed) {
        _entries = await _presetRepository.getAll();
        if (_activeId == id) {
          _activeId = _entries.firstOrNull?.id;
          await _presetRepository.setActivePreset(_activeId);
        }
        notifyListeners();
      }
      return removed;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return false;
    }
  }

  /// Create a backup to a user-chosen file.
  Future<BackupWriteResult?> createBackup(String destinationPath) async {
    try {
      final result = await _backupService.writeBackup(destinationPath);
      _error = null;
      notifyListeners();
      return result;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Ask the user where to save a backup, then write it there.
  ///
  /// Returns null when the user cancels or the write fails.
  Future<BackupWriteResult?> backupToChosenFile() async {
    try {
      final built = await _backupService.buildBytes();
      final path = await _fileGateway.saveBackupFile(
        suggestedName: _backupService.suggestedFileName(),
        bytes: built.bytes,
      );
      if (path == null) {
        return null;
      }
      await _backupService.recordBackup(path, built.bytes.length);
      _error = null;
      notifyListeners();
      return BackupWriteResult(
        path: path,
        bytes: built.bytes.length,
        presetCount: built.package.presets.length,
        checksum: '',
      );
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Ask the user to pick a backup file and validate it for confirmation.
  Future<BackupPackage?> pickAndInspectBackup() async {
    try {
      final picked = await _fileGateway.pickBackupFile();
      if (picked == null) {
        return null;
      }
      final package = BackupCodec.parse(picked.bytes);
      _error = null;
      return package;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Read and validate a backup container for confirmation.
  Future<BackupPackage?> inspectBackup(String path) async {
    try {
      final package = await _backupService.inspectBackup(path);
      _error = null;
      return package;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Restore [package] after explicit user confirmation.
  Future<RestoreReport?> restoreBackup(BackupPackage package) async {
    try {
      final report = await _backupService.restore(package, confirmed: true);
      _entries = await _presetRepository.getAll();
      _activeId = await _presetRepository.getActivePresetId();
      _error = null;
      notifyListeners();
      return report;
    } on UamDataException catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  /// Last backup timestamp and display path from settings, if any.
  Future<(String?, String?)> lastBackupInfo() async {
    final at = await _settingsRepository.get<String>(
      AppSettingKeys.lastBackupAt,
    );
    final path = await _settingsRepository.get<String>(
      AppSettingKeys.lastBackupPath,
    );
    return (at, path);
  }

  PresetEntry? _find(String id) {
    for (final entry in _entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  void _setLoading(bool value) {
    if (_loading == value) {
      return;
    }
    _loading = value;
    notifyListeners();
  }

  /// Clear the last recorded error.
  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    notifyListeners();
  }
}

/// Library tab filters (kept for backward compatibility with the UI).
enum PresetLibrarySection {
  all('All'),
  favorites('Favorites'),
  created('Created by me');

  const PresetLibrarySection(this.label);

  final String label;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
