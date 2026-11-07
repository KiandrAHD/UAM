import 'package:flutter/material.dart';

import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/components/uam_processing_ring.dart';
import '../../../design_system/components/uam_response_graph.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../../shared/models/capability.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/state/uam_app_controller.dart';

/// Aggregated read-only projection of device, engine, EQ, and preset state.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    return ListView(
      key: const Key('page-dashboard'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        UamPageHeader(
          eyebrow: 'Control center',
          title: 'Audio workspace',
          description:
              'Configure sound, inspect the local engine, and review capability '
              'states. Nothing on this page claims live audio processing.',
          actions: <Widget>[
            if (MediaQuery.sizeOf(context).width > 760)
              UamIconButton(
                icon: Icons.refresh,
                label: 'Refresh engine status',
                onPressed: () {
                  controller.engine.load();
                  controller.devices.refresh();
                },
              ),
            OutlinedButton.icon(
              onPressed: () => _go(context, AppRoutes.presets),
              icon: const Icon(Icons.library_music_outlined, size: 17),
              label: const Text('Preset library'),
            ),
          ],
        ),
        const SizedBox(height: UamSpacing.lg),
        if (controller.devices.selected == null) ...<Widget>[
          UamNotice(
            tone: UamStatusTone.warning,
            title: 'No audio device selected',
            message:
                'Device discovery is not implemented in Phase 1. The workspace '
                'therefore shows unavailable device and endpoint states instead '
                'of sample hardware.',
            action: TextButton(
              onPressed: () => _go(context, AppRoutes.deviceManager),
              child: const Text('Open devices'),
            ),
          ),
          const SizedBox(height: UamSpacing.xl),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 860;
            final left = <Widget>[
              _SelectedDeviceCard(controller: controller),
              const SizedBox(height: UamSpacing.xl),
              _QuickEqualizerCard(controller: controller),
              const SizedBox(height: UamSpacing.xl),
              _HardwareShortcutCard(controller: controller),
            ];
            final right = <Widget>[
              _ProcessingCard(controller: controller),
              const SizedBox(height: UamSpacing.xl),
              _RecentPresetsCard(controller: controller),
              const SizedBox(height: UamSpacing.xl),
              _SystemHealthCard(controller: controller),
            ];
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  left[0],
                  const SizedBox(height: UamSpacing.xl),
                  left[2],
                  const SizedBox(height: UamSpacing.xl),
                  right[0],
                  const SizedBox(height: UamSpacing.xl),
                  left[4],
                  const SizedBox(height: UamSpacing.xl),
                  right[2],
                  const SizedBox(height: UamSpacing.xl),
                  right[4],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 155,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: left,
                  ),
                ),
                const SizedBox(width: UamSpacing.xl),
                Expanded(
                  flex: 65,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: right,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static void _go(BuildContext context, String route) {
    Navigator.of(context).pushReplacementNamed(route);
  }
}

class _SelectedDeviceCard extends StatelessWidget {
  const _SelectedDeviceCard({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final device = controller.devices.selected;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UamSectionHeader(
            title: 'Selected device',
            subtitle: 'Verified device identity and connection state',
          ),
          const SizedBox(height: UamSpacing.xl),
          Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.insetPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Icon(
                  Icons.headphones,
                  size: 28,
                  color: device == null ? colors.textTertiary : colors.accent,
                ),
              ),
              const SizedBox(width: UamSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device?.displayName ?? 'No device selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UamTypography.deviceTitle.copyWith(
                        color: colors.textPrimary,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: UamSpacing.xs),
                    UamStatus(
                      label: device?.connectionState.label ?? 'Unavailable',
                      tone: device?.isConnected ?? false
                          ? UamStatusTone.success
                          : UamStatusTone.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: UamSpacing.lg),
          Text(
            device == null
                ? 'No native device adapter is available in this phase. '
                      'Connect a device through a supported platform adapter in '
                      'a later phase.'
                : 'Metadata comes from the platform adapter. Battery, codec, and '
                      'transport values remain hidden when not reported.',
            style: UamTypography.description.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: UamSpacing.xl),
          Wrap(
            spacing: UamSpacing.md,
            runSpacing: UamSpacing.md,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () =>
                    DashboardPage._go(context, AppRoutes.deviceManager),
                icon: const Icon(Icons.search, size: 17),
                label: Text(device == null ? 'Find devices' : 'View device'),
              ),
              OutlinedButton(
                onPressed: () =>
                    DashboardPage._go(context, AppRoutes.hardwareControls),
                child: const Text('Hardware controls'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickEqualizerCard extends StatelessWidget {
  const _QuickEqualizerCard({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final configuration = controller.equalizer.configuration;
    final active = controller.presets.active;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamSectionHeader(
            title: 'Quick equalizer',
            subtitle: 'Desired configuration, not verified processing',
            trailing: TextButton(
              onPressed: () => DashboardPage._go(context, AppRoutes.equalizer),
              child: const Text('Fine tune'),
            ),
          ),
          const SizedBox(height: UamSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  active == null ? 'No preset active' : active.name,
                  style: UamTypography.cardTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              CapabilityBadge(
                label: configuration.bypassed ? 'Bypassed' : 'Configured',
                tone: configuration.bypassed
                    ? UamStatusTone.muted
                    : UamStatusTone.info,
              ),
            ],
          ),
          const SizedBox(height: UamSpacing.md),
          UamResponseGraph(
            bands: configuration.bands,
            preampDb: configuration.preampDb,
            bypassed: configuration.bypassed,
            height: 120,
            showLabels: false,
          ),
          const SizedBox(height: UamSpacing.md),
          Wrap(
            spacing: UamSpacing.md,
            runSpacing: UamSpacing.xs,
            children: <Widget>[
              for (final band in configuration.bands)
                _BandChip(frequency: band.frequencyHz, gainDb: band.gainDb),
            ],
          ),
          const SizedBox(height: UamSpacing.md),
          Text(
            'Preamp ${configuration.preampDb.toStringAsFixed(1)} dB · '
            '${configuration.bands.length} peaking bands · '
            'Editor range -12 to +12 dB',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _BandChip extends StatelessWidget {
  const _BandChip({required this.frequency, required this.gainDb});

  final double frequency;
  final double gainDb;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final label = frequency >= 1000
        ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}k'
        : '${frequency.toInt()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.insetPanel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label ${gainDb >= 0 ? '+' : ''}${gainDb.toStringAsFixed(1)}',
        style: UamTypography.monospace.copyWith(
          color: colors.textSecondary,
          fontSize: 8,
        ),
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final engineState = controller.engine.state;
    final verified = engineState.processingVerified;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UamSectionHeader(
            title: 'Audio processing',
            subtitle: 'Read-only engine truth',
          ),
          const SizedBox(height: UamSpacing.xl),
          Center(
            child: UamProcessingRing(
              primaryLabel: verified ? 'Processing' : 'Not processing',
              secondaryLabel: engineState.processingScope.label,
              active: verified,
            ),
          ),
          const SizedBox(height: UamSpacing.xl),
          UamKeyValue(
            label: 'ENGINE',
            value: engineState.status.label,
            valueColor: engineState.coreReachable
                ? colors.success
                : colors.warning,
          ),
          const UamKeyValue(label: 'SCOPE', value: 'Configuration only'),
          UamKeyValue(
            label: 'VERIFIED OUTPUT',
            value: verified ? 'Verified' : 'Not verified',
            valueColor: verified ? colors.success : colors.textTertiary,
          ),
          UamKeyValue(
            label: 'SAMPLE RATE',
            value: engineState.sampleRateHz == null
                ? 'Not reported'
                : '${engineState.sampleRateHz} Hz',
          ),
          const SizedBox(height: UamSpacing.md),
          UamNotice(
            tone: verified ? UamStatusTone.success : UamStatusTone.info,
            message:
                'UAM is not attached to an audio output in Phase 1. This card '
                'will report verified processing only when the Rust core and a '
                'platform backend report an active stream.',
          ),
          const SizedBox(height: UamSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  DashboardPage._go(context, AppRoutes.audioEngine),
              child: const Text('Open audio engine'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HardwareShortcutCard extends StatelessWidget {
  const _HardwareShortcutCard({required this.controller});

  final UamAppController controller;

  static const List<(String, String, IconData, CapabilityAvailability)>
  _features = <(String, String, IconData, CapabilityAvailability)>[
    (
      'anc',
      'Active noise cancellation',
      Icons.noise_control_off_outlined,
      CapabilityAvailability.notImplemented,
    ),
    (
      'transparency',
      'Transparency mode',
      Icons.hearing_outlined,
      CapabilityAvailability.notImplemented,
    ),
    (
      'low_latency',
      'Low-latency mode',
      Icons.speed_outlined,
      CapabilityAvailability.notImplemented,
    ),
    (
      'multipoint',
      'Multipoint',
      Icons.devices_other_outlined,
      CapabilityAvailability.unsupported,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final device = controller.devices.selected;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamSectionHeader(
            title: 'Hardware shortcuts',
            subtitle: 'Capability states, not assumed controls',
            trailing: TextButton(
              onPressed: () =>
                  DashboardPage._go(context, AppRoutes.hardwareControls),
              child: const Text('All controls'),
            ),
          ),
          const SizedBox(height: UamSpacing.lg),
          for (final feature in _features) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: UamSpacing.sm),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.insetPanel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(
                      feature.$3,
                      size: 17,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: UamSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          feature.$2,
                          style: UamTypography.navigation.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          device == null
                              ? 'Select a device to evaluate'
                              : 'No adapter control available',
                          style: UamTypography.micro.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CapabilityBadge(
                    label: device == null
                        ? CapabilityAvailability.disconnected.label
                        : feature.$4.label,
                    tone: UamStatusTone.muted,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentPresetsCard extends StatelessWidget {
  const _RecentPresetsCard({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final entries = controller.presets.entries.take(3).toList(growable: false);
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamSectionHeader(
            title: 'Recently used',
            subtitle: 'Bundled reference presets',
            trailing: TextButton(
              onPressed: () => DashboardPage._go(context, AppRoutes.presets),
              child: const Text('Library'),
            ),
          ),
          const SizedBox(height: UamSpacing.md),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: UamSpacing.sm),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => controller.activatePreset(entry.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: UamSpacing.sm,
                      vertical: UamSpacing.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: colors.insetPanel,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            Icons.graphic_eq,
                            size: 15,
                            color: controller.presets.activeId == entry.id
                                ? colors.accent
                                : colors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: UamSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UamTypography.navigation.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                '${entry.document.bandCount} bands · '
                                '${entry.category}',
                                style: UamTypography.micro.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (controller.presets.activeId == entry.id)
                          const CapabilityBadge(
                            label: 'Active',
                            tone: UamStatusTone.success,
                          )
                        else
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: colors.textTertiary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (entries.isEmpty)
            Text(
              'The local library is empty.',
              style: UamTypography.description.copyWith(
                color: colors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _SystemHealthCard extends StatelessWidget {
  const _SystemHealthCard({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final state = controller.engine.state;
    final reachable = state.coreReachable;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UamSectionHeader(
            title: 'System health',
            subtitle: 'Runtime evidence only',
          ),
          const SizedBox(height: UamSpacing.lg),
          _HealthRow(
            icon: Icons.memory,
            label: 'Rust core',
            value: reachable ? 'Reachable' : 'Unavailable',
            tone: reachable
                ? UamStatusTone.success
                : (controller.engine.isLoading
                      ? UamStatusTone.info
                      : UamStatusTone.error),
          ),
          _HealthRow(
            icon: Icons.cable,
            label: 'Audio backend',
            value: 'Not connected',
            tone: UamStatusTone.muted,
          ),
          _HealthRow(
            icon: Icons.devices,
            label: 'Device adapter',
            value: 'Not implemented',
            tone: UamStatusTone.planned,
          ),
          _HealthRow(
            icon: Icons.verified_outlined,
            label: 'Processing',
            value: state.processingVerified ? 'Verified' : 'Not verified',
            tone: state.processingVerified
                ? UamStatusTone.success
                : UamStatusTone.muted,
          ),
          const SizedBox(height: UamSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  DashboardPage._go(context, AppRoutes.audioEngine),
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('Run diagnostics'),
            ),
          ),
          const SizedBox(height: UamSpacing.sm),
          Text(
            state.checkedAt == null
                ? 'No engine check has completed.'
                : 'Last checked ${state.checkedAt!.toLocal()}.',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final UamStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: UamSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: colors.statusColor(tone)),
          const SizedBox(width: UamSpacing.md),
          Expanded(
            child: Text(
              label,
              style: UamTypography.description.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: UamTypography.micro.copyWith(
              color: colors.statusColor(tone),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
