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

  /// List directory contents
  Future<List<FileItemModel>> listDirectory(String path) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.listDirectory(path);
      case ConnectionProtocol.sftp:
        return await _sftpService!.listDirectory(path);
    }
  }

  /// Create directory
  Future<bool> createDirectory(String path, String name) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.createDirectory(path, name);
      case ConnectionProtocol.sftp:
        return await _sftpService!.createDirectory(path, name);
    }
  }

  /// Rename file/folder
  Future<bool> rename(String oldPath, String newPath) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.rename(oldPath, newPath);
      case ConnectionProtocol.sftp:
        return await _sftpService!.rename(oldPath, newPath);
    }
  }

  /// Delete file
  Future<bool> deleteFile(String path) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.deleteFile(path);
      case ConnectionProtocol.sftp:
        return await _sftpService!.deleteFile(path);
    }
  }

  /// Delete directory
  Future<bool> deleteDirectory(String path) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.deleteDirectory(path);
      case ConnectionProtocol.sftp:
        return await _sftpService!.deleteDirectory(path);
    }
  }

  /// Download file (unified for all protocols)
  Future<bool> downloadFile({
    required String remotePath,
    required String localPath,
  }) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.downloadFile(
          remotePath: remotePath,
          localPath: localPath,
        );
      case ConnectionProtocol.sftp:
        return await _sftpService!.downloadFile(
          remotePath: remotePath,
          localPath: localPath,
        );
    }
  }

  /// Upload file (unified for all protocols)
  Future<bool> uploadFile({
    required String localPath,
    required String remotePath,
  }) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.uploadFile(
          localPath: localPath,
          remotePath: remotePath,
        );
      case ConnectionProtocol.sftp:
        return await _sftpService!.uploadFile(
          localPath: localPath,
          remotePath: remotePath,
        );
    }
  }

  /// Check if a path exists on server
  Future<bool> exists(String path) async {
    if (!isConnected || _activeConnection == null) {
      throw Exception('Not connected');
    }

    switch (_activeConnection!.protocol) {
      case ConnectionProtocol.ftp:
      case ConnectionProtocol.ftps:
        return await _ftpService!.exists(path);
      case ConnectionProtocol.sftp:
        return await _sftpService!.exists(path);
    }
  }
}
