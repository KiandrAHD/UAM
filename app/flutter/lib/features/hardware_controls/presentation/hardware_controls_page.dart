import 'package:flutter/material.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/uam_app_controller.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_colors.dart';
import '../../../design_system/tokens/uam_radii.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';
import '../../../shared/models/audio_device.dart';
import '../../../shared/models/capability.dart';

/// Device-specific controls with explicit capability gating.
///
/// A control renders as interactive only when the adapter reports the feature
/// as available on a connected device. Every other state is explanatory.
class HardwareControlsPage extends StatelessWidget {
  const HardwareControlsPage({super.key});

  static const List<_HardwareFeature> _features = <_HardwareFeature>[
    _HardwareFeature(
      featureId: 'anc',
      label: 'Active noise cancellation',
      description:
          'Reduces steady ambient noise when the device and platform expose a '
          'verified control.',
      icon: Icons.noise_control_off_outlined,
      fallback: CapabilityAvailability.notImplemented,
    ),
    _HardwareFeature(
      featureId: 'transparency',
      label: 'Transparency mode',
      description:
          'Passes external sound through the microphones for awareness. Mutually '
          'exclusive with noise cancellation where supported.',
      icon: Icons.hearing_outlined,
      fallback: CapabilityAvailability.notImplemented,
    ),
    _HardwareFeature(
      featureId: 'low_latency',
      label: 'Low-latency mode',
      description:
          'Prioritises latency over stability for gaming and monitoring when the '
          'device supports it.',
      icon: Icons.speed_outlined,
      fallback: CapabilityAvailability.notImplemented,
    ),
    _HardwareFeature(
      featureId: 'adaptive_noise',
      label: 'Adaptive noise control',
      description:
          'Adjusts cancellation automatically based on the environment. No '
          'adapter reports it in Phase 1.',
      icon: Icons.auto_awesome_outlined,
      fallback: CapabilityAvailability.notImplemented,
      badgeOnly: true,
    ),
    _HardwareFeature(
      featureId: 'touch_controls',
      label: 'Touch controls',
      description:
          'Gestures on the device. Requires a platform permission before UAM can '
          'observe or change them.',
      icon: Icons.touch_app_outlined,
      fallback: CapabilityAvailability.permissionRequired,
      permissionAction: true,
    ),
    _HardwareFeature(
      featureId: 'multipoint',
      label: 'Multipoint',
      description:
          'Simultaneous connection to two source devices. Not implemented in '
          'Phase 1.',
      icon: Icons.devices_other_outlined,
      fallback: CapabilityAvailability.notImplemented,
      badgeOnly: true,
    ),
    _HardwareFeature(
      featureId: 'sidetone',
      label: 'Microphone sidetone',
      description:
          'Injects the user voice into the headset. The operating system rarely '
          'exposes this; it stays unsupported until verified.',
      icon: Icons.mic_none_outlined,
      fallback: CapabilityAvailability.unsupported,
      badgeOnly: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final device = controller.devices.selected;
    return ListView(
      key: const Key('page-hardware-controls'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        UamPageHeader(
          eyebrow: 'Device features',
          title: 'Hardware controls',
          description:
              'Controls are rendered only when a platform adapter reports a '
              'feature as available on the selected device. Everything else is '
              'shown as an explicit capability state.',
          actions: <Widget>[_SelectedDeviceChip(device: device)],
        ),
        const SizedBox(height: UamSpacing.lg),
        if (device == null)
          UamNotice(
            tone: UamStatusTone.warning,
            title: 'No device connected',
            message:
                'No platform adapter has reported a connected device. Every '
                'control below is shown as disconnected or not implemented '
                'rather than assumed available.',
            action: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pushReplacementNamed(AppRoutes.deviceManager),
              child: const Text('Open devices'),
            ),
          ),
        const SizedBox(height: UamSpacing.xl),
        UamResponsiveGrid(
          minTileWidth: 340,
          children: <Widget>[
            for (final feature in _features)
              _HardwareControlCard(
                feature: feature,
                device: device,
                controller: controller,
              ),
          ],
        ),
        const SizedBox(height: UamSpacing.xl),
        const UamNotice(
          tone: UamStatusTone.info,
          title: 'Capability transparency',
          message:
              'Available, unsupported, permission-required, disconnected, '
              'not-implemented, unknown, and error are distinct states. An '
              'unavailable feature explains why it cannot be changed and never '
              'renders an actionable control.',
        ),
      ],
    );
  }
}

class _HardwareFeature {
  const _HardwareFeature({
    required this.featureId,
    required this.label,
    required this.description,
    required this.icon,
    required this.fallback,
    this.badgeOnly = false,
    this.permissionAction = false,
  });

  final String featureId;
  final String label;
  final String description;
  final IconData icon;

  /// Availability reported when the device adapter exposes no capability entry.
  final CapabilityAvailability fallback;

  /// Features that never render a toggle in Phase 1.
  final bool badgeOnly;

  /// Features that surface a (non-actionable) permission action.
  final bool permissionAction;
}

class _HardwareControlCard extends StatelessWidget {
  const _HardwareControlCard({
    required this.feature,
    required this.device,
    required this.controller,
  });

  final _HardwareFeature feature;
  final AudioDevice? device;
  final UamAppController controller;

  CapabilityAvailability get _availability {
    final current = device;
    if (current == null) {
      return CapabilityAvailability.disconnected;
    }
    if (feature.badgeOnly) {
      final reported = current.capability(feature.featureId);
      return reported?.availability ?? feature.fallback;
    }
    final reported = current.capability(feature.featureId);
    return reported?.availability ?? feature.fallback;
  }

  bool get _actionable {
    final current = device;
    return current != null &&
        current.isConnected &&
        _availability.isActionable &&
        !feature.badgeOnly;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final availability = _availability;
    final connected = device?.isConnected ?? false;
    return UamCard(
      semanticLabel: '${feature.label}. ${availability.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _actionable ? colors.infoOverlay : colors.insetPanel,
                  borderRadius: BorderRadius.circular(UamRadii.smallControl),
                  border: Border.all(color: colors.border),
                ),
                child: Icon(
                  feature.icon,
                  size: 19,
                  color: _actionable ? colors.accent : colors.textTertiary,
                ),
              ),
              const SizedBox(width: UamSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      feature.label,
                      style: UamTypography.cardTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: UamSpacing.xs),
                    Text(
                      feature.description,
                      style: UamTypography.description.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: UamSpacing.lg),
          if (_actionable)
            _AvailableControl(
              featureId: feature.featureId,
              value: controller.hardwareValue(feature.featureId),
              onChanged: (value) => controller.setHardwareValue(
                feature.featureId,
                availability,
                value,
              ),
            )
          else
            _UnavailableState(
              availability: availability,
              connected: connected,
              permissionAction: feature.permissionAction,
            ),
        ],
      ),
    );
  }
}

class _AvailableControl extends StatelessWidget {
  const _AvailableControl({
    required this.featureId,
    required this.value,
    required this.onChanged,
  });

  final String featureId;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Row(
      children: <Widget>[
        Semantics(
          label: '$featureId control',
          child: Switch(value: value, onChanged: onChanged),
        ),
        const SizedBox(width: UamSpacing.sm),
        Text(
          value ? 'On' : 'Off',
          style: UamTypography.navigation.copyWith(color: colors.textPrimary),
        ),
        const Spacer(),
        const CapabilityBadge(label: 'Available', tone: UamStatusTone.success),
      ],
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({
    required this.availability,
    required this.connected,
    required this.permissionAction,
  });

  final CapabilityAvailability availability;
  final bool connected;
  final bool permissionAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final tone = _toneFor(availability);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: UamSpacing.md,
          runSpacing: UamSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            CapabilityBadge(
              label: availability.label,
              tone: tone,
              tooltip: _reason(availability, connected),
            ),
            if (permissionAction)
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.shield_outlined, size: 15),
                label: const Text('Review permission'),
              ),
          ],
        ),
        const SizedBox(height: UamSpacing.sm),
        Text(
          _reason(availability, connected),
          style: UamTypography.micro.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  static String _reason(CapabilityAvailability availability, bool connected) {
    switch (availability) {
      case CapabilityAvailability.disconnected:
        return 'Connect and select a device to evaluate this feature.';
      case CapabilityAvailability.unsupported:
        return 'The device or platform reports this feature as unsupported.';
      case CapabilityAvailability.permissionRequired:
        return 'A platform permission must be granted before UAM can control it.';
      case CapabilityAvailability.unavailableOnPlatform:
        return 'This feature is unavailable on the current platform.';
      case CapabilityAvailability.notImplemented:
        return 'No adapter implements this control in Phase 1.';
      case CapabilityAvailability.unknown:
        return 'The adapter did not report a capability for this feature.';
      case CapabilityAvailability.error:
        return 'The adapter returned an error while reading this feature.';
      case CapabilityAvailability.loading:
        return 'The capability is still being evaluated.';
      case CapabilityAvailability.available:
        return 'Available on the selected device.';
    }
  }

  static UamStatusTone _toneFor(CapabilityAvailability availability) {
    return switch (availability) {
      CapabilityAvailability.available => UamStatusTone.success,
      CapabilityAvailability.permissionRequired ||
      CapabilityAvailability.loading => UamStatusTone.warning,
      CapabilityAvailability.unsupported ||
      CapabilityAvailability.unavailableOnPlatform ||
      CapabilityAvailability.notImplemented => UamStatusTone.planned,
      CapabilityAvailability.error => UamStatusTone.error,
      _ => UamStatusTone.muted,
    };
  }
}

class _SelectedDeviceChip extends StatelessWidget {
  const _SelectedDeviceChip({required this.device});

  final AudioDevice? device;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final connected = device?.isConnected ?? false;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(
        horizontal: UamSpacing.lg,
        vertical: UamSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(UamRadii.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.headphones,
            size: 16,
            color: connected ? colors.accent : colors.textTertiary,
          ),
          const SizedBox(width: UamSpacing.md),
          Text(
            device?.displayName ?? 'No device selected',
            style: UamTypography.navigation.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: UamSpacing.sm),
          UamStatus(
            label: device?.connectionState.label ?? 'Unavailable',
            tone: connected ? UamStatusTone.success : UamStatusTone.muted,
            compact: true,
          ),
        ],
      ),
    );
  }
}
