import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/state/uam_app_controller.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_breakpoints.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../../shared/models/audio_device.dart';
import '../../../shared/models/capability.dart';

/// Device discovery, connection state, metadata, and permission posture.
class DeviceManagerPage extends StatelessWidget {
  const DeviceManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final deviceController = controller.devices;
    return ListView(
      key: const Key('page-device-manager'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        UamPageHeader(
          eyebrow: 'Hardware',
          title: 'Device manager',
          description:
              'Enumerate active Windows render endpoints, inspect the reported '
              'mix format, and choose the endpoint UAM renders to. Capability '
              'claims carry provenance.',
          actions: <Widget>[
            FilledButton.icon(
              onPressed: deviceController.isScanning
                  ? null
                  : () => deviceController.refresh(),
              icon: deviceController.isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar, size: 17),
              label: Text(
                deviceController.isScanning
                    ? 'Scanning...'
                    : 'Refresh endpoints',
              ),
            ),
          ],
        ),
        const SizedBox(height: UamSpacing.lg),
        UamNotice(
          tone: UamStatusTone.info,
          title: 'Application-owned output',
          message:
              'UAM enumerates native render endpoints and renders its own '
              'app-owned stream to the selected one. It does not capture or '
              'modify audio from other applications.',
        ),
        const SizedBox(height: UamSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 1000;
            final primary = _PrimaryColumn(controller: controller);
            final permissions = const _BackendPanel();
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  primary,
                  const SizedBox(height: UamSpacing.xl),
                  permissions,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: primary),
                const SizedBox(width: UamSpacing.xl),
                SizedBox(
                  width: UamBreakpoints.permissionPanel,
                  child: permissions,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PrimaryColumn extends StatelessWidget {
  const _PrimaryColumn({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final deviceController = controller.devices;
    final snapshot = deviceController.snapshot;
    final selected = deviceController.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              UamSectionHeader(
                title: selected == null
                    ? 'Connected device'
                    : selected.displayName,
                subtitle: selected == null
                    ? 'No render endpoint is selected'
                    : 'Connection state: ${selected.connectionState.label}',
                trailing: selected == null
                    ? const CapabilityBadge(
                        label: 'No selection',
                        tone: UamStatusTone.muted,
                      )
                    : UamStatus(
                        label: selected.connectionState.label,
                        tone: selected.isConnected
                            ? UamStatusTone.success
                            : UamStatusTone.muted,
                      ),
              ),
              const SizedBox(height: UamSpacing.xl),
              if (selected == null)
                UamEmptyState(
                  icon: Icons.headset_off_outlined,
                  title: 'No endpoint selected',
                  description:
                      'Refresh endpoints and select one. UAM shows only what the '
                      'native audio backend reports; no sample device is '
                      'displayed.',
                  action: OutlinedButton.icon(
                    onPressed: deviceController.isScanning
                        ? null
                        : () => deviceController.refresh(),
                    icon: const Icon(Icons.radar, size: 17),
                    label: const Text('Refresh endpoints'),
                  ),
                )
              else
                _DeviceDetail(device: selected),
            ],
          ),
        ),
        const SizedBox(height: UamSpacing.xl),
        UamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const UamSectionHeader(
                title: 'Available devices',
                subtitle: 'Active render endpoints reported by the backend',
              ),
              const SizedBox(height: UamSpacing.lg),
              if (deviceController.isScanning)
                const _ScanningState()
              else if (snapshot.status == DeviceDiscoveryStatus.error)
                UamNotice(
                  tone: UamStatusTone.error,
                  title: 'Discovery failed',
                  message: snapshot.reason ?? 'The adapter returned an error.',
                )
              else if (snapshot.status ==
                  DeviceDiscoveryStatus.permissionRequired)
                UamNotice(
                  tone: UamStatusTone.warning,
                  title: 'Permission required',
                  message:
                      snapshot.reason ??
                      'Device discovery needs a platform permission before it can '
                          'run.',
                  action: const TextButton(
                    onPressed: null,
                    child: Text('Review permission'),
                  ),
                )
              else if (!snapshot.hasDevices)
                UamEmptyState(
                  icon: Icons.bluetooth_disabled,
                  title: snapshot.status == DeviceDiscoveryStatus.unavailable
                      ? 'Discovery unavailable'
                      : 'No devices found',
                  description:
                      snapshot.reason ??
                      'The native backend returned no active render endpoints. '
                          'Empty is not the same as unsupported.',
                  action: OutlinedButton.icon(
                    onPressed: deviceController.isScanning
                        ? null
                        : () => deviceController.refresh(),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('Refresh endpoints'),
                  ),
                )
              else
                Column(
                  children: <Widget>[
                    for (final device in snapshot.devices)
                      _AvailableDeviceRow(
                        device: device,
                        selected: selected?.id == device.id,
                        onSelect: () {
                          unawaited(deviceController.selectDevice(device));
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanningState extends StatelessWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: UamSpacing.empty),
        child: Column(
          children: <Widget>[
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: UamSpacing.lg),
            Text(
              'Searching nearby...',
              style: UamTypography.description.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: UamSpacing.xs),
            Text(
              'Waiting for a platform adapter response.',
              style: UamTypography.micro.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceDetail extends StatelessWidget {
  const _DeviceDetail({required this.device});

  final AudioDevice device;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final metadata = <(String, String)>[
      ('TYPE', device.type.label),
      ('TRANSPORT', device.transport.label),
      if (device.isDefault) ('DEFAULT', 'Yes'),
      if (device.formatSummary != null) ('FORMAT', device.formatSummary!),
      if (device.transportVersion != null)
        ('TRANSPORT VERSION', device.transportVersion!),
      if (device.codec != null) ('CODEC', device.codec!),
      if (device.signalStrength != null) ('SIGNAL', device.signalStrength!),
      if (device.battery != null && device.battery!.isValid)
        ('BATTERY', '${device.battery!.percent}%'),
      if (device.platformId != null) ('PLATFORM ID', device.platformId!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: UamSpacing.md,
          runSpacing: UamSpacing.md,
          children: <Widget>[
            for (final item in metadata)
              Container(
                padding: const EdgeInsets.all(UamSpacing.md),
                width: 150,
                decoration: BoxDecoration(
                  color: colors.insetPanel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.$1,
                      style: UamTypography.technicalLabel.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UamTypography.numeric.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: UamSpacing.lg),
        Text(
          'CAPABILITIES',
          style: UamTypography.technicalLabel.copyWith(
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: UamSpacing.sm),
        if (device.capabilities.isEmpty)
          Text(
            'No capability reports were returned. This is not proof that the '
            'device lacks a feature.',
            style: UamTypography.description.copyWith(
              color: colors.textSecondary,
            ),
          )
        else
          Wrap(
            spacing: UamSpacing.sm,
            runSpacing: UamSpacing.sm,
            children: <Widget>[
              for (final capability in device.capabilities)
                CapabilityBadge(
                  label: capability.label,
                  tone: _toneFor(capability.availability),
                  tooltip: capability.reason,
                ),
            ],
          ),
      ],
    );
  }

  static UamStatusTone _toneFor(CapabilityAvailability availability) {
    return switch (availability) {
      CapabilityAvailability.available => UamStatusTone.success,
      CapabilityAvailability.permissionRequired => UamStatusTone.warning,
      CapabilityAvailability.notImplemented ||
      CapabilityAvailability.unsupported ||
      CapabilityAvailability.unavailableOnPlatform => UamStatusTone.planned,
      CapabilityAvailability.error => UamStatusTone.error,
      _ => UamStatusTone.muted,
    };
  }
}

class _AvailableDeviceRow extends StatelessWidget {
  const _AvailableDeviceRow({
    required this.device,
    required this.selected,
    required this.onSelect,
  });

  final AudioDevice device;
  final bool selected;
  final VoidCallback onSelect;

  bool get selectable => device.isConnected;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: UamSpacing.sm),
      child: Material(
        color: selected ? colors.infoOverlay : colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: selectable ? onSelect : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(UamSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? colors.accent : colors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.headphones,
                  size: 20,
                  color: selected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: UamSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        device.displayName,
                        style: UamTypography.navigation.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${device.type.label} · ${device.transport.label} · '
                        '${device.connectionState.label}'
                        '${device.isDefault ? ' · Default' : ''}',
                        style: UamTypography.micro.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      if (device.formatSummary != null)
                        Text(
                          device.formatSummary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UamTypography.micro.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  selected
                      ? 'SELECTED'
                      : (device.isDefault ? 'DEFAULT' : 'SELECT'),
                  style: UamTypography.badge.copyWith(
                    color: selected ? colors.accent : colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackendPanel extends StatelessWidget {
  const _BackendPanel();

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final colors = context.uamColors;
    final available = controller.devices.isAvailable;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cable_outlined, size: 18, color: colors.textSecondary),
              const SizedBox(width: UamSpacing.md),
              Expanded(
                child: Text(
                  'Render backend',
                  style: UamTypography.cardTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: UamSpacing.md),
          CapabilityBadge(
            label: available ? 'Available' : 'Unavailable',
            tone: available ? UamStatusTone.success : UamStatusTone.muted,
          ),
          const SizedBox(height: UamSpacing.lg),
          Text(
            controller.devices.adapterDescription,
            style: UamTypography.description.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: UamSpacing.md),
          Text(
            'UAM processes only audio it renders itself. System-wide capture '
            'would require a virtual audio device or an audio processing object, '
            'which is not part of this build.',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
          if (controller.devices.selectionError != null) ...<Widget>[
            const SizedBox(height: UamSpacing.lg),
            UamNotice(
              tone: UamStatusTone.warning,
              title: 'Selection notice',
              message: controller.devices.selectionError!,
            ),
          ],
          const SizedBox(height: UamSpacing.lg),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: UamSpacing.lg),
          Text(
            'ENDPOINT STATES',
            style: UamTypography.technicalLabel.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: UamSpacing.sm),
          const Wrap(
            spacing: UamSpacing.sm,
            runSpacing: UamSpacing.sm,
            children: <Widget>[
              CapabilityBadge(label: 'Active', tone: UamStatusTone.success),
              CapabilityBadge(label: 'Disabled', tone: UamStatusTone.warning),
              CapabilityBadge(label: 'Unplugged', tone: UamStatusTone.muted),
              CapabilityBadge(label: 'Not present', tone: UamStatusTone.muted),
              CapabilityBadge(label: 'Unknown', tone: UamStatusTone.muted),
              CapabilityBadge(label: 'Error', tone: UamStatusTone.error),
            ],
          ),
          const SizedBox(height: UamSpacing.md),
          Text(
            'Only active endpoints can be selected for rendering. Disconnected '
            'or unknown states never render as selectable.',
            style: UamTypography.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
