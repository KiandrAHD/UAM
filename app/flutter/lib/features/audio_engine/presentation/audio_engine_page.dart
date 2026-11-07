import 'dart:async';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter/services.dart' hide DiagnosticLevel;

import '../../../app/state/uam_app_controller.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/components/uam_processing_ring.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../../platform/audio/audio_processing_scope.dart';
import '../../../shared/models/engine_runtime_state.dart';
import '../../settings/presentation/rust_core_proof_page.dart';
import '../domain/diagnostic_entry.dart';

/// Engine readiness, processing scope, endpoint, backend, and diagnostics.
///
/// Every value on this page is read from the runtime bridge or explicitly
/// reported as not available. It never claims verified processing.
class AudioEnginePage extends StatelessWidget {
  const AudioEnginePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final state = controller.engine.state;
    final verified = state.processingVerified;
    return ListView(
      key: const Key('page-audio-engine'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        UamPageHeader(
          eyebrow: 'Runtime',
          title: 'Audio engine',
          description:
              'Engine readiness, processing scope, and diagnostics from the '
              'control path. Configured values and verified processing are '
              'separate fields.',
          actions: <Widget>[
            UamIconButton(
              icon: Icons.refresh,
              label: 'Reload engine status',
              onPressed: controller.engine.isLoading
                  ? null
                  : () {
                      unawaited(controller.engine.load());
                    },
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      RustCoreProofPage(engineController: controller.engine),
                ),
              ),
              icon: const Icon(Icons.memory, size: 17),
              label: const Text('Phase 0 core proof'),
            ),
          ],
        ),
        const SizedBox(height: UamSpacing.lg),
        const UamNotice(
          tone: UamStatusTone.info,
          title: 'Configuration only',
          message:
              'UAM is not attached to an audio output in Phase 1. The core can '
              'report readiness and accept a configuration, but no live stream '
              'is verified. Verified output is shown only when the core and a '
              'backend report an active stream.',
        ),
        const SizedBox(height: UamSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 1100;
            final status = _EngineStatusCard(
              controller: controller,
              state: state,
              verified: verified,
            );
            final path = _SignalPathCard(state: state, verified: verified);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: status),
                  const SizedBox(width: UamSpacing.lgPlus),
                  Expanded(child: path),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                status,
                const SizedBox(height: UamSpacing.xl),
                path,
              ],
            );
          },
        ),
        const SizedBox(height: UamSpacing.xl),
        _TechnicalGrid(state: state),
        const SizedBox(height: UamSpacing.xl),
        _DiagnosticLogCard(controller: controller),
      ],
    );
  }
}

class _EngineStatusCard extends StatelessWidget {
  const _EngineStatusCard({
    required this.controller,
    required this.state,
    required this.verified,
  });

  final UamAppController controller;
  final EngineRuntimeState state;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final loading = controller.engine.isLoading;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamSectionHeader(
            title: 'Engine status',
            subtitle: 'Read-only truth from the Rust core',
            trailing: UamStatus(
              label: loading ? 'Checking' : state.status.label,
              tone: loading
                  ? UamStatusTone.info
                  : (state.coreReachable
                        ? UamStatusTone.success
                        : UamStatusTone.error),
            ),
          ),
          const SizedBox(height: UamSpacing.xl),
          Center(
            child: UamProcessingRing(
              primaryLabel: verified ? 'Processing' : 'Ready, not processing',
              secondaryLabel: state.processingScope.label,
              active: verified,
            ),
          ),
          const SizedBox(height: UamSpacing.xl),
          Text(
            state.summary,
            style: UamTypography.description.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: UamSpacing.md),
          UamKeyValue(
            label: 'CORE VERSION',
            value: state.coreVersion == null
                ? 'Not reported'
                : 'v${state.coreVersion}',
          ),
          UamKeyValue(
            label: 'BRIDGE ABI',
            value: state.bridgeAbiVersion == null
                ? 'Not reported'
                : '${state.bridgeAbiVersion}',
          ),
          UamKeyValue(
            label: 'CONFIG ACCEPTED',
            value: state.configurationAccepted ? 'Accepted' : 'Not accepted',
            valueColor: state.configurationAccepted
                ? colors.success
                : colors.textTertiary,
          ),
          UamKeyValue(
            label: 'LAST CHECKED',
            value: state.checkedAt == null
                ? 'Never'
                : state.checkedAt!.toLocal().toString(),
          ),
        ],
      ),
    );
  }
}

class _SignalPathCard extends StatelessWidget {
  const _SignalPathCard({required this.state, required this.verified});

  final EngineRuntimeState state;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final nodes = <_SignalNode>[
      _SignalNode(
        label: 'Desired config',
        detail: 'Edited in the Equalizer',
        tone: UamStatusTone.info,
        icon: Icons.tune,
      ),
      _SignalNode(
        label: 'Rust core',
        detail: state.coreReachable ? 'Reachable' : 'Unavailable',
        tone: state.coreReachable ? UamStatusTone.success : UamStatusTone.error,
        icon: Icons.memory,
      ),
      _SignalNode(
        label: 'Audio backend',
        detail: state.backendName ?? 'Not connected',
        tone: UamStatusTone.muted,
        icon: Icons.settings_input_component,
      ),
      _SignalNode(
        label: 'Output',
        detail: verified ? 'Verified' : 'Not verified',
        tone: verified ? UamStatusTone.success : UamStatusTone.muted,
        icon: Icons.speaker,
      ),
    ];
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UamSectionHeader(
            title: 'Signal path',
            subtitle: 'Configuration is not proof of processing',
          ),
          const SizedBox(height: UamSpacing.xl),
          for (var index = 0; index < nodes.length; index += 1) ...<Widget>[
            _SignalPathNode(node: nodes[index]),
            if (index != nodes.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: UamSpacing.xs),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 15),
                    Icon(
                      Icons.arrow_downward,
                      size: 16,
                      color: colors.textTertiary,
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

class _SignalNode {
  const _SignalNode({
    required this.label,
    required this.detail,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String detail;
  final UamStatusTone tone;
  final IconData icon;
}

class _SignalPathNode extends StatelessWidget {
  const _SignalPathNode({required this.node});

  final _SignalNode node;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final color = colors.statusColor(node.tone);
    return Container(
      padding: const EdgeInsets.all(UamSpacing.md),
      decoration: BoxDecoration(
        color: colors.insetPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(node.icon, size: 16, color: color),
          ),
          const SizedBox(width: UamSpacing.mdPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  node.label,
                  style: UamTypography.navigation.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  node.detail,
                  style: UamTypography.micro.copyWith(
                    color: colors.statusColor(node.tone),
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

class _TechnicalGrid extends StatelessWidget {
  const _TechnicalGrid({required this.state});

  final EngineRuntimeState state;

  @override
  Widget build(BuildContext context) {
    return UamResponsiveGrid(
      minTileWidth: 200,
      children: <Widget>[
        UamMetricTile(
          label: 'Processing scope',
          value: state.processingScope.label,
          caption:
              state.processingScope == AudioProcessingScope.configurationOnly
              ? 'No stream attached'
              : 'Scope reported by the core',
          icon: Icons.layers_outlined,
          tone: UamStatusTone.info,
        ),
        UamMetricTile(
          label: 'Selected endpoint',
          value: state.selectedEndpoint ?? 'Not selected',
          caption: 'No endpoint is chosen in Phase 1',
          icon: Icons.radio_button_checked,
          tone: UamStatusTone.muted,
        ),
        UamMetricTile(
          label: 'Active endpoint',
          value: state.activeEndpoint ?? 'None',
          caption: 'Requires a live backend',
          icon: Icons.settings_input_composite,
          tone: UamStatusTone.muted,
        ),
        UamMetricTile(
          label: 'Audio backend',
          value: state.backendName ?? 'Not connected',
          caption: 'Platform backend not attached',
          icon: Icons.cable_outlined,
          tone: UamStatusTone.muted,
        ),
        UamMetricTile(
          label: 'Sample rate',
          value: state.sampleRateHz == null
              ? 'Not reported'
              : '${state.sampleRateHz} Hz',
          caption: state.bitDepth == null ? null : '${state.bitDepth}-bit',
          icon: Icons.graphic_eq,
          tone: UamStatusTone.muted,
        ),
        UamMetricTile(
          label: 'Latency',
          value: state.latencyMs == null
              ? 'Not measured'
              : '${state.latencyMs!.toStringAsFixed(1)} ms',
          caption: 'No live buffer to measure',
          icon: Icons.timer_outlined,
          tone: UamStatusTone.muted,
        ),
      ],
    );
  }
}

class _DiagnosticLogCard extends StatelessWidget {
  const _DiagnosticLogCard({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final entries = controller.engine.entries.reversed.toList(growable: false);
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UamSectionHeader(
            title: 'Diagnostics',
            subtitle: 'Session events from the control path',
            trailing: OutlinedButton.icon(
              onPressed: () {
                unawaited(_copyReport(context, controller));
              },
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Copy report'),
            ),
          ),
          const SizedBox(height: UamSpacing.lg),
          if (entries.isEmpty)
            Text(
              'No diagnostic events have been recorded yet. Reload the engine '
              'status to produce a session entry.',
              style: UamTypography.description.copyWith(
                color: colors.textTertiary,
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: colors.insetPanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: <Widget>[
                  for (var index = 0; index < entries.length; index += 1)
                    _DiagnosticRow(
                      entry: entries[index],
                      showDivider: index != entries.length - 1,
                    ),
                ],
              ),
            ),
          const SizedBox(height: UamSpacing.md),
          Text(
            'Reports contain runtime status only. No device identifiers, audio '
            'content, or private paths are included.',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.entry, required this.showDivider});

  final DiagnosticEntry entry;
  final bool showDivider;

  static UamStatusTone _toneFor(DiagnosticLevel level) => switch (level) {
    DiagnosticLevel.info => UamStatusTone.info,
    DiagnosticLevel.notice => UamStatusTone.warning,
    DiagnosticLevel.error => UamStatusTone.error,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final tone = _toneFor(entry.level);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: UamSpacing.md,
            vertical: UamSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.formattedTime,
                style: UamTypography.monospace.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: UamSpacing.md),
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.statusColor(tone),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: UamSpacing.md),
              Expanded(
                child: Text(
                  entry.message,
                  style: UamTypography.micro.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(color: colors.border, height: 1, thickness: 1),
      ],
    );
  }
}

Future<void> _copyReport(
  BuildContext context,
  UamAppController controller,
) async {
  final state = controller.engine.state;
  final buffer = StringBuffer()
    ..writeln('UAM engine diagnostic report')
    ..writeln('Status: ${state.status.label}')
    ..writeln('Core reachable: ${state.coreReachable}')
    ..writeln('Core version: ${state.coreVersion ?? 'not reported'}')
    ..writeln('Bridge ABI: ${state.bridgeAbiVersion ?? 'not reported'}')
    ..writeln('Processing scope: ${state.processingScope.label}')
    ..writeln('Processing verified: ${state.processingVerified}')
    ..writeln('Configuration accepted: ${state.configurationAccepted}')
    ..writeln('Backend: ${state.backendName ?? 'not connected'}')
    ..writeln('Selected endpoint: ${state.selectedEndpoint ?? 'not selected'}')
    ..writeln('Active endpoint: ${state.activeEndpoint ?? 'none'}')
    ..writeln('Checked at: ${state.checkedAt ?? 'never'}')
    ..writeln('Events:');
  final entries = controller.engine.entries;
  if (entries.isEmpty) {
    buffer.writeln('  (none)');
  } else {
    for (final entry in entries) {
      buffer.writeln('  [${entry.formattedTime}] ${entry.message}');
    }
  }
  await Clipboard.setData(ClipboardData(text: buffer.toString()));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Diagnostic report copied to clipboard.')),
  );
}
