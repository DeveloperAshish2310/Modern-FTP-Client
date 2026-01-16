/// Model for file transfer tracking
class TransferModel {
  final int? id;
  final int connectionId;
  final String fileName;
  final String localPath;
  final String remotePath;
  final int fileSize;
  final TransferType type;
  TransferStatus status;
  final DateTime startedAt;
  DateTime? completedAt;
  String? errorMessage;

  // Runtime progress tracking (not stored in DB)
  double progress;
  double speed; // bytes per second

  TransferModel({
    this.id,
    required this.connectionId,
    required this.fileName,
    required this.localPath,
    required this.remotePath,
    required this.fileSize,
    required this.type,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.progress = 0.0,
    this.speed = 0.0,
  });

  // Convert to Map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'connection_id': connectionId,
      'file_name': fileName,
      'local_path': localPath,
      'remote_path': remotePath,
      'file_size': fileSize,
      'transfer_type': type.name,
      'status': status.name,
      'started_at': startedAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'error_message': errorMessage,
    };
  }

  // Create from Map (database result)
  factory TransferModel.fromMap(Map<String, dynamic> map) {
    return TransferModel(
      id: map['id'] as int?,
      connectionId: map['connection_id'] as int,
      fileName: map['file_name'] as String,
      localPath: map['local_path'] as String,
      remotePath: map['remote_path'] as String,
      fileSize: map['file_size'] as int,
      type: TransferType.values.firstWhere(
        (e) => e.name == map['transfer_type'],
      ),
      status: TransferStatus.values.firstWhere((e) => e.name == map['status']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
      completedAt: map['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
          : null,
      errorMessage: map['error_message'] as String?,
    );
  }

  // Get formatted speed
  String get formattedSpeed {
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  // Get ETA (estimated time of arrival)
  String get eta {
    if (speed <= 0 || progress >= 1.0) return '--';

    final remainingBytes = fileSize * (1.0 - progress);
    final remainingSeconds = remainingBytes / speed;

    if (remainingSeconds < 60) return '${remainingSeconds.toInt()}s';
    if (remainingSeconds < 3600) return '${(remainingSeconds / 60).toInt()}m';
    return '${(remainingSeconds / 3600).toInt()}h ${((remainingSeconds % 3600) / 60).toInt()}m';
  }

  // Get percentage
  String get percentage => '${(progress * 100).toStringAsFixed(0)}%';
}

/// Transfer type enum
enum TransferType { upload, download }

/// Transfer status enum
enum TransferStatus {
  pending,
  inProgress,
  paused,
  completed,
  failed,
  cancelled,
}

/// Extension for transfer status
extension TransferStatusExtension on TransferStatus {
  String get displayName {
    switch (this) {
      case TransferStatus.pending:
        return 'Pending';
      case TransferStatus.inProgress:
        return 'In Progress';
      case TransferStatus.paused:
        return 'Paused';
      case TransferStatus.completed:
        return 'Completed';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.cancelled:
        return 'Cancelled';
    }
  }
}
