import 'package:flutter/material.dart';

import '../../../app/state/uam_app_controller.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/components/uam_response_graph.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_breakpoints.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_radii.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../../shared/models/equalizer_configuration.dart';

/// Ten-band equalizer configuration editor.
///
/// This page edits desired configuration. It does not claim active DSP
/// processing and does not call the Rust audio path.
class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final configuration = controller.equalizer.configuration;
    return ListView(
      key: const Key('page-equalizer'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        const UamPageHeader(
          eyebrow: 'Sound shaping',
          title: 'Equalizer',
          description:
              'Shape a ten-band configuration with validated preamp and gain '
              'bounds. The response graph reflects the configuration; no live '
              'audio stream is claimed.',
        ),
        const SizedBox(height: UamSpacing.lg),
        const UamNotice(
          tone: UamStatusTone.info,
          title: 'Configuration only',
          message:
              'Sliders update the desired DSP configuration and the calculated '
              'response preview. Phase 1 does not attach this configuration to '
              'system or app-owned audio.',
        ),
        const SizedBox(height: UamSpacing.xl),
        _PresetToolbar(controller: controller),
        const SizedBox(height: UamSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 1000;
            final workspace = _EqualizerWorkspace(
              controller: controller,
              configuration: configuration,
            );
            final rail = _EqualizerRail(controller: controller);
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  workspace,
                  const SizedBox(height: UamSpacing.xl),
                  rail,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: workspace),
                const SizedBox(width: UamSpacing.xl),
                SizedBox(width: UamBreakpoints.equalizerRail, child: rail),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PresetToolbar extends StatelessWidget {
  const _PresetToolbar({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final entries = controller.presets.entries;
    final activeId = controller.presets.activeId;
    final bypassed = controller.equalizer.configuration.bypassed;
    return UamCard(
      padding: const EdgeInsets.all(UamSpacing.lg),
      child: Wrap(
        spacing: UamSpacing.md,
        runSpacing: UamSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: UamSpacing.lg),
              decoration: BoxDecoration(
                color: colors.insetPanel,
                borderRadius: BorderRadius.circular(UamRadii.control),
                border: Border.all(color: colors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: activeId,
                  isExpanded: true,
                  dropdownColor: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(UamRadii.control),
                  icon: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                  hint: Text(
                    'Select preset',
                    style: UamTypography.navigation.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final entry in entries)
                      DropdownMenuItem<String>(
                        value: entry.id,
                        child: Text(
                          entry.name,
                          overflow: TextOverflow.ellipsis,
                          style: UamTypography.navigation.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      controller.activatePreset(value);
                    }
                  },
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: controller.equalizer.reset,
            icon: const Icon(Icons.restart_alt, size: 17),
            label: const Text('Reset'),
          ),
          OutlinedButton.icon(
            onPressed: () => _showSaveDialog(context, controller),
            icon: const Icon(Icons.save_outlined, size: 17),
            label: const Text('Save as preset'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Switch(
                value: bypassed,
                onChanged: controller.equalizer.setBypassed,
              ),
              const SizedBox(width: UamSpacing.xs),
              Text(
                bypassed ? 'Bypassed' : 'Active',
                style: UamTypography.navigation.copyWith(
                  color: bypassed ? colors.textTertiary : colors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EqualizerWorkspace extends StatelessWidget {
  const _EqualizerWorkspace({
    required this.controller,
    required this.configuration,
  });

  final UamAppController controller;
  final EqualizerConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= UamBreakpoints.compact;
    final mobile = width <= UamBreakpoints.mobile;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamSectionHeader(
            title: 'Frequency response',
            subtitle: configuration.bypassed
                ? 'Bypass enabled; response is flat'
                : 'Calculated from ten peaking bands',
            trailing: CapabilityBadge(
              label: configuration.bypassed ? 'Bypassed' : 'Desired config',
              tone: configuration.bypassed
                  ? UamStatusTone.muted
                  : UamStatusTone.info,
            ),
          ),
          const SizedBox(height: UamSpacing.lg),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: configuration.bypassed ? 0.55 : 1,
            child: UamResponseGraph(
              bands: configuration.bands,
              preampDb: configuration.preampDb,
              bypassed: configuration.bypassed,
              height: mobile ? 150 : 210,
            ),
          ),
          const SizedBox(height: UamSpacing.lg),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: UamSpacing.lg),
          Text(
            'GAIN',
            style: UamTypography.technicalLabel.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: UamSpacing.md),
          _BandControls(
            controller: controller,
            configuration: configuration,
            compact: compact,
          ),
          const SizedBox(height: UamSpacing.md),
          Text(
            compact
                ? 'Scroll horizontally to reach every band. '
                      'Gain labels are hidden at compact width.'
                : 'Drag a band to change gain. Keyboard focus and arrow keys are '
                      'supported by the underlying slider.',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _BandControls extends StatelessWidget {
  const _BandControls({
    required this.controller,
    required this.configuration,
    required this.compact,
  });

  final UamAppController controller;
  final EqualizerConfiguration configuration;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth < 440
            ? 440.0
            : constraints.maxWidth;
        final itemWidth = totalWidth / configuration.bands.length;
        final content = SizedBox(
          width: totalWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (
                var index = 0;
                index < configuration.bands.length;
                index += 1
              )
                SizedBox(
                  width: itemWidth,
                  child: _VerticalBand(
                    band: configuration.bands[index],
                    index: index,
                    bypassed: configuration.bypassed,
                    showGainLabel: !compact,
                    onChanged: configuration.bypassed
                        ? null
                        : (value) =>
                              controller.equalizer.setBandGain(index, value),
                  ),
                ),
            ],
          ),
        );
        if (constraints.maxWidth < 440) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        }
        return content;
      },
    );
  }
}

class _VerticalBand extends StatelessWidget {
  const _VerticalBand({
    required this.band,
    required this.index,
    required this.bypassed,
    required this.showGainLabel,
    required this.onChanged,
  });

  final EqBandConfiguration band;
  final int index;
  final bool bypassed;
  final bool showGainLabel;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final frequencyLabel = band.frequencyHz >= 1000
        ? '${(band.frequencyHz / 1000).toStringAsFixed(band.frequencyHz % 1000 == 0 ? 0 : 1)}k'
        : band.frequencyHz.toInt().toString();
    return Column(
      children: <Widget>[
        if (showGainLabel)
          Text(
            '${band.gainDb >= 0 ? '+' : ''}${band.gainDb.toStringAsFixed(1)}',
            style: UamTypography.numeric.copyWith(
              color: bypassed ? colors.textTertiary : colors.textPrimary,
              fontSize: 11,
            ),
          ),
        const SizedBox(height: UamSpacing.xs),
        SizedBox(
          height: 170,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: band.gainDb.clamp(
                EqConstraints.editorMinGainDb,
                EqConstraints.editorMaxGainDb,
              ),
              min: EqConstraints.editorMinGainDb,
              max: EqConstraints.editorMaxGainDb,
              divisions:
                  ((EqConstraints.editorMaxGainDb -
                              EqConstraints.editorMinGainDb) /
                          EqConstraints.gainStepDb)
                      .round(),
              label: '${band.gainDb.toStringAsFixed(1)} dB',
              semanticFormatterCallback: (value) =>
                  '$frequencyLabel hertz, ${value.toStringAsFixed(1)} decibels',
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          frequencyLabel,
          style: UamTypography.technicalLabel.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'Hz',
          style: UamTypography.badge.copyWith(
            color: colors.textTertiary,
            fontSize: 7,
          ),
        ),
      ],
    );
  }
}

class _EqualizerRail extends StatelessWidget {
  const _EqualizerRail({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final configuration = controller.equalizer.configuration;
    final suggested = configuration.suggestedPreampDb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UamCard(
          padding: const EdgeInsets.all(UamSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'OUTPUT',
                style: UamTypography.technicalLabel.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: UamSpacing.sm),
              Text(
                'Preamp',
                style: UamTypography.cardTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: UamSpacing.xs),
              Text(
                '${configuration.preampDb.toStringAsFixed(1)} dB',
                style: UamTypography.majorStatus.copyWith(
                  color: colors.accent,
                  fontSize: 26,
                ),
              ),
              Slider(
                value: configuration.preampDb.clamp(
                  EqConstraints.minPreampDb,
                  EqConstraints.maxPreampDb,
                ),
                min: EqConstraints.minPreampDb,
                max: EqConstraints.maxPreampDb,
                divisions: 72,
                label: '${configuration.preampDb.toStringAsFixed(1)} dB',
                semanticFormatterCallback: (value) =>
                    'Preamp ${value.toStringAsFixed(1)} decibels',
                onChanged: controller.equalizer.setPreamp,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '-24 dB',
                    style: UamTypography.badge.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  Text(
                    '+12 dB',
                    style: UamTypography.badge.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: UamSpacing.md),
              UamNotice(
                tone: UamStatusTone.info,
                message:
                    'Suggested headroom: ${suggested.toStringAsFixed(1)} dB '
                    'based on the sum of positive band gain.',
                action: TextButton(
                  onPressed: () => controller.equalizer.setPreamp(suggested),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: UamSpacing.xl),
        UamCard(
          padding: const EdgeInsets.all(UamSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'OUTPUT METER',
                style: UamTypography.technicalLabel.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: UamSpacing.md),
              for (final channel in <String>['LEFT', 'RIGHT']) ...<Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 34,
                      child: Text(
                        channel,
                        style: UamTypography.badge.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.insetPanel,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: UamSpacing.sm),
              ],
              Text(
                'No live meter. Peak monitoring requires an audio stream and is '
                'not implemented in Phase 1.',
                style: UamTypography.micro.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: UamSpacing.xl),
        UamCard(
          padding: const EdgeInsets.all(UamSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'FILTER MODEL',
                style: UamTypography.technicalLabel.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: UamSpacing.md),
              const _FilterRow(
                label: 'Peaking',
                detail: 'Ten editable bands',
                badge: 'Active',
                tone: UamStatusTone.success,
              ),
              const _FilterRow(
                label: 'Low shelf',
                detail: 'Supported by the Rust DSP core',
                badge: 'Preset only',
                tone: UamStatusTone.info,
              ),
              const _FilterRow(
                label: 'High shelf',
                detail: 'Supported by the Rust DSP core',
                badge: 'Preset only',
                tone: UamStatusTone.info,
              ),
              const _FilterRow(
                label: 'Q control',
                detail: 'Fixed at 1.0 in graphic mode',
                badge: 'Unavailable',
                tone: UamStatusTone.muted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.detail,
    required this.badge,
    required this.tone,
  });

  final String label;
  final String detail;
  final String badge;
  final UamStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: UamSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: UamTypography.navigation.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  detail,
                  style: UamTypography.micro.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          CapabilityBadge(label: badge, tone: tone),
        ],
      ),
    );
  }
}

Future<void> _showSaveDialog(
  BuildContext context,
  UamAppController controller,
) async {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          final name = nameController.text.trim();
          final valid = name.isNotEmpty && name.runes.length <= 80;
          return AlertDialog(
            title: const Text('Save preset'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Preset name',
                      hintText: 'Required',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: UamSpacing.md),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Optional',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () {
                        final entry = controller.presets.createFromEqualizer(
                          name: name,
                          description: descriptionController.text,
                          configuration: controller.equalizer.configuration,
                        );
                        if (entry != null) {
                          controller.activatePreset(entry.id);
                        }
                        Navigator.of(dialogContext).pop();
                      }
                    : null,
                child: const Text('Save preset'),
              ),
            ],
          );
        },
      );
    },
  );
  nameController.dispose();
  descriptionController.dispose();
}
