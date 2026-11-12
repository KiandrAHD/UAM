import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/database/database_exception.dart';

/// Atomic file writing used for preset export and backup containers.
///
/// The bytes are always written to a sibling temporary file first and then
/// renamed over the destination, so a crash or a full disk cannot leave a
/// half-written user file behind.
abstract final class AtomicFileWriter {
  /// Write [bytes] to [destinationPath] atomically.
  ///
  /// Throws [UamDataException] with `permissionDenied` or `unknown` when the
  /// destination cannot be written. Any temporary file is removed.
  static Future<void> writeBytes(
    String destinationPath,
    List<int> bytes,
  ) async {
    final destination = File(destinationPath);
    final directory = destination.parent;
    if (!await directory.exists()) {
      try {
        await directory.create(recursive: true);
      } on FileSystemException catch (error) {
        throw _mapFileSystemError(error, destinationPath);
      }
    }
    final temp = File(
      p.join(
        directory.path,
        '.${p.basename(destinationPath)}.uam-tmp-'
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(destinationPath);
    } on FileSystemException catch (error) {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } on FileSystemException {
          // Cleanup failure must not mask the original write error.
        }
      }
      throw _mapFileSystemError(error, destinationPath);
    }
  }

  /// Read at most [maxBytes] from [path].
  ///
  /// Reading is bounded before allocation so a huge or hostile file cannot be
  /// loaded into memory.
  static Future<List<int>> readBounded(
    String path, {
    required int maxBytes,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const UamDataException(
        UamDataErrorCode.fileNotFound,
        'The selected file no longer exists.',
      );
    }
    try {
      final length = await file.length();
      if (length > maxBytes) {
        throw UamDataException(
          UamDataErrorCode.corruptData,
          'The file is ${_formatBytes(length)}, above the '
          '${_formatBytes(maxBytes)} limit.',
        );
      }
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      throw _mapFileSystemError(error, path);
    }
  }

  static UamDataException _mapFileSystemError(
    FileSystemException error,
    String path,
  ) {
    final code = error.osError?.errorCode;
    final isPermission =
        code == 5 || code == 13 || code == 1 || code == 21 || code == 32;
    return UamDataException(
      isPermission
          ? UamDataErrorCode.permissionDenied
          : UamDataErrorCode.unknown,
      isPermission
          ? 'UAM is not allowed to write or read that location.'
          : 'The file operation could not be completed.',
      cause: error,
    );
  }

  static String _formatBytes(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB'
      : '${(bytes / 1024).toStringAsFixed(1)} KiB';
}
