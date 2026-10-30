/// Transfer Service - Manages background file downloads and uploads.
///
/// Handles concurrent transfers with progress tracking, speed calculation,
/// system notifications, database persistence, and cancel/retry operations.
/// Each transfer opens its own dedicated [ConnectionManager] so it never
/// shares a control channel with the file browser (FTP cannot multiplex
/// commands on one connection) and survives the browser screen closing.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  // Cache connections for retry
  final Map<int, ConnectionModel> _connections = {};

  // Dedicated connection per running transfer, keyed by DB id
  final Map<int, ConnectionManager> _transferConnections = {};

  // Limit parallel transfers; servers often cap connections per client
  static const int _maxConcurrent = 3;
  int _running = 0;
  final List<Completer<void>> _waiting = [];

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

  /// Start a background download.
  ///
  /// [existingId] reuses a history row (resuming an interrupted transfer)
  /// instead of inserting a new one. [resume] continues a partial local
  /// file where the protocol supports it (native SFTP on Android).
  Future<void> startDownload({
    required ConnectionModel connection,
    required String remotePath,
    required String localPath,
    required String fileName,
    required int fileSize,
    int? existingId,
    bool resume = false,
  }) async {
    await init();

    // Cache for retry
    _connections[connection.id ?? 0] = connection;

    final int dbId;
    if (existingId != null) {
      dbId = existingId;
      await _db.updateTransfer(dbId, {
        'status': TransferStatus.inProgress.name,
        'error_message': null,
      });
    } else {
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
      dbId = await _db.insertTransfer(transfer.toMap());
    }

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
    _executeDownload(active, connection, resume: resume);
  }

  /// Start a background upload
  Future<void> startUpload({
    required ConnectionModel connection,
    required String remotePath,
    required String localPath,
    required String fileName,
    required int fileSize,
  }) async {
    await init();

    // Cache for retry
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
    _executeUpload(active, connection);
  }

  /// Cancel an active transfer
  void cancelTransfer(int dbId) {
    final idx = _activeTransfers.indexWhere((t) => t.id == dbId);
    if (idx >= 0) {
      final transfer = _activeTransfers[idx];
      transfer.status = TransferStatus.cancelled;

      // Update DB
      _db.updateTransfer(dbId, {'status': TransferStatus.cancelled.name});

      // Remove from active list immediately
      _activeTransfers.removeAt(idx);
      notifyListeners();

      // Show cancelled notification
      _showCompleteNotification(transfer, success: false);

      // Closing the dedicated connection aborts the in-flight transfer;
      // the partial file is removed once the transfer has stopped.
      _transferConnections[dbId]?.disconnect();
    }
  }

  Future<void> _acquireSlot() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void _releaseSlot() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  /// Open a dedicated connection for one transfer
  Future<ConnectionManager> _openTransferConnection(
    ActiveTransfer active,
    ConnectionModel connection,
  ) async {
    final cm = ConnectionManager();
    _transferConnections[active.id] = cm;
    final ok = await cm
        .connect(connection)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('Connection timed out'),
        );
    if (!ok) {
      throw Exception(
        'Could not open transfer connection to ${connection.host}',
      );
    }
    return cm;
  }

  Future<void> _closeTransferConnection(ActiveTransfer active) async {
    final cm = _transferConnections.remove(active.id);
    try {
      await cm?.disconnect();
    } catch (_) {}
  }

  static const MethodChannel _mediaChannel = MethodChannel(
    'com.ftpclient/media',
  );

  /// Add a downloaded file to Android's MediaStore; files written with the
  /// File API are otherwise invisible to Gallery and the Files app.
  void _scanMedia(String path) {
    if (!Platform.isAndroid) return;
    _mediaChannel
        .invokeMethod('scanFile', {'path': path})
        .catchError((Object e) => debugPrint('Media scan failed: $e'));
  }

  /// Look up a connection, falling back to the DB after an app restart
  Future<ConnectionModel?> _getConnection(int connectionId) async {
    final cached = _connections[connectionId];
    if (cached != null) return cached;
    final row = await _db.getConnection(connectionId);
    if (row == null) return null;
    return _connections[connectionId] = ConnectionModel.fromMap(row);
  }

  bool _resumeChecked = false;

  /// Restart downloads left "in progress" when the app was killed.
  /// Downloads resume from the partial file; uploads can't be resumed and
  /// are marked failed so the user can retry them.
  Future<void> resumeInterrupted() async {
    if (_resumeChecked) return;
    _resumeChecked = true;

    final rows = await _db.getTransferHistory(limit: 200);
    final activeIds = _activeTransfers.map((t) => t.id).toSet();
    final stale = rows
        .map(TransferModel.fromMap)
        .where(
          (t) =>
              t.status == TransferStatus.inProgress &&
              !activeIds.contains(t.id),
        )
        .toList();

    // Rows are newest first: resume only the newest per local file so two
    // transfers never write the same file
    final seenPaths = <String>{};
    for (final t in stale) {
      final conn = await _getConnection(t.connectionId);
      if (t.type == TransferType.download &&
          conn != null &&
          seenPaths.add(t.localPath)) {
        await startDownload(
          connection: conn,
          remotePath: t.remotePath,
          localPath: t.localPath,
          fileName: t.fileName,
          fileSize: t.fileSize,
          existingId: t.id,
          resume: true,
        );
      } else {
        await _db.updateTransfer(t.id!, {
          'status': TransferStatus.failed.name,
          'error_message': 'Interrupted: app was closed',
        });
      }
    }
  }

  /// Retry a failed/cancelled transfer from history
  Future<bool> retryTransfer(TransferModel transfer) async {
    final conn = await _getConnection(transfer.connectionId);
    if (conn == null) return false;

    if (transfer.type == TransferType.download) {
      await startDownload(
        connection: conn,
        remotePath: transfer.remotePath,
        localPath: transfer.localPath,
        fileName: transfer.fileName,
        fileSize: transfer.fileSize,
        resume: true,
      );
    } else {
      await startUpload(
        connection: conn,
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
    ConnectionModel connection, {
    bool resume = false,
  }) async {
    DateTime lastNotify = DateTime.now();
    bool started = false;
    int? baseBytes; // bytes already on disk when resuming
    await _acquireSlot();
    try {
      if (active.status == TransferStatus.cancelled) {
        throw Exception('Cancelled');
      }
      final cm = await _openTransferConnection(active, connection);
      if (active.status == TransferStatus.cancelled) {
        throw Exception('Cancelled');
      }

      // Measure speed from when bytes start flowing, not from queueing
      active.startedAt = DateTime.now();
      started = true;
      await cm.downloadFile(
        remotePath: active.remotePath,
        localPath: active.localPath,
        isCancelled: () => active.status == TransferStatus.cancelled,
        resume: resume,
        onProgress: (downloaded, total) {
          if (active.status == TransferStatus.cancelled) return;
          active.bytesTransferred = downloaded;
          baseBytes ??= downloaded;
          final now = DateTime.now();
          final elapsed = now.difference(active.startedAt).inMilliseconds;
          if (elapsed > 0) {
            active.speed = (downloaded - baseBytes!) / elapsed * 1000;
          }
          // Throttle UI + notification updates
          if (now.difference(lastNotify).inMilliseconds >= 500) {
            lastNotify = now;
            notifyListeners();
            _showProgressNotification(active);
          }
        },
      );

      if (active.status == TransferStatus.cancelled) {
        throw Exception('Cancelled');
      }

      // Success
      active.status = TransferStatus.completed;
      active.bytesTransferred = active.fileSize;
      notifyListeners(); // Tell UI we're done NOW
      _scanMedia(active.localPath);
      await _db.updateTransfer(active.id, {
        'status': TransferStatus.completed.name,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      });

      _showCompleteNotification(active, success: true);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (active.status == TransferStatus.cancelled) {
        // cancelTransfer already updated DB + notification; drop partial file
        if (started) {
          try {
            final file = File(active.localPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      } else {
        active.status = TransferStatus.failed;
        active.errorMessage = msg;
        await _db.updateTransfer(active.id, {
          'status': TransferStatus.failed.name,
          'error_message': msg,
        });
        _showCompleteNotification(active, success: false);
      }
    } finally {
      await _closeTransferConnection(active);
      _releaseSlot();
      _activeTransfers.remove(active);
      notifyListeners();
    }
  }

  /// Execute upload
  Future<void> _executeUpload(
    ActiveTransfer active,
    ConnectionModel connection,
  ) async {
    await _acquireSlot();
    try {
      if (active.status == TransferStatus.cancelled) {
        throw Exception('Cancelled');
      }
      final cm = await _openTransferConnection(active, connection);
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
      if (active.status != TransferStatus.cancelled) {
        final msg = e.toString().replaceAll('Exception: ', '');
        active.status = TransferStatus.failed;
        active.errorMessage = msg;
        await _db.updateTransfer(active.id, {
          'status': TransferStatus.failed.name,
          'error_message': msg,
        });
        _showCompleteNotification(active, success: false);
      }
    } finally {
      await _closeTransferConnection(active);
      _releaseSlot();
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
