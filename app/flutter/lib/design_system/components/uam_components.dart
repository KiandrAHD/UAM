import 'package:flutter/material.dart';

import '../../design_system/theme/uam_theme.dart';
import '../../design_system/tokens/uam_colors.dart';
import '../../design_system/tokens/uam_radii.dart';
import '../../design_system/tokens/uam_spacing.dart';
import '../../design_system/tokens/uam_typography.dart';

/// Shared dark-surface card.
class UamCard extends StatelessWidget {
  const UamCard({
    required this.child,
    this.padding,
    this.selected = false,
    this.disabled = false,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final compact = context.uamIsCompact;
    final content = Padding(
      padding:
          padding ?? EdgeInsets.all(compact ? UamSpacing.xl : UamSpacing.xxl),
      child: child,
    );
    final decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            (selected ? colors.surfaceSecondary : colors.surface).withValues(
              alpha: disabled ? 0.55 : 0.98,
            ),
            colors.surface.withValues(alpha: disabled ? 0.55 : 0.98),
          ],
        ),
        borderRadius: BorderRadius.circular(UamRadii.card),
        border: Border.all(
          color: selected ? colors.accent : colors.border,
          width: selected ? 1.25 : 1,
        ),
      ),
      child: content,
    );
    if (onTap == null || disabled) {
      return Semantics(label: semanticLabel, child: decorated);
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(UamRadii.card),
          onTap: onTap,
          child: decorated,
        ),
      ),
    );
  }
}

/// Compact semantic status dot and label.
class UamStatus extends StatelessWidget {
  const UamStatus({
    required this.label,
    required this.tone,
    this.compact = false,
    super.key,
  });

  final String label;
  final UamStatusTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final color = colors.statusColor(tone);
    return Semantics(
      label: 'Status: $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: tone == UamStatusTone.success
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          SizedBox(width: compact ? UamSpacing.xs : UamSpacing.sm),
          Text(
            label.toUpperCase(),
            style: UamTypography.badge.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Non-actionable capability state label.
class CapabilityBadge extends StatelessWidget {
  const CapabilityBadge({
    required this.label,
    required this.tone,
    this.tooltip,
    super.key,
  });

  final String label;
  final UamStatusTone tone;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final color = colors.statusColor(tone);
    final badge = Semantics(
      label: tooltip == null ? label : '$label. $tooltip',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(UamRadii.badge),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label.toUpperCase(),
          style: UamTypography.badge.copyWith(color: color),
        ),
      ),
    );
    return tooltip == null ? badge : Tooltip(message: tooltip!, child: badge);
  }
}

/// Page-level status message.
class UamNotice extends StatelessWidget {
  const UamNotice({
    required this.message,
    required this.tone,
    this.title,
    this.action,
    super.key,
  });

  final String message;
  final UamStatusTone tone;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final color = colors.statusColor(tone);
    final overlay = switch (tone) {
      UamStatusTone.success => colors.successOverlay,
      UamStatusTone.warning => colors.warningOverlay,
      UamStatusTone.error => colors.errorOverlay,
      UamStatusTone.info => colors.infoOverlay,
      UamStatusTone.planned => colors.plannedOverlay,
      UamStatusTone.muted => colors.surfaceSecondary,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(UamSpacing.lg),
        decoration: BoxDecoration(
          color: overlay,
          borderRadius: BorderRadius.circular(UamRadii.notice),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(_iconFor(tone), size: 18, color: color),
            const SizedBox(width: UamSpacing.mdPlus),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title != null) ...<Widget>[
                    Text(
                      title!,
                      style: UamTypography.cardTitle.copyWith(color: color),
                    ),
                    const SizedBox(height: UamSpacing.xs),
                  ],
                  Text(
                    message,
                    style: UamTypography.description.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(width: UamSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(UamStatusTone value) => switch (value) {
    UamStatusTone.success => Icons.check_circle_outline,
    UamStatusTone.warning => Icons.warning_amber_rounded,
    UamStatusTone.error => Icons.error_outline,
    UamStatusTone.info => Icons.info_outline,
    UamStatusTone.planned => Icons.schedule_outlined,
    UamStatusTone.muted => Icons.info_outline,
  };
}

/// Official UAM artwork used everywhere the app presents its identity.
class UamBrandMark extends StatelessWidget {
  const UamBrandMark({this.size = 38, super.key});

  static const String assetPath = 'assets/branding/uam_logo.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Universe Audio Management',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(assetPath, fit: BoxFit.contain),
      ),
    );
  }
}

/// Icon button with desktop tooltip and a 44dp semantic target.
class UamIconButton extends StatelessWidget {
  const UamIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Tooltip(
      message: label,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon),
        color: selected ? colors.accent : colors.textSecondary,
        style: IconButton.styleFrom(
          backgroundColor: selected ? colors.infoOverlay : Colors.transparent,
          minimumSize: const Size(44, 44),
        ),
      ),
    );
  }
}

/// Empty state with explicit explanatory copy.
class UamEmptyState extends StatelessWidget {
  const UamEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Semantics(
      label: '$title. $description',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UamSpacing.xxl,
          vertical: UamSpacing.empty,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 32, color: colors.textTertiary),
                const SizedBox(height: UamSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: UamTypography.sectionTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: UamSpacing.md),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: UamTypography.description.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: UamSpacing.xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
