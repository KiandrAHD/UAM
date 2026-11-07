import 'package:flutter/material.dart';

import '../../design_system/theme/uam_theme.dart';
import '../../design_system/tokens/uam_breakpoints.dart';
import '../../design_system/tokens/uam_radii.dart';
import '../../design_system/tokens/uam_spacing.dart';
import '../../design_system/tokens/uam_typography.dart';
import '../router/app_routes.dart';
import 'uam_destinations.dart';

/// Touch-oriented bottom navigation and secondary navigation sheet.
class UamMobileNavigation extends StatelessWidget {
  const UamMobileNavigation({
    required this.route,
    required this.onNavigate,
    super.key,
  });

  final String route;
  final ValueChanged<String> onNavigate;

  bool get _secondaryActive =>
      UamDestination.secondaryMobile.any((item) => item.route == route);

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const Key('uam-mobile-nav'),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: colors.canvasSecondary.withValues(alpha: 0.97),
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SizedBox(
        height: UamBreakpoints.bottomNavigation,
        child: Row(
          children: <Widget>[
            for (final destination in UamDestination.primaryMobile)
              Expanded(
                child: _DestinationTile(
                  label: destination.shortLabel,
                  icon: route == destination.route
                      ? destination.selectedIcon
                      : destination.icon,
                  selected: route == destination.route,
                  onTap: () => onNavigate(destination.route),
                  semanticLabel: destination.label,
                ),
              ),
            Expanded(
              child: _DestinationTile(
                label: 'More',
                icon: _secondaryActive
                    ? Icons.more_horiz
                    : Icons.more_horiz_outlined,
                selected: _secondaryActive,
                onTap: () => _openMoreSheet(context),
                semanticLabel: 'More destinations',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMoreSheet(BuildContext context) async {
    final colors = context.uamColors;
    final selected = await showModalBottomSheet<UamDestination>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.all(UamSpacing.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(UamRadii.modal),
            border: Border.all(color: colors.borderEmphasis),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.modalShadow.withValues(alpha: 0.45),
                blurRadius: 50,
                offset: const Offset(0, -15),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(UamSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.borderEmphasis,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: UamSpacing.xl),
                  Text(
                    'MORE',
                    style: UamTypography.eyebrow.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: UamSpacing.xs),
                  Text(
                    'Secondary destinations',
                    style: UamTypography.sectionTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: UamSpacing.lg),
                  for (final destination in UamDestination.secondaryMobile)
                    _SecondarySheetTile(
                      destination: destination,
                      selected: route == destination.route,
                      onTap: () => Navigator.of(sheetContext).pop(destination),
                    ),
                  if (route == AppRoutes.settings)
                    Padding(
                      padding: const EdgeInsets.only(top: UamSpacing.md),
                      child: Text(
                        'Settings is open',
                        style: UamTypography.micro.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      onNavigate(selected.route);
    }
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: UamSpacing.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.7),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: UamSpacing.sm),
              Icon(
                icon,
                size: 21,
                color: selected ? colors.accent : colors.textSecondary,
              ),
              const SizedBox(height: UamSpacing.xxs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UamTypography.badge.copyWith(
                  color: selected ? colors.textPrimary : colors.textTertiary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondarySheetTile extends StatelessWidget {
  const _SecondarySheetTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final UamDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: UamSpacing.sm),
      child: Material(
        color: selected ? colors.infoOverlay : Colors.transparent,
        borderRadius: BorderRadius.circular(UamRadii.notice),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(UamRadii.notice),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: UamSpacing.lg,
              vertical: UamSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(UamRadii.notice),
              border: Border.all(
                color: selected ? colors.accent : colors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: selected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: UamSpacing.mdPlus),
                Expanded(
                  child: Text(
                    destination.label,
                    style: UamTypography.navigation.copyWith(
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
