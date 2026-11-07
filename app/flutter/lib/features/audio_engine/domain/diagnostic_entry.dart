/// One runtime diagnostic entry. Never contains device identifiers, paths, or
/// audio content.
final class DiagnosticEntry {
  const DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String message;

  String get formattedTime {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:'
        '${two(timestamp.second)}';
  }
}

/// Severity of a diagnostic entry.
enum DiagnosticLevel { info, notice, error }
