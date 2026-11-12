/// Where a preset came from.
enum PresetSource {
  /// Shipped with UAM. Immutable: cannot be deleted or overwritten.
  builtin('builtin'),

  /// Added by importing a portable `.uam-preset.json` file.
  imported('imported'),

  /// Created inside UAM from the equalizer editor.
  user('user');

  const PresetSource(this.wireName);

  /// Stable identifier stored in the database `presets.source` column.
  final String wireName;

  static PresetSource fromWire(String value) {
    for (final source in values) {
      if (source.wireName == value) {
        return source;
      }
    }
    return PresetSource.user;
  }
}
