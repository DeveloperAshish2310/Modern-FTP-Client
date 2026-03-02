import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/connection_model.dart';
import '../models/transfer_model.dart';
import '../core/database/database_helper.dart';
import 'connection_manager.dart';

/// Active transfer item with live progress
class ActiveTransfer {
  final int id; // DB id
  final String fileName;
  final String localPath;
  final String remotePath;
  final int fileSize;
  final TransferType type;
  TransferStatus status;
  int bytesTransferred;
  double speed; // bytes/sec
  DateTime startedAt;
  String? errorMessage;

  ActiveTransfer({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.remotePath,
    required this.fileSize,
    required this.type,
    this.status = TransferStatus.inProgress,
    this.bytesTransferred = 0,
    this.speed = 0,
    DateTime? startedAt,
    this.errorMessage,
  }) : startedAt = startedAt ?? DateTime.now();

  double get progress => fileSize > 0 ? bytesTransferred / fileSize : 0;
  String get percentage => '${(progress * 100).toStringAsFixed(0)}%';
}

/// Singleton transfer service for background downloads/uploads
class TransferService extends ChangeNotifier {
  static final TransferService _instance = TransferService._internal();
  factory TransferService() => _instance;
  TransferService._internal();

  final DatabaseHelper _db = DatabaseHelper();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final List<ActiveTransfer> _activeTransfers = [];
  bool _initialized = false;

  // Cache connection managers for retry
  final Map<int, ConnectionManager> _connectionManagers = {};
  final Map<int, ConnectionModel> _connections = {};

  List<ActiveTransfer> get activeTransfers =>
      List.unmodifiable(_activeTransfers);
  int get activeCount => _activeTransfers.length;
  bool get hasActive => _activeTransfers.isNotEmpty;

  /// Initialize notification channel
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    // Create notification channel
    const channel = AndroidNotificationChannel(
      'ftp_transfers',
      'File Transfers',
      description: 'File transfer progress and completion',
      importance: Importance.low,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Start a background download
  Future<void> startDownload({
    required ConnectionModel connection,
    required ConnectionManager connectionManager,
    required String remotePath,
    required String localPath,
    required String fileName,
    required int fileSize,
  }) async {
    await init();

    // Cache for retry
    _connectionManagers[connection.id ?? 0] = connectionManager;
    _connections[connection.id ?? 0] = connection;

    // Insert into DB
    final transfer = TransferModel(
      connectionId: connection.id ?? 0,
      fileName: fileName,
      localPath: localPath,
      remotePath: remotePath,
      fileSize: fileSize,
      type: TransferType.download,
      status: TransferStatus.inProgress,
      startedAt: DateTime.now(),
    );
    final dbId = await _db.insertTransfer(transfer.toMap());

    // Create active transfer
    final active = ActiveTransfer(
      id: dbId,
      fileName: fileName,
      localPath: localPath,
      remotePath: remotePath,
      fileSize: fileSize,
      type: TransferType.download,
    );
    _activeTransfers.add(active);
    notifyListeners();

    // Show notification
    _showProgressNotification(active);

    // Execute download in background
    _executeDownload(active, connectionManager);
  }

  /// Start a background upload
  Future<void> startUpload({
    required ConnectionModel connection,
    required ConnectionManager connectionManager,
    required String remotePath,
    required String localPath,
    required String fileName,
    required int fileSize,
  }) async {
    await init();

    // Cache for retry
    _connectionManagers[connection.id ?? 0] = connectionManager;
    _connections[connection.id ?? 0] = connection;

    final transfer = TransferModel(
      connectionId: connection.id ?? 0,
      fileName: fileName,
      localPath: localPath,
      remotePath: remotePath,
      fileSize: fileSize,
      type: TransferType.upload,
      status: TransferStatus.inProgress,
      startedAt: DateTime.now(),
    );
    final dbId = await _db.insertTransfer(transfer.toMap());

    final active = ActiveTransfer(
      id: dbId,
      fileName: fileName,
      localPath: localPath,
      remotePath: remotePath,
      fileSize: fileSize,
      type: TransferType.upload,
    );
    _activeTransfers.add(active);
    notifyListeners();

    _showProgressNotification(active);
    _executeUpload(active, connectionManager);
  }

  /// Cancel an active transfer
  void cancelTransfer(int dbId) {
    final idx = _activeTransfers.indexWhere((t) => t.id == dbId);
    if (idx >= 0) {
      _activeTransfers[idx].status = TransferStatus.cancelled;
      notifyListeners();
    }
  }

  /// Retry a failed/cancelled transfer from history
  Future<bool> retryTransfer(TransferModel transfer) async {
    final cm = _connectionManagers[transfer.connectionId];
    final conn = _connections[transfer.connectionId];
    if (cm == null || conn == null) return false;

    if (transfer.type == TransferType.download) {
      await startDownload(
        connection: conn,
        connectionManager: cm,
        remotePath: transfer.remotePath,
        localPath: transfer.localPath,
        fileName: transfer.fileName,
        fileSize: transfer.fileSize,
      );
    } else {
      await startUpload(
        connection: conn,
        connectionManager: cm,
        remotePath: transfer.remotePath,
        localPath: transfer.localPath,
        fileName: transfer.fileName,
        fileSize: transfer.fileSize,
      );
    }
    return true;
  }

  /// Execute download
  Future<void> _executeDownload(
    ActiveTransfer active,
    ConnectionManager cm,
  ) async {
    DateTime lastNotify = DateTime.now();
    try {
      await cm.downloadFile(
        remotePath: active.remotePath,
        localPath: active.localPath,
        isCancelled: () => active.status == TransferStatus.cancelled,
        onProgress: (downloaded, total) {
          active.bytesTransferred = downloaded;
          final now = DateTime.now();
          final elapsed = now.difference(active.startedAt).inMilliseconds;
          if (elapsed > 0) {
            active.speed = downloaded / elapsed * 1000;
          }
          // Throttle UI + notification updates
          if (now.difference(lastNotify).inMilliseconds >= 500) {
            lastNotify = now;
            notifyListeners();
            _showProgressNotification(active);
          }
        },
      );

      // Success
      active.status = TransferStatus.completed;
      active.bytesTransferred = active.fileSize;
      await _db.updateTransfer(active.id, {
        'status': TransferStatus.completed.name,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      });

      _showCompleteNotification(active, success: true);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('Cancelled')) {
        active.status = TransferStatus.cancelled;
        await _db.updateTransfer(active.id, {
          'status': TransferStatus.cancelled.name,
        });
      } else {
        active.status = TransferStatus.failed;
        active.errorMessage = msg;
        await _db.updateTransfer(active.id, {
          'status': TransferStatus.failed.name,
          'error_message': msg,
        });
      }
      _showCompleteNotification(active, success: false);
    } finally {
      _activeTransfers.remove(active);
      notifyListeners();
    }
  }

  /// Execute upload
  Future<void> _executeUpload(
    ActiveTransfer active,
    ConnectionManager cm,
  ) async {
    try {
      await cm.uploadFile(
        localPath: active.localPath,
        remotePath: active.remotePath,
      );

      active.status = TransferStatus.completed;
      active.bytesTransferred = active.fileSize;
      await _db.updateTransfer(active.id, {
        'status': TransferStatus.completed.name,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      });

      _showCompleteNotification(active, success: true);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      active.status = TransferStatus.failed;
      active.errorMessage = msg;
      await _db.updateTransfer(active.id, {
        'status': TransferStatus.failed.name,
        'error_message': msg,
      });
      _showCompleteNotification(active, success: false);
    } finally {
      _activeTransfers.remove(active);
      notifyListeners();
    }
  }

  /// Show progress notification
  void _showProgressNotification(ActiveTransfer transfer) {
    final pct = (transfer.progress * 100).round();
    final isDownload = transfer.type == TransferType.download;
    final speedText = transfer.speed > 0
        ? ' • ${_formatBytes(transfer.speed.round())}/s'
        : '';

    _notifications.show(
      transfer.id,
      '${isDownload ? '⬇️' : '⬆️'} ${transfer.fileName}',
      '$pct% • ${_formatBytes(transfer.bytesTransferred)} / ${_formatBytes(transfer.fileSize)}$speedText',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'ftp_transfers',
          'File Transfers',
          channelDescription: 'File transfer progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          showProgress: true,
          maxProgress: 100,
          progress: pct,
          autoCancel: false,
        ),
      ),
    );
  }

  /// Show completion notification
  void _showCompleteNotification(
    ActiveTransfer transfer, {
    required bool success,
  }) {
    final isDownload = transfer.type == TransferType.download;
    final icon = success ? '✅' : '❌';
    final statusText = success
        ? 'Complete'
        : (transfer.status == TransferStatus.cancelled
              ? 'Cancelled'
              : 'Failed');

    _notifications.show(
      transfer.id,
      '$icon ${transfer.fileName}',
      '${isDownload ? 'Download' : 'Upload'} $statusText',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ftp_transfers',
          'File Transfers',
          channelDescription: 'File transfer completion',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: false,
          autoCancel: true,
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
