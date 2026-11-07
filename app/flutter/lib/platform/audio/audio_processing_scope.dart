/// Audio processing scope reported by the core and displayed by the UI.
///
/// These labels mirror the architecture contract. Phase 0 always reports
/// [configurationOnly].
enum AudioProcessingScope {
  /// UAM processes audio that UAM itself generates or plays.
  appOwnedStream('app_owned_stream', 'App-owned stream'),

  /// UAM processes a supported selected stream.
  selectedStream('selected_stream', 'Selected stream'),

  /// UAM processes system output through a supported integration.
  systemOutput('system_output', 'System output'),

  /// UAM edits configuration but is not attached to a processing path.
  configurationOnly('configuration_only', 'Configuration only');

  const AudioProcessingScope(this.wireName, this.label);

  /// Stable identifier exchanged with the Rust core.
  final String wireName;

  /// User-facing label.
  final String label;

  /// Parse a wire identifier, returning null for unknown values.
  static AudioProcessingScope? tryParse(String value) {
    for (final scope in values) {
      if (scope.wireName == value) {
        return scope;
      }
    }
    return null;
  }

  /// Parse a wire identifier, throwing for unknown values so callers cannot
  /// silently overstate capability.
  static AudioProcessingScope fromWireName(String value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('Unknown audio processing scope "$value"');
    }
    return parsed;
  }
}
