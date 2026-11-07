import 'package:flutter/material.dart';

import '../theme/uam_theme.dart';
import '../tokens/uam_colors.dart';
import '../tokens/uam_spacing.dart';
import '../tokens/uam_typography.dart';

/// Standard page heading: eyebrow, title, description, and actions.
class UamPageHeader extends StatelessWidget {
  const UamPageHeader({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.actions = const <Widget>[],
    super.key,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width <= 760;
    final compact = width <= 390;
    final titleStyle =
        (isMobile ? UamTypography.pageTitleMobile : UamTypography.pageTitle)
            .copyWith(color: colors.textPrimary);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          eyebrow.toUpperCase(),
          style: UamTypography.eyebrow.copyWith(color: colors.accent),
        ),
        const SizedBox(height: UamSpacing.xs),
        Text(
          title,
          style: titleStyle.copyWith(
            fontSize: compact ? 22 : titleStyle.fontSize,
          ),
        ),
        const SizedBox(height: UamSpacing.sm),
        Text(
          description,
          style: UamTypography.description.copyWith(
            color: colors.textSecondary,
            fontSize: isMobile ? 11 : 12,
          ),
        ),
      ],
    );
    if (actions.isEmpty) {
      return heading;
    }
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          heading,
          const SizedBox(height: UamSpacing.lg),
          Wrap(
            spacing: UamSpacing.md,
            runSpacing: UamSpacing.md,
            children: actions,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: heading),
        const SizedBox(width: UamSpacing.xl),
        Wrap(
          spacing: UamSpacing.md,
          runSpacing: UamSpacing.md,
          alignment: WrapAlignment.end,
          children: actions,
        ),
      ],
    );
  }
}

/// Section heading inside a page.
class UamSectionHeader extends StatelessWidget {
  const UamSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: UamTypography.sectionTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: UamTypography.description.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: UamSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

/// Compact label/value pair used in technical cards.
class UamKeyValue extends StatelessWidget {
  const UamKeyValue({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: UamSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: UamTypography.technicalLabel.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: UamSpacing.md),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style:
                  valueStyle ??
                  UamTypography.numeric.copyWith(
                    color: valueColor ?? colors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small metric tile used in the Audio Engine grid.
class UamMetricTile extends StatelessWidget {
  const UamMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tone = UamStatusTone.muted,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final UamStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final color = colors.statusColor(tone);
    return Container(
      padding: const EdgeInsets.all(UamSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(height: UamSpacing.md),
          Text(
            label.toUpperCase(),
            style: UamTypography.technicalLabel.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: UamSpacing.xs),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: UamTypography.cardTitle.copyWith(color: colors.textPrimary),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              caption!,
              style: UamTypography.micro.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Responsive grid helper with a fixed minimum tile width.
class UamResponsiveGrid extends StatelessWidget {
  const UamResponsiveGrid({
    required this.children,
    required this.minTileWidth,
    this.spacing = UamSpacing.lgPlus,
    this.runSpacing = UamSpacing.lgPlus,
    super.key,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxColumns = children.length;
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(
          1,
          maxColumns,
        );
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: <Widget>[
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
