import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Local preset library: browse, filter, preview, import, and export.
///
/// The library is in-memory in Phase 1. Import validation mirrors the schema
/// contract and is labelled as local; no Rust validation call is claimed.
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
    final categories = <String>['All', ...controller.presets.categories];
    if (!categories.contains(_category)) {
      _category = 'All';
    }
    final entries = controller.presets.filtered(
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
              'Browse the local profile library, preview a tuning, and import a '
              'portable .uam-preset.json document. Validation is performed '
              'locally against schema version 1.',
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
        if (entries.isEmpty)
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
                  active: controller.presets.activeId == entry.id,
                  onPreview: () => controller.activatePreset(entry.id),
                  onFavorite: () => controller.presets.toggleFavorite(entry.id),
                  onExport: () => _exportPreset(context, entry),
                  onDelete: entry.isBuiltIn
                      ? null
                      : () => _confirmDelete(context, controller, entry),
                ),
            ],
          ),
        const SizedBox(height: UamSpacing.xl),
        const UamNotice(
          tone: UamStatusTone.info,
          title: 'Portable format',
          message:
              'UAM presets use the .uam-preset.json format, schema version 1. '
              'Built-in entries mirror the repository reference presets and are '
              'not device data. Persistence arrives in a later phase.',
        ),
      ],
    );
  }

  Future<void> _exportPreset(BuildContext context, PresetEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.document.toPrettyJson()));
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
          '"${entry.name}" will be removed from the local library. This cannot '
          'be undone.',
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
    if (confirmed ?? false) {
      controller.presets.removePreset(entry.id);
    }
  }
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
    required this.onDelete,
  });

  final PresetEntry entry;
  final bool active;
  final VoidCallback onPreview;
  final VoidCallback onFavorite;
  final VoidCallback onExport;
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
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: active ? null : onPreview,
                icon: const Icon(Icons.play_arrow_rounded, size: 17),
                label: Text(active ? 'Active' : 'Preview'),
              ),
              const Spacer(),
              UamIconButton(
                icon: entry.isFavorite ? Icons.favorite : Icons.favorite_border,
                label: entry.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                selected: entry.isFavorite,
                onPressed: onFavorite,
              ),
              UamIconButton(
                icon: Icons.ios_share_outlined,
                label: 'Copy as .uam-preset.json',
                onPressed: onExport,
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

/// Owns the import text controller so it is disposed with the dialog state,
/// after the route has actually left the tree.
class _ImportPresetDialog extends StatefulWidget {
  const _ImportPresetDialog({required this.controller});

  final UamAppController controller;

  @override
  State<_ImportPresetDialog> createState() => _ImportPresetDialogState();
}

class _ImportPresetDialogState extends State<_ImportPresetDialog> {
  final TextEditingController _textController = TextEditingController();
  PresetParseResult? _result;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _import() {
    final entry = widget.controller.presets.importJson(_textController.text);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (entry == null) {
      return;
    }
    widget.controller.activatePreset(entry.id);
    messenger.showSnackBar(
      SnackBar(content: Text('"${entry.name}" imported to the local library.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: const Text('Import preset'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Paste a .uam-preset.json document. Validation runs '
                'locally against schema version 1; the Rust core does not '
                'expose a preset-validation symbol in this build.',
                style: UamTypography.description.copyWith(
                  color: context.uamColors.textSecondary,
                ),
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
                    setState(() => _result = null);
                  }
                },
              ),
              if (result != null) ...<Widget>[
                const SizedBox(height: UamSpacing.lg),
                _ImportResultPanel(result: result),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () =>
              setState(() => _result = PresetCodec.parse(_textController.text)),
          child: const Text('Validate'),
        ),
        FilledButton(
          onPressed: (result?.isValid ?? false) ? _import : null,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _ImportResultPanel extends StatelessWidget {
  const _ImportResultPanel({required this.result});

  final PresetParseResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    if (result.isValid) {
      final preset = result.preset!;
      return UamNotice(
        tone: UamStatusTone.success,
        title: 'Valid preset',
        message:
            '"${preset.metadata.name}" is well-formed: '
            '${preset.bandCount} bands, preamp '
            '${preset.audio.preampDb.toStringAsFixed(1)} dB, schema version '
            '${PresetDocument.schemaVersion}.',
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
