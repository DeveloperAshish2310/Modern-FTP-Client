import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import '../models/connection_model.dart';
import '../models/file_item_model.dart';

/// FTP/FTPS service implementation using ftpconnect library
class FTPService {
  FTPConnect? _ftpConnect;
  ConnectionModel? _connection;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  ConnectionModel? get connection => _connection;

  /// Connect to FTP/FTPS server
  Future<bool> connect(ConnectionModel connection) async {
    try {
      _connection = connection;

      // Create FTP connection
      _ftpConnect = FTPConnect(
        connection.host,
        user: connection.username,
        pass: connection.password ?? '',
        port: connection.port,
        timeout: 30,
        securityType: connection.protocol == ConnectionProtocol.ftps
            ? SecurityType.FTPS
            : SecurityType.FTP,
      );

      // Attempt connection
      final isConnected = await _ftpConnect!.connect();
      _isConnected = isConnected;

      return isConnected;
    } catch (e) {
      debugPrint('FTP Connection Error: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Disconnect from FTP server
  Future<void> disconnect() async {
    try {
      if (_ftpConnect != null && _isConnected) {
        await _ftpConnect!.disconnect();
      }
    } catch (e) {
      debugPrint('FTP Disconnect Error: $e');
    } finally {
      _isConnected = false;
      _ftpConnect = null;
      _connection = null;
    }
  }

  /// List directory contents
  Future<List<FileItemModel>> listDirectory(String path) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      await _ftpConnect!.changeDirectory(path);
      final dirContents = await _ftpConnect!.listDirectoryContent();

      List<FileItemModel> items = [];

      for (var item in dirContents) {
        items.add(
          FileItemModel(
            name: item.name,
            path: '$path/${item.name}',
            size: item.size ?? 0,
            isDirectory: item.type == FTPEntryType.DIR,
            modifiedDate: item.modifyTime,
            permissions: null, // permissions not available in FTPEntry
          ),
        );
      }

      return items;
    } catch (e) {
      debugPrint('FTP List Directory Error: $e');
      throw Exception('Failed to list directory: $e');
    }
  }

  /// Create directory
  Future<bool> createDirectory(String path, String name) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      final fullPath = '$path/$name';
      final result = await _ftpConnect!.makeDirectory(fullPath);
      return result;
    } catch (e) {
      debugPrint('FTP Create Directory Error: $e');
      return false;
    }
  }

  /// Rename file/folder
  Future<bool> rename(String oldPath, String newPath) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      final result = await _ftpConnect!.rename(oldPath, newPath);
      return result;
    } catch (e) {
      debugPrint('FTP Rename Error: $e');
      return false;
    }
  }

  /// Delete file
  Future<bool> deleteFile(String path) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      final result = await _ftpConnect!.deleteFile(path);
      return result;
    } catch (e) {
      debugPrint('FTP Delete File Error: $e');
      return false;
    }
  }

  /// Delete directory
  Future<bool> deleteDirectory(String path) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      final result = await _ftpConnect!.deleteDirectory(path);
      return result;
    } catch (e) {
      debugPrint('FTP Delete Directory Error: $e');
      return false;
    }
  }

  /// Download file
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    Function(double)? onProgress,
  }) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      final localFile = File(localPath);

      // Download with progress callback
      final result = await _ftpConnect!.downloadFile(remotePath, localFile);

      return result;
    } catch (e) {
      debugPrint('FTP Download Error: $e');
      throw Exception('Download failed: $e');
    }
  }

  /// Upload file
  Future<bool> uploadFile({
    required String localPath,
    required String remotePath,
    Function(double)? onProgress,
  }) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        throw Exception('Local file does not exist');
      }

      // Upload with progress callback
      final result = await _ftpConnect!.uploadFile(localFile);

      return result;
    } catch (e) {
      debugPrint('FTP Upload Error: $e');
      throw Exception('Upload failed: $e');
    }
  }

  /// Get file size
  Future<int?> getFileSize(String remotePath) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      return await _ftpConnect!.sizeFile(remotePath);
    } catch (e) {
      debugPrint('FTP Get File Size Error: $e');
      return null;
    }
  }

  /// Check if path exists
  Future<bool> exists(String path) async {
    if (!_isConnected || _ftpConnect == null) {
      throw Exception('Not connected to FTP server');
    }

    try {
      // Try to change directory or get file size
      await _ftpConnect!.changeDirectory(path);
      return true;
    } catch (e) {
      try {
        await _ftpConnect!.sizeFile(path);
        return true;
      } catch (e2) {
        return false;
      }
    }
  }
}
