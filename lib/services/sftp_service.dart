import 'dart:io';
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
      print('SFTP Connection Error: $e');
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
      print('SFTP Disconnect Error: $e');
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
            permissions: _formatPermissions(item.attr.permissions),
          ),
        );
      }

      return fileItems;
    } catch (e) {
      print('SFTP List Directory Error: $e');
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
      print('SFTP Create Directory Error: $e');
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
      print('SFTP Rename Error: $e');
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
      print('SFTP Delete File Error: $e');
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
      print('SFTP Delete Directory Error: $e');
      return false;
    }
  }

  /// Download file
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    Function(int, int)? onProgress,
  }) async {
    if (!_isConnected || _sftpClient == null) {
      throw Exception('Not connected to SFTP server');
    }

    try {
      final localFile = File(localPath);
      final remoteFile = await _sftpClient!.open(remotePath);

      // Get file size for progress tracking
      final stat = await _sftpClient!.stat(remotePath);
      final fileSize = stat.size ?? 0;

      int downloaded = 0;
      final sink = localFile.openWrite();

      await for (final chunk in remoteFile.read()) {
        sink.add(chunk);
        downloaded += chunk.length;

        if (onProgress != null && fileSize > 0) {
          onProgress(downloaded, fileSize);
        }
      }

      await sink.close();
      return true;
    } catch (e) {
      print('SFTP Download Error: $e');
      throw Exception('Download failed: $e');
    }
  }

  /// Upload file
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
      final remoteFile = await _sftpClient!.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      int uploaded = 0;
      final stream = localFile.openRead();

      await for (final chunk in stream) {
        await remoteFile.write(chunk as List<int>);
        uploaded += chunk.length;

        if (onProgress != null && fileSize > 0) {
          onProgress(uploaded, fileSize);
        }
      }

      return true;
    } catch (e) {
      print('SFTP Upload Error: $e');
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
      print('SFTP Get File Size Error: $e');
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

  /// Format permissions to string
  String? _formatPermissions(int? permissions) {
    if (permissions == null) return null;

    String result = '';
    const types = ['---', '--x', '-w-', '-wx', 'r--', 'r-x', 'rw-', 'rwx'];

    result += types[(permissions >> 6) & 7]; // Owner
    result += types[(permissions >> 3) & 7]; // Group
    result += types[permissions & 7]; // Others

    return result;
  }
}
