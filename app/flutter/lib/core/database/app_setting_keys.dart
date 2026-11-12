/// Stable keys stored in the `app_settings` table.
///
/// Keys are namespaced so a settings reset can target a prefix and so preset
/// state can live in the same key/value table without collisions.
abstract final class AppSettingKeys {
  /// Appearance theme: `system`, `dark`, or `light`.
  static const String themeMode = 'appearance.themeMode';

  /// Reduced-motion preference, a JSON boolean.
  static const String reducedMotion = 'appearance.reducedMotion';

  /// Launch-at-startup preference, a JSON boolean.
  static const String launchAtStartup = 'general.launchAtStartup';

  /// Identifier of the currently active preset, or removed when none.
  static const String activePresetId = 'preset.activeId';

  /// RFC 3339 timestamp of the last user-initiated backup.
  static const String lastBackupAt = 'backup.lastBackupAt';

  /// Display path of the last user-initiated backup file (non-sensitive).
  static const String lastBackupPath = 'backup.lastBackupPath';

  /// Internal: applied built-in seed policy version.
  static const String builtinSeedVersion = 'internal.builtinSeedVersion';

  /// Prefix reserved for internal bookkeeping keys excluded from user backups.
  static const String internalPrefix = 'internal.';

  /// Prefix for every appearance key.
  static const String appearancePrefix = 'appearance.';

  /// Prefix for every general key.
  static const String generalPrefix = 'general.';
}
