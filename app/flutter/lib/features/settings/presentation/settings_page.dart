import 'package:flutter/material.dart';

import '../../../app/state/uam_app_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../design_system/components/uam_components.dart';
import '../../../design_system/components/uam_layout.dart';
import '../../../design_system/theme/uam_theme.dart';
import '../../../design_system/tokens/uam_breakpoints.dart';
import '../../../design_system/tokens/uam_radii.dart';
import '../../../design_system/tokens/uam_spacing.dart';
import '../../../design_system/tokens/uam_typography.dart';

/// Settings categories. Only the categories with designed content are active;
/// the remainder render an explicit not-designed state.
enum _SettingsCategory {
  general('General', Icons.tune, implemented: true),
  appearance('Appearance', Icons.palette_outlined, implemented: true),
  audio('Audio', Icons.graphic_eq_outlined),
  devices('Devices', Icons.headphones_outlined),
  permissions('Permissions', Icons.shield_outlined),
  presetManagement('Preset Management', Icons.library_music_outlined),
  storage('Storage', Icons.folder_outlined),
  about('About UAM', Icons.info_outline, implemented: true),
  reset('Reset', Icons.restart_alt, implemented: true);

  const _SettingsCategory(this.label, this.icon, {this.implemented = false});

  final String label;
  final IconData icon;
  final bool implemented;
}

/// Application preferences, appearance, version data, and reset actions.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsCategory _category = _SettingsCategory.general;

  @override
  Widget build(BuildContext context) {
    final controller = UamAppScope.of(context);
    return ListView(
      key: const Key('page-settings'),
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        const UamPageHeader(
          eyebrow: 'Preferences',
          title: 'Settings',
          description:
              'Appearance, general behaviour, version data, and reset. Phase 1 '
              'preferences are held in memory only; nothing is persisted.',
        ),
        const SizedBox(height: UamSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            final navigation = _CategoryNavigation(
              selected: _category,
              horizontal: !wide,
              onSelect: (category) => setState(() => _category = category),
            );
            final content = ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: UamBreakpoints.settingsContent,
              ),
              child: _SettingsContent(
                category: _category,
                controller: controller,
              ),
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  navigation,
                  const SizedBox(height: UamSpacing.xl),
                  content,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: UamBreakpoints.settingsNavigation,
                  child: navigation,
                ),
                const SizedBox(width: UamSpacing.huge),
                Expanded(child: content),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryNavigation extends StatelessWidget {
  const _CategoryNavigation({
    required this.selected,
    required this.horizontal,
    required this.onSelect,
  });

  final _SettingsCategory selected;
  final bool horizontal;
  final ValueChanged<_SettingsCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final category in _SettingsCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: UamSpacing.md),
                child: _CategoryTile(
                  category: category,
                  selected: category == selected,
                  compact: true,
                  onTap: () => onSelect(category),
                ),
              ),
          ],
        ),
      );
    }
    return UamCard(
      padding: const EdgeInsets.all(UamSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final category in _SettingsCategory.values)
            _CategoryTile(
              category: category,
              selected: category == selected,
              compact: false,
              onTap: () => onSelect(category),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _SettingsCategory category;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final foreground = selected ? colors.accent : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 0 : UamSpacing.xs),
        child: Material(
          color: selected ? colors.infoOverlay : Colors.transparent,
          borderRadius: BorderRadius.circular(UamRadii.navigation),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(UamRadii.navigation),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: UamSpacing.lg,
                vertical: UamSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(UamRadii.navigation),
                border: Border.all(
                  color: selected ? colors.accent : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: <Widget>[
                  Icon(category.icon, size: 18, color: foreground),
                  const SizedBox(width: UamSpacing.mdPlus),
                  if (compact)
                    Text(
                      category.label,
                      style: UamTypography.navigation.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        category.label,
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
                  if (!category.implemented && !compact) ...<Widget>[
                    const Spacer(),
                    Icon(
                      Icons.construction_outlined,
                      size: 15,
                      color: colors.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.category, required this.controller});

  final _SettingsCategory category;
  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    return switch (category) {
      _SettingsCategory.general => _GeneralSection(controller: controller),
      _SettingsCategory.appearance => _AppearanceSection(
        controller: controller,
      ),
      _SettingsCategory.about => _AboutSection(controller: controller),
      _SettingsCategory.reset => _ResetSection(controller: controller),
      _ => _NotDesignedSection(category: category),
    };
  }
}

class _GeneralSection extends StatelessWidget {
  const _GeneralSection({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const UamSectionHeader(
                title: 'General',
                subtitle: 'Application behaviour',
              ),
              const SizedBox(height: UamSpacing.lg),
              _SettingRow(
                title: 'Launch at startup',
                description:
                    'A local preference only. No platform auto-start integration '
                    'is active in Phase 1.',
                control: Switch(
                  value: controller.launchAtStartup,
                  onChanged: controller.setLaunchAtStartup,
                ),
              ),
              const _SettingDivider(),
              const _SettingRow(
                title: 'Language',
                description:
                    'Localisation is not implemented. The interface follows the '
                    'system language and ships in English.',
                control: _DisabledSelector(label: 'System default'),
              ),
              const _SettingDivider(),
              const _SettingRow(
                title: 'Close behaviour',
                description:
                    'Window close behaviour is platform-managed and not '
                    'configured in Phase 1.',
                control: _DisabledSelector(label: 'Platform default'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const UamSectionHeader(
                title: 'Appearance',
                subtitle: 'Theme and motion',
              ),
              const SizedBox(height: UamSpacing.lg),
              Text(
                'THEME',
                style: UamTypography.technicalLabel.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: UamSpacing.sm),
              SegmentedButton<UamThemePreference>(
                segments: <ButtonSegment<UamThemePreference>>[
                  for (final preference in UamThemePreference.values)
                    ButtonSegment<UamThemePreference>(
                      value: preference,
                      label: Text(preference.label),
                      icon: Icon(_themeIcon(preference), size: 16),
                    ),
                ],
                selected: <UamThemePreference>{controller.themePreference},
                onSelectionChanged: (selection) =>
                    controller.setThemePreference(selection.first),
              ),
              const _SettingDivider(),
              _SettingRow(
                title: 'Reduced motion',
                description:
                    'Reduces navigation and control transitions. The system '
                    'accessibility preference is always honoured in addition.',
                control: Switch(
                  value: controller.reducedMotion,
                  onChanged: controller.setReducedMotion,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _themeIcon(UamThemePreference preference) =>
      switch (preference) {
        UamThemePreference.system => Icons.brightness_auto_outlined,
        UamThemePreference.dark => Icons.dark_mode_outlined,
        UamThemePreference.light => Icons.light_mode_outlined,
      };
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    final state = controller.engine.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const UamSectionHeader(
                title: 'About UAM',
                subtitle: 'Universe Audio Management',
              ),
              const SizedBox(height: UamSpacing.lg),
              const UamKeyValue(
                label: 'APPLICATION',
                value: AppConstants.productName,
              ),
              const UamKeyValue(
                label: 'APP VERSION',
                value: AppConstants.appVersion,
              ),
              const UamKeyValue(label: 'PHASE', value: 'Phase 1 — Foundation'),
              UamKeyValue(
                label: 'RUST CORE',
                value: state.coreVersion == null
                    ? 'Not reported'
                    : 'v${state.coreVersion}',
                valueColor: state.coreReachable
                    ? colors.success
                    : colors.textTertiary,
              ),
              UamKeyValue(
                label: 'BRIDGE ABI',
                value: state.bridgeAbiVersion == null
                    ? 'Not reported'
                    : '${state.bridgeAbiVersion}',
              ),
              const UamKeyValue(label: 'PRESET SCHEMA', value: 'uam-preset v1'),
              const UamKeyValue(
                label: 'DATA LOCATION',
                value: 'In memory (not persisted)',
              ),
              const SizedBox(height: UamSpacing.md),
              Text(
                'Phase 1 holds configuration in memory. Preset persistence, '
                'device adapters, and audio processing arrive in later phases.',
                style: UamTypography.micro.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResetSection extends StatelessWidget {
  const _ResetSection({required this.controller});

  final UamAppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return UamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const UamSectionHeader(
            title: 'Reset preferences',
            subtitle: 'Danger zone',
          ),
          const SizedBox(height: UamSpacing.lg),
          Text(
            'Resets the in-memory appearance and general preferences for this '
            'session and restores the default equalizer configuration. No '
            'persisted data exists, so nothing on disk is removed.',
            style: UamTypography.description.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: UamSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => _confirmReset(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
            ),
            icon: const Icon(Icons.restart_alt, size: 17),
            label: const Text('Reset preferences'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset preferences'),
        content: const Text(
          'Appearance and general preferences return to their defaults and the '
          'equalizer resets to a flat ten-band configuration. This cannot be '
          'undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      controller.equalizer.reset();
      controller.resetPreferences();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phase 1 preferences were reset.')),
      );
    }
  }
}

class _NotDesignedSection extends StatelessWidget {
  const _NotDesignedSection({required this.category});

  final _SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return UamCard(
      child: UamEmptyState(
        icon: Icons.construction_outlined,
        title: '${category.label} is not designed yet',
        description:
            'The prototype defines the "${category.label}" category in the '
            'navigation but no detail content. Phase 1 shows this explicit '
            'placeholder instead of inventing settings that do not exist.',
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UamSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: UamTypography.cardTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: UamSpacing.xs),
                Text(
                  description,
                  style: UamTypography.description.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: UamSpacing.xl),
          control,
        ],
      ),
    );
  }
}

class _SettingDivider extends StatelessWidget {
  const _SettingDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(color: context.uamColors.border, height: 1);
  }
}

class _DisabledSelector extends StatelessWidget {
  const _DisabledSelector({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.uamColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(
        horizontal: UamSpacing.lg,
        vertical: UamSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.insetPanel,
        borderRadius: BorderRadius.circular(UamRadii.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: UamTypography.navigation.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: UamSpacing.sm),
          Icon(Icons.lock_outline, size: 14, color: colors.textTertiary),
        ],
      ),
    );
  }
}
