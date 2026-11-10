/// SFTP Service - SSH File Transfer Protocol implementation.
///
/// Uses dartssh2 library for SSH connections and SFTP operations.
/// Download uses pipelined downloadToRandomAccess() with a stall watchdog.
/// Upload uses sequential writeBytes() with 256KB chunks for throughput.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/connection_model.dart';
import '../models/file_item_model.dart';
import 'native_sftp.dart';
import 'ssh_service.dart';

/// SFTP service implementation using dartssh2 library
class SFTPService {
  static const Duration _stallTimeout = Duration(seconds: 60);

  SSHClient? _sshClient;
  SftpClient? _sftpClient;
  ConnectionModel? _connection;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  ConnectionModel? get connection => _connection;

  /// Connect to SFTP server (auth + handshake retry via [openSshClient])
  Future<bool> connect(ConnectionModel connection) async {
    try {
      _connection = connection;
      _sshClient = await openSshClient(connection);
      _sftpClient = await _sshClient!.sftp();
      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('SFTP Connection Error: $e');
      _sshClient?.close();
      _sshClient = null;
      _isConnected = false;
      return false;
    }
  }

  /// Disconnect from SFTP server
  Future<void> disconnect() async {
    try {
      _sftpClient?.close();
      _sshClient?.close();
    } catch (e) {
      debugPrint('SFTP Disconnect Error: $e');
    } finally {
      _isConnected = false;
      _sftpClient = null;
      _sshClient = null;
      _connection = null;
    }
  }

  /// List directory contents
  Future<List<FileItemModel>> listDirectory(String path) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final items = await _sftpClient!.listdir(path);

      List<FileItemModel> fileItems = [];

      for (var item in items) {
        // Skip . and .. directories
        if (item.filename == '.' || item.filename == '..') continue;

        final isDir = item.attr.isDirectory;

        fileItems.add(
          FileItemModel(
            name: item.filename,
            path: '$path/${item.filename}',
            size: item.attr.size ?? 0,
            isDirectory: isDir,
            modifiedDate: item.attr.modifyTime != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    item.attr.modifyTime! * 1000,
                  )
                : null,
            permissions: null, // permissions not available in SftpFileAttrs
          ),
        );
      }

      return fileItems;
    } catch (e) {
      debugPrint('SFTP List Directory Error: $e');
      throw Exception('Failed to list directory: $e');
    }
  }

  /// Create directory
  Future<bool> createDirectory(String path, String name) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final fullPath = '$path/$name';
      await _sftpClient!.mkdir(fullPath);
      return true;
    } catch (e) {
      debugPrint('SFTP Create Directory Error: $e');
      return false;
    }
  }

  /// Create an empty file on the server
  Future<bool> createFile(String path, String name) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final fullPath = '$path/$name';
      final file = await _sftpClient!.open(
        fullPath,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      await file.close();
      return true;
    } catch (e) {
      debugPrint('SFTP Create File Error: $e');
      return false;
    }
  }

  /// Rename file/folder
  Future<bool> rename(String oldPath, String newPath) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      await _sftpClient!.rename(oldPath, newPath);
      return true;
    } catch (e) {
      debugPrint('SFTP Rename Error: $e');
      return false;
    }
  }

  /// Delete file
  Future<bool> deleteFile(String path) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      await _sftpClient!.remove(path);
      return true;
    } catch (e) {
      debugPrint('SFTP Delete File Error: $e');
      return false;
    }
  }

  /// Delete directory
  Future<bool> deleteDirectory(String path) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      await _sftpClient!.rmdir(path);
      return true;
    } catch (e) {
      debugPrint('SFTP Delete Directory Error: $e');
      return false;
    }
  }

  /// Download file with pipelined random-access reads.
  ///
  /// Chunks are written at their own offset, so out-of-order replies and
  /// short reads are handled. A watchdog aborts the transfer if no data
  /// arrives for [_stallTimeout] instead of hanging forever.
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    Function(int, int)? onProgress,
    bool Function()? isCancelled,
    bool resume = false,
  }) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    // On Android stream natively: dartssh2 buffers on the Dart heap and
    // runs out of memory on large files.
    if (NativeSftp.isSupported) {
      final bytes = await NativeSftp.download(
        connection: _connection!,
        remotePath: remotePath,
        localPath: localPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
        resume: resume,
      );
      debugPrint('[SFTP] Native download complete: $bytes bytes');
      return true;
    }

    final localFile = File(localPath);

    // Ensure parent directory exists
    final parentDir = localFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // Get file size first
    final stat = await _sftpClient!.stat(remotePath);
    final fileSize = stat.size ?? 0;
    debugPrint('[SFTP] Download: $remotePath ($fileSize bytes)');

    if (fileSize == 0) {
      await localFile.writeAsBytes(const []);
      return true;
    }

    final remoteFile = await _sftpClient!.open(
      remotePath,
      mode: SftpFileOpenMode.read,
    );
    final raf = await localFile.open(mode: FileMode.write);

    int received = 0;
    DateTime lastData = DateTime.now();
    DateTime lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
    final abort = Completer<void>();

    // Watchdog: cancellation and stall detection
    final watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (abort.isCompleted) return;
      if (isCancelled != null && isCancelled()) {
        abort.completeError(Exception('Cancelled'));
      } else if (DateTime.now().difference(lastData) > _stallTimeout) {
        abort.completeError(
          Exception(
            'Transfer stalled: no data for ${_stallTimeout.inSeconds}s '
            'at ${(received * 100 / fileSize).toStringAsFixed(0)}%',
          ),
        );
      }
    });

    try {
      final download = remoteFile.downloadToRandomAccess(
        raf,
        length: fileSize,
        onProgress: (bytesRead) {
          received = bytesRead;
          final now = DateTime.now();
          lastData = now;
          if (onProgress != null &&
              now.difference(lastProgress).inMilliseconds >= 200) {
            lastProgress = now;
            onProgress(bytesRead, fileSize);
          }
        },
      );
      // Abandoned reads must not surface as unhandled errors after abort
      download.ignore();
      await Future.any([download, abort.future]);

      onProgress?.call(fileSize, fileSize);
      debugPrint('[SFTP] Download complete: $received bytes');
      return true;
    } catch (e) {
      debugPrint('[SFTP] Download error: $e');
      rethrow;
    } finally {
      watchdog.cancel();
      if (!abort.isCompleted) abort.complete();
      try {
        await remoteFile.close();
      } catch (_) {}
      try {
        await raf.close();
      } catch (_) {}
    }
  }

  /// Copy a file on the server with `cp` over SSH, so no data passes
  /// through the device. Returns false if the server refuses command
  /// execution (e.g. SFTP-only accounts) so the caller can fall back.
  Future<bool> copyFileOnServer(String sourcePath, String destPath) async {
    if (!_isConnected || _sshClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final session = await _sshClient!.execute(
        'cp -- ${_shellQuote(sourcePath)} ${_shellQuote(destPath)}',
      );
      final stderr = StringBuffer();
      session.stdout.drain<void>();
      session.stderr.listen((d) => stderr.write(String.fromCharCodes(d)));
      await session.done;

      if (session.exitCode == 0) return true;
      if (session.exitCode == null) {
        // Server sent no exit status; verify by comparing sizes
        final src = await _sftpClient!.stat(sourcePath);
        final dst = await _sftpClient!.stat(destPath);
        return src.size != null && src.size == dst.size;
      }
      debugPrint('[SFTP] Server copy failed (${session.exitCode}): $stderr');
      return false;
    } catch (e) {
      debugPrint('[SFTP] Server copy unavailable: $e');
      return false;
    }
  }

  static String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Upload file
  Future<bool> uploadFile({
    required String localPath,
    required String remotePath,
    Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    // On Android stream natively (see downloadFile)
    if (NativeSftp.isSupported) {
      final bytes = await NativeSftp.upload(
        connection: _connection!,
        localPath: localPath,
        remotePath: remotePath,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      debugPrint('[SFTP] Native upload complete: $bytes bytes');
      return true;
    }

    try {
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        throw Exception('Local file does not exist');
      }

      final fileSize = await localFile.length();
      print('[SFTP] Upload: $remotePath ($fileSize bytes)');

      final remoteFile = await _sftpClient!.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      int uploaded = 0;
      final raf = await localFile.open();

      try {
        // Use 256KB chunks — writeBytes internally pipelines 16 x 16KB writes
        const chunkSize = 256 * 1024;
        while (uploaded < fileSize) {
          if (isCancelled != null && isCancelled()) {
            throw Exception('Cancelled');
          }
          final remaining = fileSize - uploaded;
          final toRead = remaining < chunkSize ? remaining : chunkSize;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          // Single chunk write - no parallelism, most reliable
          await remoteFile.writeBytes(
            Uint8List.fromList(chunk),
            offset: uploaded,
          );
          uploaded += chunk.length;

          if (onProgress != null) {
            onProgress(uploaded, fileSize);
          }
        }
      } finally {
        await raf.close();
        await remoteFile.close();
      }

      print('[SFTP] ===== UPLOAD COMPLETE ($uploaded bytes) =====');
      return true;
    } catch (e) {
      print('[SFTP] UPLOAD ERROR: $e');
      throw Exception('Upload failed: $e');
    }
  }

  /// Get file size
  Future<int?> getFileSize(String remotePath) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final stat = await _sftpClient!.stat(remotePath);
      return stat.size;
    } catch (e) {
      debugPrint('SFTP Get File Size Error: $e');
      return null;
    }
  }

  /// Check if path exists
  Future<bool> exists(String path) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      await _sftpClient!.stat(path);
      return true;
    } catch (e) {
      return false;
    }
  }
}
