import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design_system/components/uam_components.dart';
import '../../design_system/theme/uam_theme.dart';
import '../../design_system/tokens/uam_breakpoints.dart';
import '../../design_system/tokens/uam_radii.dart';
import '../../design_system/tokens/uam_spacing.dart';
import '../../design_system/tokens/uam_typography.dart';
import '../../shared/models/audio_device.dart';
import '../router/app_routes.dart';
import '../state/uam_app_controller.dart';

/// Contextual top bar with breadcrumb and selected-device summary.
class UamTopBar extends StatelessWidget {
  const UamTopBar({
    required this.route,
    required this.widthClass,
    required this.onNavigate,
    super.key,
  });

  final String route;
  final UamWidthClass widthClass;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final colors = context.uamColors;
    final isMobile = uamUsesMobileNavigation(widthClass);
    final height = isMobile
        ? UamBreakpoints.topBarMobile
        : UamBreakpoints.topBarDesktop;
    final device = controller.devices.selected;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.canvas.withValues(alpha: 0.86),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? UamSpacing.lg : UamSpacing.pageWide,
            ),
            child: Row(
              children: <Widget>[
                if (isMobile) ...<Widget>[
                  const UamBrandMark(size: 28),
                  const SizedBox(width: UamSpacing.md),
                  Text(
                    'UAM',
                    style: UamTypography.brand.copyWith(
                      fontSize: 14,
                      color: colors.textPrimary,
                    ),
                  ),
                ] else
                  Expanded(child: _Breadcrumb(route: route)),
                if (!isMobile) const SizedBox(width: UamSpacing.xl),
                _DeviceSelector(
                  device: device,
                  compact: isMobile,
                  onTap: () => onNavigate(AppRoutes.deviceManager),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.route});

  final String route;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Row(
      children: <Widget>[
        Text(
          'WORKSPACE',
          style: UamTypography.eyebrow.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(width: UamSpacing.md),
        Icon(Icons.chevron_right, size: 14, color: colors.textTertiary),
        const SizedBox(width: UamSpacing.md),
        Flexible(
          child: Text(
            AppRoutes.labelFor(route),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UamTypography.navigation.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceSelector extends StatelessWidget {
  const _DeviceSelector({
    required this.device,
    required this.compact,
    required this.onTap,
  });

  final AudioDevice? device;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final connected = device?.isConnected ?? false;
    final label = device?.displayName ?? 'No device selected';
    final detail = device == null
        ? 'Device discovery unavailable'
        : device!.connectionState.label;
    final summary = device == null
        ? 'Select an audio device. Device discovery is unavailable in Phase 1.'
        : '$label. $detail.';
    return Tooltip(
      message: summary,
      child: Semantics(
        button: true,
        label: 'Selected device. $summary',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(UamRadii.notice),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? UamSpacing.md : UamSpacing.lg,
                vertical: UamSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(UamRadii.notice),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(
                        UamRadii.smallControl,
                      ),
                    ),
                    child: Icon(
                      Icons.headphones,
                      size: 16,
                      color: connected ? colors.accent : colors.textTertiary,
                    ),
                  ),
                  if (!compact) ...<Widget>[
                    const SizedBox(width: UamSpacing.mdPlus),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UamTypography.navigation.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UamTypography.badge.copyWith(
                            color: connected
                                ? colors.success
                                : colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(width: UamSpacing.xs),
                  Icon(Icons.unfold_more, size: 14, color: colors.textTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
