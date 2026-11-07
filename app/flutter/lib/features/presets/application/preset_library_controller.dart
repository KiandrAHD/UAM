import 'package:flutter/foundation.dart';

import '../../../shared/models/equalizer_configuration.dart';
import '../../../shared/models/preset_document.dart';

/// One preset in the local library.
final class PresetEntry {
  const PresetEntry({
    required this.id,
    required this.document,
    required this.isBuiltIn,
    this.isFavorite = false,
  });

  final String id;
  final PresetDocument document;
  final bool isBuiltIn;
  final bool isFavorite;

  String get name => document.metadata.name;
  String get category => document.metadata.tags.isEmpty
      ? 'Uncategorised'
      : document.metadata.tags.first;

  PresetEntry copyWith({bool? isFavorite}) {
    return PresetEntry(
      id: id,
      document: document,
      isBuiltIn: isBuiltIn,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

/// Library tab filters.
enum PresetLibrarySection {
  all('All'),
  favorites('Favorites'),
  created('Created by me');

  const PresetLibrarySection(this.label);

  final String label;
}

/// Local, in-memory preset library.
///
/// Phase 1 does not include SQLite persistence. Built-in entries mirror the
/// repository's actual `presets/examples/` documents; they are not device data.
final class PresetLibraryController extends ChangeNotifier {
  PresetLibraryController({List<PresetEntry>? initialEntries, String? activeId})
    : _entries = List<PresetEntry>.of(
        initialEntries ?? builtInPresetEntries(),
      ) {
    _activeId = activeId ?? _entries.firstOrNull?.id;
  }

  final List<PresetEntry> _entries;
  String? _activeId;

  List<PresetEntry> get entries => List<PresetEntry>.unmodifiable(_entries);
  String? get activeId => _activeId;
  PresetEntry? get active {
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

  PresetEntry? activate(String id) {
    final entry = _find(id);
    if (entry == null) {
      return null;
    }
    _activeId = id;
    notifyListeners();
    return entry;
  }

  PresetEntry? toggleFavorite(String id) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      return null;
    }
    final updated = _entries[index].copyWith(
      isFavorite: !_entries[index].isFavorite,
    );
    _entries[index] = updated;
    notifyListeners();
    return updated;
  }

  PresetEntry? addPreset(
    PresetDocument document, {
    String? id,
    bool activate = false,
  }) {
    // Re-parse the generated document so the library cannot accept a preset
    // that violates schema version 1.
    if (!PresetCodec.parse(document.toPrettyJson()).isValid) {
      return null;
    }
    final entry = PresetEntry(
      id: id ?? 'user-${DateTime.now().microsecondsSinceEpoch}',
      document: document,
      isBuiltIn: false,
    );
    _entries.add(entry);
    if (activate) {
      _activeId = entry.id;
    }
    notifyListeners();
    return entry;
  }

  PresetEntry? importJson(String source, {bool activate = true}) {
    final result = PresetCodec.parse(source);
    final document = result.preset;
    if (!result.isValid || document == null) {
      return null;
    }
    return addPreset(document, activate: activate);
  }

  PresetEntry? createFromEqualizer({
    required String name,
    required EqualizerConfiguration configuration,
    String? author,
    String? description,
    bool activate = true,
  }) {
    final document = PresetDocument.fromEqualizer(
      name: name,
      author: author,
      description: description,
      configuration: configuration,
    );
    return addPreset(document, activate: activate);
  }

  bool removePreset(String id) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0 || _entries[index].isBuiltIn) {
      return false;
    }
    _entries.removeAt(index);
    if (_activeId == id) {
      _activeId = null;
    }
    notifyListeners();
    return true;
  }

  PresetEntry? _find(String id) {
    for (final entry in _entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }
}

/// Built-in presets copied from the repository's Phase 0 examples.
List<PresetEntry> builtInPresetEntries() {
  return <PresetEntry>[
    PresetEntry(
      id: 'builtin-balanced-warm',
      isBuiltIn: true,
      document: PresetDocument(
        metadata: const PresetMetadata(
          name: 'Balanced Warm',
          author: 'UAM Phase 0 Fixture',
          description:
              'A balanced profile with gentle low-frequency warmth and a soft '
              'treble lift.',
          createdAt: '2026-01-01T00:00:00Z',
          tags: <String>['balanced', 'warm'],
        ),
        compatibility: const PresetCompatibility(),
        audio: PresetAudio(
          preampDb: -2,
          bands: const <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 60,
              gainDb: 2,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 250,
              gainDb: 1,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 1000,
              gainDb: 0,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 4000,
              gainDb: -1,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 10000,
              gainDb: 1.5,
              q: 1,
            ),
          ],
        ),
      ),
    ),
    PresetEntry(
      id: 'builtin-neutral-reference',
      isBuiltIn: true,
      document: PresetDocument(
        metadata: const PresetMetadata(
          name: 'Neutral Reference',
          author: 'UAM Phase 0 Fixture',
          description:
              'Zero preamp and no bands. Useful for verifying that a valid '
              'preset may contain an empty equalizer list.',
          createdAt: '2026-03-01T08:00:00Z',
          tags: <String>['neutral', 'reference'],
        ),
        compatibility: const PresetCompatibility(),
        audio: const PresetAudio(preampDb: 0, bands: <EqBandConfiguration>[]),
      ),
    ),
    PresetEntry(
      id: 'builtin-shelf-bass-boost',
      isBuiltIn: true,
      document: PresetDocument(
        metadata: const PresetMetadata(
          name: 'Shelf Bass Boost',
          author: 'UAM Phase 0 Fixture',
          description:
              'Low-shelf bass lift with a restrained high-shelf cut, used to '
              'exercise both shelving filter shapes.',
          createdAt: '2026-02-14T12:30:00Z',
          tags: <String>['bass', 'shelf'],
        ),
        compatibility: const PresetCompatibility(
          requiredCapabilities: <String>['dsp.eq.peaking', 'dsp.eq.shelving'],
        ),
        audio: PresetAudio(
          preampDb: -4.5,
          bands: const <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.lowShelf,
              frequencyHz: 120,
              gainDb: 6,
              q: 0.707,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.highShelf,
              frequencyHz: 8000,
              gainDb: -2.5,
              q: 0.707,
            ),
          ],
        ),
      ),
    ),
  ];
}

extension on List<PresetEntry> {
  PresetEntry? get firstOrNull => isEmpty ? null : first;
}
