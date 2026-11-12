import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/state/uam_app_controller.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/components/uam_response_graph.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_radii.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../../shared/models/preset_document.dart';
import '../application/preset_library_controller.dart';
import '../data/preset_exchange_service.dart';
import '../domain/preset_entry.dart';
import '../domain/preset_source.dart';

/// Local preset library: browse, filter, preview, import, and export.
///
/// The library is backed by the SQLite repository: built-in presets are seeded
/// once, user and imported presets persist across restarts, favorites and the
/// active preset survive a full application restart. Import validation runs
/// before any database write, so a rejected document never changes stored data.
class PresetsPage extends StatefulWidget {
  const PresetsPage({super.key});

  @override
  State<PresetsPage> createState() => _PresetsPageState();
}

class _PresetsPageState extends State<PresetsPage> {
  final TextEditingController _searchController = TextEditingController();
  PresetLibrarySection _section = PresetLibrarySection.all;
  String _category = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final library = controller.presets;
    final categories = <String>['All', ...library.categories];
    if (!categories.contains(_category)) {
      _category = 'All';
    }
    final entries = library.filtered(
      query: _searchController.text,
      section: _section,
      category: _category,
    );
    return ListView(
      key: const Key('page-presets'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        UamPageHeader(
          eyebrow: 'Local library',
          title: 'Presets',
          description:
              'Browse the persisted local profile library, preview a tuning, '
              'and import or export a portable .uam-preset.json document. '
              'Validation is performed locally against schema version 1 before '
              'anything is written to the database.',
          actions: <Widget>[
            FilledButton.icon(
              onPressed: () => _showImportDialog(context, controller),
              icon: const Icon(Icons.upload_file_outlined, size: 17),
              label: const Text('Import preset'),
            ),
          ],
        ),
        const SizedBox(height: UamSpacing.lg),
        _PresetToolbar(
          searchController: _searchController,
          section: _section,
          category: _category,
          categories: categories,
          onSearchChanged: () => setState(() {}),
          onSectionChanged: (section) => setState(() => _section = section),
          onCategoryChanged: (category) => setState(() => _category = category),
        ),
        const SizedBox(height: UamSpacing.xl),
        if (library.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: UamSpacing.lg),
            child: UamNotice(
              tone: UamStatusTone.error,
              title: 'The preset library could not be updated',
              message: _describeError(library.error!),
            ),
          ),
        if (library.isLoading && library.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: UamSpacing.empty),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (entries.isEmpty)
          UamEmptyState(
            icon: Icons.library_music_outlined,
            title: 'No presets match',
            description:
                'No preset matches the current search, tab, and category '
                'filters. Clear the filters or import a portable preset.',
            action: OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _section = PresetLibrarySection.all;
                  _category = 'All';
                });
              },
              icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
              label: const Text('Clear filters'),
            ),
          )
        else
          UamResponsiveGrid(
            minTileWidth: 300,
            children: <Widget>[
              for (final entry in entries)
                _PresetCard(
                  entry: entry,
                  active: library.activeId == entry.id,
                  onPreview: () => controller.activatePreset(entry.id),
                  onFavorite: () => library.toggleFavorite(entry.id),
                  onExport: () => _exportPreset(context, controller, entry),
                  onCopy: () => _copyPreset(context, controller, entry),
                  onDelete: entry.isBuiltIn
                      ? null
                      : () => _confirmDelete(context, controller, entry),
                ),
            ],
          ),
        const SizedBox(height: UamSpacing.xl),
        const UamNotice(
          tone: UamStatusTone.info,
          title: 'Persisted locally',
          message:
              'UAM presets use the .uam-preset.json format, schema version 1. '
              'The library, favorites, and the active preset are stored in the '
              'local SQLite database and survive a restart. Built-in entries '
              'are seeded once and cannot be deleted or overwritten.',
        ),
      ],
    );
  }

  Future<void> _exportPreset(
    BuildContext context,
    UamAppController controller,
    PresetEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await controller.presets.exportPreset(entry);
    if (path == null) {
      // The user cancelled the save dialog, or the write failed and the
      // controller recorded an error the page already surfaces.
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '"${entry.name}" exported as ${p.basename(path)} '
          '(.uam-preset.json).',
        ),
      ),
    );
  }

  Future<void> _copyPreset(
    BuildContext context,
    UamAppController controller,
    PresetEntry entry,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: controller.presets.exportPresetToString(entry)),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${entry.name}" copied as .uam-preset.json.')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UamAppController controller,
    PresetEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete preset'),
        content: Text(
          '"${entry.name}" will be removed from the persisted library. This '
          'cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) {
      return;
    }
    final removed = await controller.presets.removePreset(entry.id);
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (removed) {
      messenger.showSnackBar(
        SnackBar(content: Text('"${entry.name}" was deleted.')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '"${entry.name}" was not deleted. Built-in presets are protected.',
          ),
        ),
      );
    }
  }
}

String _describeError(Object error) {
  if (error is Exception) {
    final text = error.toString();
    final colon = text.indexOf(': ');
    return colon >= 0 ? text.substring(colon + 2) : text;
  }
  return error.toString();
}

class _PresetToolbar extends StatelessWidget {
  const _PresetToolbar({
    required this.searchController,
    required this.section,
    required this.category,
    required this.categories,
    required this.onSearchChanged,
    required this.onSectionChanged,
    required this.onCategoryChanged,
  });

  final TextEditingController searchController;
  final PresetLibrarySection section;
  final String category;
  final List<String> categories;
  final VoidCallback onSearchChanged;
  final ValueChanged<PresetLibrarySection> onSectionChanged;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return UamCard(
      padding: const EdgeInsets.all(UamSpacing.lg),
      child: Wrap(
        spacing: UamSpacing.md,
        runSpacing: UamSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 260,
            child: TextField(
              key: const Key('presets-search'),
              controller: searchController,
              onChanged: (_) => onSearchChanged(),
              decoration: InputDecoration(
                hintText: 'Search presets',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged();
                        },
                      ),
              ),
            ),
          ),
          for (final value in PresetLibrarySection.values)
            _ToolbarChip(
              label: value.label,
              selected: section == value,
              onTap: () => onSectionChanged(value),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: UamSpacing.md),
            decoration: BoxDecoration(
              color: colors.insetPanel,
              borderRadius: BorderRadius.circular(UamRadii.control),
              border: Border.all(color: colors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: category,
                dropdownColor: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(UamRadii.control),
                icon: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: colors.textTertiary,
                ),
                items: <DropdownMenuItem<String>>[
                  for (final value in categories)
                    DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value == 'All' ? 'All categories' : value,
                        style: UamTypography.navigation.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onCategoryChanged(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Material(
      color: selected ? colors.infoOverlay : colors.surfaceSecondary,
      borderRadius: BorderRadius.circular(UamRadii.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UamRadii.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: UamSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(UamRadii.control),
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          child: Text(
            label,
            style: UamTypography.navigation.copyWith(
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.entry,
    required this.active,
    required this.onPreview,
    required this.onFavorite,
    required this.onExport,
    required this.onCopy,
    required this.onDelete,
  });

  final PresetEntry entry;
  final bool active;
  final VoidCallback onPreview;
  final VoidCallback onFavorite;
  final VoidCallback onExport;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final document = entry.document;
    final metadata = document.metadata;
    return UamCard(
      selected: active,
      semanticLabel: '${entry.name} preset${active ? ', active' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CapabilityBadge(label: entry.category, tone: UamStatusTone.info),
              const SizedBox(width: UamSpacing.sm),
              if (entry.isBuiltIn)
                const CapabilityBadge(
                  label: 'Built-in',
                  tone: UamStatusTone.muted,
                )
              else if (entry.source == PresetSource.imported)
                const CapabilityBadge(
                  label: 'Imported',
                  tone: UamStatusTone.planned,
                ),
              const Spacer(),
              if (active)
                const CapabilityBadge(
                  label: 'Active',
                  tone: UamStatusTone.success,
                ),
            ],
          ),
          const SizedBox(height: UamSpacing.md),
          UamResponseGraph(
            bands: document.audio.bands,
            preampDb: document.audio.preampDb,
            bypassed: false,
            height: 96,
            showLabels: false,
          ),
          const SizedBox(height: UamSpacing.md),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UamTypography.cardTitle.copyWith(color: colors.textPrimary),
          ),
          if (metadata.description != null) ...<Widget>[
            const SizedBox(height: UamSpacing.xs),
            Text(
              metadata.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: UamTypography.description.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: UamSpacing.md),
          Text(
            '${metadata.author ?? 'Unknown author'} · '
            '${document.bandCount} bands · preamp '
            '${document.audio.preampDb.toStringAsFixed(1)} dB',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: UamSpacing.lg),
          Wrap(
            spacing: UamSpacing.xs,
            runSpacing: UamSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: active ? null : onPreview,
                icon: const Icon(Icons.play_arrow_rounded, size: 17),
                label: Text(active ? 'Active' : 'Preview'),
              ),
              UamIconButton(
                icon: entry.isFavorite ? Icons.favorite : Icons.favorite_border,
                label: entry.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                selected: entry.isFavorite,
                onPressed: onFavorite,
              ),
              UamIconButton(
                icon: Icons.save_alt_outlined,
                label: 'Export to .uam-preset.json',
                onPressed: onExport,
              ),
              UamIconButton(
                icon: Icons.content_copy_outlined,
                label: 'Copy preset JSON',
                onPressed: onCopy,
              ),
              if (onDelete != null)
                UamIconButton(
                  icon: Icons.delete_outline,
                  label: 'Delete preset',
                  onPressed: onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showImportDialog(
  BuildContext context,
  UamAppController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ImportPresetDialog(controller: controller),
  );
}

/// Multi-step import: pick/paste, validate, preview, resolve duplicates,
/// confirm. Nothing is written until the user confirms.
class _ImportPresetDialog extends StatefulWidget {
  const _ImportPresetDialog({required this.controller});

  final UamAppController controller;

  @override
  State<_ImportPresetDialog> createState() => _ImportPresetDialogState();
}

class _ImportPresetDialogState extends State<_ImportPresetDialog> {
  final TextEditingController _textController = TextEditingController();
  PresetImportResult? _result;
  DuplicateResolution _resolution = DuplicateResolution.importAsNew;
  bool _busy = false;
  String? _sourceName;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _busy = true);
    try {
      final result = await widget.controller.presets.pickImport();
      if (!mounted) {
        return;
      }
      if (result == null) {
        // The user cancelled the picker: leave the dialog untouched.
        return;
      }
      setState(() {
        _result = result;
        _sourceName = result.isValid ? 'selected file' : null;
        _resolution = _defaultResolution(result.candidate);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _validatePasted() async {
    setState(() => _busy = true);
    try {
      final result = await widget.controller.presets.prepareImport(
        _textController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _sourceName = 'pasted document';
        _resolution = _defaultResolution(result.candidate);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  DuplicateResolution _defaultResolution(PresetImportCandidate? candidate) {
    if (candidate == null) {
      return DuplicateResolution.importAsNew;
    }
    return switch (candidate.conflict) {
      ImportConflict.builtInCollision => DuplicateResolution.keepExisting,
      _ => DuplicateResolution.importAsNew,
    };
  }

  Future<void> _commit() async {
    final candidate = _result?.candidate;
    if (candidate == null) {
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final entry = await widget.controller.presets.importCandidate(
      candidate,
      _resolution,
    );
    if (!mounted) {
      return;
    }
    navigator.pop();
    if (entry != null) {
      await widget.controller.activatePreset(entry.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${entry.name}" was imported to the local library.'),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('The existing preset was kept.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final candidate = result?.candidate;
    final canImport = result?.isValid ?? false;
    return AlertDialog(
      title: const Text('Import preset'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Choose a .uam-preset.json file or paste a document. UAM '
                'validates the schema, numeric boundaries, and filter '
                'definitions locally before anything is stored.',
                style: UamTypography.description.copyWith(
                  color: context.uamColors.textSecondary,
                ),
              ),
              const SizedBox(height: UamSpacing.lg),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('preset-import-pick'),
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 17),
                    label: const Text('Choose file'),
                  ),
                  const SizedBox(width: UamSpacing.md),
                  if (_sourceName != null)
                    Text(
                      'Source: $_sourceName',
                      style: UamTypography.micro.copyWith(
                        color: context.uamColors.textTertiary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: UamSpacing.lg),
              TextField(
                key: const Key('preset-import-field'),
                controller: _textController,
                maxLines: 10,
                minLines: 6,
                style: UamTypography.monospace,
                decoration: const InputDecoration(
                  hintText: '{ "format": "uam-preset", ... }',
                ),
                onChanged: (_) {
                  if (_result != null) {
                    setState(() {
                      _result = null;
                      _sourceName = null;
                    });
                  }
                },
              ),
              if (result != null) ...<Widget>[
                const SizedBox(height: UamSpacing.lg),
                _ImportResultPanel(result: result),
              ],
              if (candidate != null && candidate.needsDecision) ...<Widget>[
                const SizedBox(height: UamSpacing.lg),
                _DuplicateResolutionSelector(
                  candidate: candidate,
                  selected: _resolution,
                  onChanged: (value) => setState(() => _resolution = value),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _validatePasted,
          child: const Text('Validate'),
        ),
        FilledButton(
          onPressed: (canImport && !_busy) ? _commit : null,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _ImportResultPanel extends StatelessWidget {
  const _ImportResultPanel({required this.result});

  final PresetImportResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    if (result.isValid) {
      final candidate = result.candidate!;
      final preset = candidate.document;
      final warnings = candidate.compatibilityWarnings;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamNotice(
            tone: UamStatusTone.success,
            title: 'Valid preset',
            message:
                '"${preset.metadata.name}" is well-formed: '
                '${preset.bandCount} bands, preamp '
                '${preset.audio.preampDb.toStringAsFixed(1)} dB, schema version '
                '${PresetDocument.schemaVersion}.',
          ),
          for (final warning in warnings) ...<Widget>[
            const SizedBox(height: UamSpacing.sm),
            UamNotice(tone: UamStatusTone.warning, message: warning),
          ],
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(UamSpacing.lg),
      decoration: BoxDecoration(
        color: colors.errorOverlay,
        borderRadius: BorderRadius.circular(UamRadii.notice),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Validation failed',
            style: UamTypography.cardTitle.copyWith(color: colors.error),
          ),
          const SizedBox(height: UamSpacing.sm),
          for (final error in result.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: UamSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.circle, size: 5, color: colors.error),
                  const SizedBox(width: UamSpacing.md),
                  Expanded(
                    child: Text(
                      error,
                      style: UamTypography.micro.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DuplicateResolutionSelector extends StatelessWidget {
  const _DuplicateResolutionSelector({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });

  final PresetImportCandidate candidate;
  final DuplicateResolution selected;
  final ValueChanged<DuplicateResolution> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final conflict = candidate.conflict;
    final existingName = candidate.existingName ?? candidate.existingId ?? '';
    final canReplace =
        conflict == ImportConflict.identifierInUse ||
        conflict == ImportConflict.identicalContent;
    return UamCard(
      padding: const EdgeInsets.all(UamSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'This document conflicts with an existing preset',
            style: UamTypography.cardTitle.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: UamSpacing.xs),
          Text(
            switch (conflict) {
              ImportConflict.identifierInUse =>
                'Another preset already uses this identifier ("$existingName").',
              ImportConflict.identicalContent =>
                'An identical preset already exists ("$existingName").',
              ImportConflict.nameInUse =>
                'Another preset already uses the name "$existingName".',
              ImportConflict.builtInCollision =>
                'The name resolves to the reserved built-in "$existingName". '
                    'Built-in presets can never be replaced.',
              ImportConflict.none => 'No conflict.',
            },
            style: UamTypography.description.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: UamSpacing.md),
          RadioGroup<DuplicateResolution>(
            groupValue: selected,
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
            child: Column(
              children: <Widget>[
                const RadioListTile<DuplicateResolution>(
                  value: DuplicateResolution.keepExisting,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Keep the existing preset'),
                ),
                const RadioListTile<DuplicateResolution>(
                  value: DuplicateResolution.importAsNew,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Import as a new preset with a new identifier'),
                ),
                if (canReplace)
                  const RadioListTile<DuplicateResolution>(
                    value: DuplicateResolution.replaceExisting,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Replace the existing user preset'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
