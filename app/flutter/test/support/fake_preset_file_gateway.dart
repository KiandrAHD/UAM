import 'dart:typed_data';

import 'package:uam/platform/files/preset_file_gateway.dart';

/// In-memory file gateway for widget tests.
///
/// No platform channel is touched. Tests control exactly what the picker
/// returns and capture what the save dialog would have written.
final class FakePresetFileGateway implements PresetFileGateway {
  FakePresetFileGateway({this.presetFile, this.backupFile});

  /// Bytes returned by [pickPresetFile]; null simulates the user cancelling.
  PickedFile? presetFile;

  /// Bytes returned by [pickBackupFile]; null simulates a cancel.
  PickedFile? backupFile;

  /// Name of the last saved file, or null when nothing was saved.
  String? lastSavedPresetName;
  String? lastSavedBackupName;
  Uint8List? lastSavedPresetBytes;
  Uint8List? lastSavedBackupBytes;

  /// When set, saving fails with this message.
  String? saveFailure;

  /// Absolute path the fake claims to have written, when saving succeeds.
  String saveDirectory = 'C:/fake-uam-tests';

  @override
  Future<PickedFile?> pickPresetFile() async => presetFile;

  @override
  Future<PickedFile?> pickBackupFile() async => backupFile;

  @override
  Future<String?> savePresetFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    final failure = saveFailure;
    if (failure != null) {
      throw StateError(failure);
    }
    lastSavedPresetName = suggestedName;
    lastSavedPresetBytes = bytes;
    return '$saveDirectory/$suggestedName';
  }

  @override
  Future<String?> saveBackupFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    final failure = saveFailure;
    if (failure != null) {
      throw StateError(failure);
    }
    lastSavedBackupName = suggestedName;
    lastSavedBackupBytes = bytes;
    return '$saveDirectory/$suggestedName';
  }
}
