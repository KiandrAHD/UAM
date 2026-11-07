import 'dart:typed_data';

/// Metadata and bytes for a preset file the user explicitly chose to share.
///
/// Phase 0 defines the boundary only; no platform share sheet is wired. File
/// bytes come from validated `.uam-preset.json` export, never from an arbitrary
/// path or unvalidated import.
final class PresetFileExport {
  const PresetFileExport({required this.fileName, required this.utf8Bytes});

  /// Suggested file name ending in `.uam-preset.json`.
  final String fileName;

  /// UTF-8 encoded validated preset document.
  final Uint8List utf8Bytes;

  /// MIME type for platform share/file chooser integrations.
  String get mimeType => 'application/json';
}
