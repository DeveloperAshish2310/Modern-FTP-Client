import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/connection_model.dart';
import '../models/file_item_model.dart';

/// SFTP service implementation using dartssh2 library
class SFTPService {
  SSHClient? _sshClient;
  SftpClient? _sftpClient;
  ConnectionModel? _connection;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  ConnectionModel? get connection => _connection;

  /// Connect to SFTP server
  Future<bool> connect(ConnectionModel connection) async {
    try {
      _connection = connection;

      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: const Duration(seconds: 30),
      );

      // Authenticate with password or SSH key
      if (connection.sshKeyPath != null && connection.sshKeyPath!.isNotEmpty) {
        // SSH key authentication
        final keyFile = File(connection.sshKeyPath!);
        if (await keyFile.exists()) {
          final keyContent = await keyFile.readAsString();
          _sshClient = SSHClient(
            socket,
            username: connection.username,
            identities: [...SSHKeyPair.fromPem(keyContent)],
          );
        } else {
          throw Exception('SSH key file not found');
        }
      } else {
        // Password authentication
        _sshClient = SSHClient(
          socket,
          username: connection.username,
          onPasswordRequest: () => connection.password ?? '',
        );
      }

      _sftpClient = await _sshClient!.sftp();
      _isConnected = true;

      return true;
    } catch (e) {
      debugPrint('SFTP Connection Error: $e');
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

  /// Download file using chunked streaming to avoid memory issues
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final localFile = File(localPath);

      // Ensure parent directory exists
      final parentDir = localFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Get file size first
      final stat = await _sftpClient!.stat(remotePath);
      final fileSize = stat.size ?? 0;
      print('[SFTP] Download: $remotePath ($fileSize bytes)');

      if (fileSize == 0) {
        await localFile.create();
        print('[SFTP] Empty file created');
        return true;
      }

      // Open remote file
      final remoteFile = await _sftpClient!.open(
        remotePath,
        mode: SftpFileOpenMode.read,
      );

      // Use streaming read() which pipelines 64 x 16KB chunks (1MB in flight)
      final sink = localFile.openWrite();
      DateTime lastProgress = DateTime.now();
      bool cancelled = false;
      int bytesWritten = 0;
      int lastFlushAt = 0;

      try {
        await for (final chunk in remoteFile.read(
          onProgress: (bytesRead) {
            if (onProgress != null) {
              final now = DateTime.now();
              if (now.difference(lastProgress).inMilliseconds >= 200 ||
                  bytesRead >= fileSize) {
                lastProgress = now;
                onProgress(bytesRead, fileSize);
              }
            }
          },
        )) {
          if (isCancelled != null && isCancelled()) {
            cancelled = true;
            break;
          }
          sink.add(chunk);
          bytesWritten += chunk.length;

          // Flush to disk every ~1MB to prevent large end-of-transfer stall
          if (bytesWritten - lastFlushAt >= 1024 * 1024) {
            await sink.flush();
            lastFlushAt = bytesWritten;
          }
        }
      } catch (e) {
        if (!cancelled) rethrow;
      } finally {
        await sink.flush();
        await sink.close();
        try {
          await remoteFile.close();
        } catch (_) {}
      }

      // Fire 100% progress
      if (!cancelled && onProgress != null) {
        onProgress(fileSize, fileSize);
      }

      if (cancelled) {
        if (await localFile.exists()) await localFile.delete();
        throw Exception('Cancelled');
      }

      final writtenSize = await localFile.length();
      print('[SFTP] Written: $writtenSize bytes');
      print('[SFTP] ===== DOWNLOAD COMPLETE =====');

      if (writtenSize == 0 && fileSize > 0) {
        throw Exception('0 bytes written (expected $fileSize)');
      }
      return true;
    } catch (e) {
      print('[SFTP] ERROR: $e');
      rethrow;
    }
  }

  /// Upload file using sequential writeBytes for reliability
  Future<bool> uploadFile({
    required String localPath,
    required String remotePath,
    Function(int, int)? onProgress,
  }) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
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

      // Read in 64KB chunks and write sequentially
      const chunkSize = 64 * 1024;
      int uploaded = 0;
      DateTime lastProgress = DateTime.now();
      final raf = await localFile.open();

      try {
        while (uploaded < fileSize) {
          final remaining = fileSize - uploaded;
          final toRead = remaining < chunkSize ? remaining : chunkSize;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;

          await remoteFile.writeBytes(
            Uint8List.fromList(chunk),
            offset: uploaded,
          );
          uploaded += chunk.length;

          if (onProgress != null) {
            final now = DateTime.now();
            if (now.difference(lastProgress).inMilliseconds >= 200 ||
                uploaded >= fileSize) {
              lastProgress = now;
              onProgress(uploaded, fileSize);
            }
          }
        }
      } finally {
        await raf.close();
        await remoteFile.close();
      }

      print('[SFTP] ===== UPLOAD COMPLETE =====');
      return true;
    } catch (e) {
      debugPrint('SFTP Upload Error: $e');
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
