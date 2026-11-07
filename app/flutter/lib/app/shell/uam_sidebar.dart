import 'package:flutter/material.dart';

import '../../design_system/components/uam_components.dart';
import '../../design_system/theme/uam_theme.dart';
import '../../design_system/tokens/uam_breakpoints.dart';
import '../../design_system/tokens/uam_colors.dart';
import '../../design_system/tokens/uam_radii.dart';
import '../../design_system/tokens/uam_spacing.dart';
import '../../design_system/tokens/uam_typography.dart';
import '../../shared/models/engine_runtime_state.dart';
import '../state/uam_app_controller.dart';
import 'uam_destinations.dart';

/// Persistent desktop and tablet navigation.
class UamSidebar extends StatelessWidget {
  const UamSidebar({
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
    final colors = context.uamColors;
    final isTablet = widthClass == UamWidthClass.tablet;
    final width = isTablet
        ? UamBreakpoints.sidebarTablet
        : UamBreakpoints.sidebarDesktop;
    final productDestinations = UamDestination.values
        .where((destination) => destination != UamDestination.settings)
        .toList(growable: false);

    return Container(
      key: const Key('uam-sidebar'),
      width: width,
      decoration: BoxDecoration(
        color: colors.canvasSecondary.withValues(alpha: 0.78),
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: UamBreakpoints.topBarDesktop,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? UamSpacing.lg : UamSpacing.xxl,
              ),
              child: Row(
                mainAxisAlignment: isTablet
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: <Widget>[
                  UamBrandMark(size: isTablet ? 30 : 38),
                  if (!isTablet) ...<Widget>[
                    const SizedBox(width: UamSpacing.mdPlus),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            'UAM',
                            style: UamTypography.brand.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'UNIVERSE AUDIO',
                            style: UamTypography.badge.copyWith(
                              color: colors.textTertiary,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: UamSpacing.md,
                vertical: UamSpacing.md,
              ),
              children: <Widget>[
                for (final destination in productDestinations)
                  _SidebarItem(
                    destination: destination,
                    selected: route == destination.route,
                    compact: isTablet,
                    onTap: () => onNavigate(destination.route),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: UamSpacing.md,
                    horizontal: UamSpacing.sm,
                  ),
                  child: Divider(color: colors.border, height: 1),
                ),
                _SidebarItem(
                  destination: UamDestination.settings,
                  selected: route == UamDestination.settings.route,
                  compact: isTablet,
                  onTap: () => onNavigate(UamDestination.settings.route),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(UamSpacing.md),
            child: isTablet
                ? const _CompactCoreHealth()
                : const _CoreHealthCard(),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final UamDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final foreground = selected ? colors.accent : colors.textSecondary;
    final item = Semantics(
      button: true,
      selected: selected,
      label: '${destination.label}${selected ? ', current page' : ''}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: UamSpacing.xs),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(UamRadii.navigation),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                gradient: selected
                    ? LinearGradient(
                        colors: <Color>[
                          colors.accent.withValues(alpha: 0.16),
                          colors.accent.withValues(alpha: 0.04),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(UamRadii.navigation),
                border: Border.all(
                  color: selected
                      ? colors.accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
              ),
              child: Stack(
                children: <Widget>[
                  if (selected)
                    Positioned(
                      left: 0,
                      top: 10,
                      child: Container(
                        width: 3,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: colors.accent.withValues(alpha: 0.8),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? UamSpacing.md : UamSpacing.lg,
                      vertical: UamSpacing.md,
                    ),
                    child: Row(
                      mainAxisAlignment: compact
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          selected
                              ? destination.selectedIcon
                              : destination.icon,
                          size: 19,
                          color: foreground,
                        ),
                        if (!compact) ...<Widget>[
                          const SizedBox(width: UamSpacing.mdPlus),
                          Expanded(
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: UamTypography.navigation.copyWith(
                                color: selected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (destination == UamDestination.deviceManager)
                            _ConnectionDot(
                              connected:
                                  UamAppScope.of(
                                    context,
                                  ).devices.selected?.isConnected ??
                                  false,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!compact) {
      return item;
    }
    return Tooltip(message: destination.label, child: item);
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Semantics(
      label: connected ? 'Device connected' : 'No device connected',
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: connected ? colors.success : colors.textTertiary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _CoreHealthCard extends StatelessWidget {
  const _CoreHealthCard();

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final colors = context.uamColors;
    final state = controller.engine.state;
    final (statusLabel, tone) = _status(state, controller.engine.isLoading);
    return Container(
      padding: const EdgeInsets.all(UamSpacing.mdPlus),
      decoration: BoxDecoration(
        color: colors.coreStatusWell,
        borderRadius: BorderRadius.circular(UamRadii.notice),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              UamStatus(label: statusLabel, tone: tone, compact: true),
              const Spacer(),
              Icon(Icons.memory, size: 14, color: colors.textTertiary),
            ],
          ),
          const SizedBox(height: UamSpacing.sm),
          Text(
            'UAM CORE',
            style: UamTypography.technicalLabel.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            state.coreVersion == null
                ? 'Version not reported'
                : 'v${state.coreVersion}',
            style: UamTypography.monospace.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactCoreHealth extends StatelessWidget {
  const _CompactCoreHealth();

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    final colors = context.uamColors;
    final state = controller.engine.state;
    final (statusLabel, tone) = _status(state, controller.engine.isLoading);
    final color = colors.statusColor(tone);
    return Tooltip(
      message:
          'UAM Core: $statusLabel'
          '${state.coreVersion == null ? '' : ', v${state.coreVersion}'}',
      child: Semantics(
        label: 'UAM Core: $statusLabel',
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.coreStatusWell,
            borderRadius: BorderRadius.circular(UamRadii.notice),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

(String, UamStatusTone) _status(EngineRuntimeState state, bool loading) {
  if (loading) {
    return ('Checking', UamStatusTone.info);
  }
  if (state.status == EngineProcessingStatus.error) {
    return ('Unavailable', UamStatusTone.error);
  }
  if (state.coreReachable) {
    return ('Reachable', UamStatusTone.success);
  }
  return ('Unknown', UamStatusTone.muted);
}
