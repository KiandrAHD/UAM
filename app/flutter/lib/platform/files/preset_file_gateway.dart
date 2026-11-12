import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// A file the user picked for import.
final class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.path});

  final String name;
  final Uint8List bytes;

  /// Absolute path on desktop platforms; null on mobile where only a
  /// security-scoped copy is exposed.
  final String? path;
}

/// Platform file selection and saving.
///
/// Production uses `file_selector`, which maps to native open/save dialogs on
/// Windows, macOS, and Linux and to the system document picker on Android and
/// iOS. Tests inject a fake so no platform channel is required.
abstract interface class PresetFileGateway {
  /// Let the user pick one preset file. Returns null when cancelled.
  Future<PickedFile?> pickPresetFile();

  /// Let the user pick one backup container. Returns null when cancelled.
  Future<PickedFile?> pickBackupFile();

  /// Ask where to save a preset and write [bytes]. Returns the path, or null
  /// when the user cancelled.
  Future<String?> savePresetFile({
    required String suggestedName,
    required Uint8List bytes,
  });

  /// Ask where to save a backup and write [bytes]. Returns the path, or null
  /// when the user cancelled.
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  });
}

/// `file_selector` backed gateway.
final class NativePresetFileGateway implements PresetFileGateway {
  const NativePresetFileGateway();

  static const List<String> _presetExtensions = <String>['json'];
  static const List<String> _backupExtensions = <String>['uam-backup'];

  @override
  Future<PickedFile?> pickPresetFile() async {
    const group = XTypeGroup(
      label: 'UAM preset',
      extensions: _presetExtensions,
      uniformTypeIdentifiers: <String>['public.json'],
      mimeTypes: <String>['application/json'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null) {
      return null;
    }
    return PickedFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      path: file.path.isEmpty ? null : file.path,
    );
  }

  @override
  Future<PickedFile?> pickBackupFile() async {
    const group = XTypeGroup(
      label: 'UAM backup',
      extensions: _backupExtensions,
      mimeTypes: <String>['application/json'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null) {
      return null;
    }
    return PickedFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      path: file.path.isEmpty ? null : file.path,
    );
  }

  @override
  Future<String?> savePresetFile({
    required String suggestedName,
    required Uint8List bytes,
  }) => _save(
    suggestedName: suggestedName,
    bytes: bytes,
    extensions: _presetExtensions,
  );

  @override
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  }) => _save(
    suggestedName: suggestedName,
    bytes: bytes,
    extensions: _backupExtensions,
  );

  Future<String?> _save({
    required String suggestedName,
    required Uint8List bytes,
    required List<String> extensions,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: 'UAM file', extensions: extensions),
      ],
    );
    if (location == null) {
      return null;
    }
    final file = XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: 'application/json',
    );
    await file.saveTo(location.path);
    return location.path;
  }
}
