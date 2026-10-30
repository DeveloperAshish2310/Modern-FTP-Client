/// Connection Manager - Unified interface for FTP, SFTP, and FTPS protocols.
///
/// Delegates operations to [FTPService] or [SFTPService] based on the
/// active connection's protocol. Provides a single API for file browsing,
/// uploads, downloads, and file management operations.
import 'dart:io';
import '../models/connection_model.dart';
import '../models/file_item_model.dart';
import 'ftp_service.dart';
import 'sftp_service.dart';

/// Unified connection manager for all protocols
class ConnectionManager {
  FTPService? _ftpService;
  SFTPService? _sftpService;
  ConnectionModel? _activeConnection;

  bool get isConnected {
    if (_activeConnection == null) return false;

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return _ftpService?.isConnected ?? false;
      case ConnectionProtocol.sftp:
        return _sftpService?.isConnected ?? false;
    }
  }

  ConnectionModel? get activeConnection => _activeConnection;

  /// Connect to server
  Future<bool> connect(ConnectionModel connection) async {
    // Disconnect if already connected
    if (isConnected) {
      await disconnect();
    }

    _activeConnection = connection;

    switch (connection.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        _ftpService = FTPService();
        return await _ftpService!.connect(connection);

      case ConnectionProtocol.sftp:
        _sftpService = SFTPService();
        return await _sftpService!.connect(connection);
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    if (_ftpService != null) {
      await _ftpService!.disconnect();
      _ftpService = null;
    }

    if (_sftpService != null) {
      await _sftpService!.disconnect();
      _sftpService = null;
    }

    _activeConnection = null;
  }

  /// Run [op], reconnecting once if the connection was dropped (idle
  /// timeout, phone sleep, server restart) and retrying it.
  Future<T> _withReconnect<T>(Future<T> Function() op) async {
    final connection = _activeConnection;
    if (connection == null) throw Exception('Not connected');
    if (!isConnected) await _reconnect(connection);
    try {
      return await op();
    } catch (e) {
      if (!_isConnectionLost(e)) rethrow;
      await _reconnect(connection);
      return await op();
    }
  }

  Future<void> _reconnect(ConnectionModel connection) async {
    await disconnect();
    if (!await connect(connection)) {
      throw Exception('Connection lost and reconnect failed');
    }
  }

  static bool _isConnectionLost(Object e) {
    final msg = e.toString();
    return e is SocketException ||
        msg.contains('Connection closed') ||
        msg.contains('SftpAbortError') ||
        msg.contains('SSHStateError') ||
        msg.contains('SocketException') ||
        msg.contains('Broken pipe') ||
        msg.contains('Connection reset') ||
        msg.contains('Not connected');
  }

  /// List directory contents
  Future<List<FileItemModel>> listDirectory(String path) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.listDirectory(path);
        case ConnectionProtocol.sftp:
          return await _sftpService!.listDirectory(path);
      }
    });
  }

  /// Create directory
  Future<bool> createDirectory(String path, String name) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.createDirectory(path, name);
        case ConnectionProtocol.sftp:
          return await _sftpService!.createDirectory(path, name);
      }
    });
  }

  /// Create an empty file
  Future<bool> createFile(String path, String name) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.createFile(path, name);
        case ConnectionProtocol.sftp:
          return await _sftpService!.createFile(path, name);
      }
    });
  }

  /// Rename file/folder
  Future<bool> rename(String oldPath, String newPath) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.rename(oldPath, newPath);
        case ConnectionProtocol.sftp:
          return await _sftpService!.rename(oldPath, newPath);
      }
    });
  }

  /// Delete file
  Future<bool> deleteFile(String path) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.deleteFile(path);
        case ConnectionProtocol.sftp:
          return await _sftpService!.deleteFile(path);
      }
    });
  }

  /// Delete directory
  Future<bool> deleteDirectory(String path) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.deleteDirectory(path);
        case ConnectionProtocol.sftp:
          return await _sftpService!.deleteDirectory(path);
      }
    });
  }

  /// Download file (unified for all protocols)
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
    bool Function()? isCancelled,
    Function(int, int)? onProgress,
    bool resume = false,
  }) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.downloadFile(
            remotePath: remotePath,
            localPath: localPath,
            onProgress: onProgress,
          );
        case ConnectionProtocol.sftp:
          return await _sftpService!.downloadFile(
            remotePath: remotePath,
            localPath: localPath,
            isCancelled: isCancelled,
            onProgress: onProgress,
            resume: resume,
          );
      }
    });
  }

  /// Copy a file on the server without transferring it through the device.
  /// Returns false when the protocol/server can't do it (FTP has no copy).
  Future<bool> copyFileOnServer(String sourcePath, String destPath) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return false;
        case ConnectionProtocol.sftp:
          return await _sftpService!.copyFileOnServer(sourcePath, destPath);
      }
    });
  }

  /// Upload file (unified for all protocols)
  Future<bool> uploadFile({
    required String localPath,
    required String remotePath,
    bool Function()? isCancelled,
    Function(int, int)? onProgress,
  }) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.uploadFile(
            localPath: localPath,
            remotePath: remotePath,
            onProgress: onProgress,
          );
        case ConnectionProtocol.sftp:
          return await _sftpService!.uploadFile(
            localPath: localPath,
            remotePath: remotePath,
            isCancelled: isCancelled,
            onProgress: onProgress,
          );
      }
    });
  }

  /// Check if a path exists on server
  Future<bool> exists(String path) {
    return _withReconnect(() async {
      switch (_activeConnection!.protocol) {
        case ConnectionProtocol.ftp:
        case ConnectionProtocol.ftps:
          return await _ftpService!.exists(path);
        case ConnectionProtocol.sftp:
          return await _sftpService!.exists(path);
      }
    });
  }
}
