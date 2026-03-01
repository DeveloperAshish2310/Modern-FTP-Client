import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/database/database_helper.dart';
import '../../models/transfer_model.dart';
import '../../services/transfer_service.dart';

class TransferManagerScreen extends StatefulWidget {
  const TransferManagerScreen({super.key});

  @override
  State<TransferManagerScreen> createState() => _TransferManagerScreenState();
}

class _TransferManagerScreenState extends State<TransferManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _db = DatabaseHelper();
  final TransferService _transferService = TransferService();

  List<TransferModel> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
    _transferService.addListener(_onTransferUpdate);
  }

  @override
  void dispose() {
    _transferService.removeListener(_onTransferUpdate);
    _tabController.dispose();
    super.dispose();
  }

  void _onTransferUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final rows = await _db.getTransferHistory(limit: 200);
    if (!mounted) return;
    setState(() {
      _history = rows.map((r) => TransferModel.fromMap(r)).toList();
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('This will remove all transfer history records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = await _db.database;
      await db.delete('transfer_history');
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _transferService.activeTransfers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear History',
              onPressed: _clearHistory,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: active.isNotEmpty ? 'Active (${active.length})' : 'Active',
            ),
            Tab(text: 'History (${_history.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildActiveTab(active), _buildHistoryTab()],
            ),
    );
  }

  // ================= ACTIVE TAB =================
  Widget _buildActiveTab(List<ActiveTransfer> active) {
    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_done, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No active transfers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Downloads and uploads will appear here',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: active.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, index) => _buildActiveTile(active[index]),
    );
  }

  Widget _buildActiveTile(ActiveTransfer transfer) {
    final isDownload = transfer.type == TransferType.download;
    final pct = (transfer.progress * 100).round();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isDownload ? Colors.blue : Colors.green).withAlpha(
                      30,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDownload ? Icons.download : Icons.upload,
                    color: isDownload ? Colors.blue : Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transfer.fileName,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_formatBytes(transfer.bytesTransferred)} / ${_formatBytes(transfer.fileSize)} • ${_formatBytes(transfer.speed.round())}/s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Cancel button
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 22),
                  onPressed: () => _transferService.cancelTransfer(transfer.id),
                  tooltip: 'Cancel',
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: transfer.progress),
            const SizedBox(height: 4),
            Text('$pct%', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  // ================= HISTORY TAB =================
  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_vert, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No transfers yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Transfer history will appear here',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        itemCount: _history.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (context, index) => _buildHistoryTile(_history[index]),
      ),
    );
  }

  Widget _buildHistoryTile(TransferModel transfer) {
    final isDownload = transfer.type == TransferType.download;
    final statusColor = _statusColor(transfer.status);
    final statusIcon = _statusIcon(transfer.status);
    final canRetry =
        transfer.status == TransferStatus.failed ||
        transfer.status == TransferStatus.cancelled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: transfer.status == TransferStatus.completed && isDownload
            ? () => OpenFilex.open(transfer.localPath)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isDownload ? Colors.blue : Colors.green).withAlpha(
                    30,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isDownload ? Icons.download : Icons.upload,
                  color: isDownload ? Colors.blue : Colors.green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.fileName,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatBytes(transfer.fileSize)} • ${_formatDate(transfer.startedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      transfer.status.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (canRetry)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Retry',
                  onPressed: () async {
                    final ok = await _transferService.retryTransfer(transfer);
                    if (!mounted) return;
                    if (ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Retrying: ${transfer.fileName}'),
                        ),
                      );
                      _tabController.animateTo(0); // Switch to Active tab
                      _loadHistory();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Cannot retry — connect to server first',
                          ),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= HELPERS =================
  Color _statusColor(TransferStatus status) {
    switch (status) {
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
        return Colors.red;
      case TransferStatus.cancelled:
        return Colors.orange;
      case TransferStatus.inProgress:
        return Colors.blue;
      case TransferStatus.paused:
        return Colors.amber;
      case TransferStatus.pending:
        return Colors.grey;
    }
  }

  IconData _statusIcon(TransferStatus status) {
    switch (status) {
      case TransferStatus.completed:
        return Icons.check_circle;
      case TransferStatus.failed:
        return Icons.error;
      case TransferStatus.cancelled:
        return Icons.cancel;
      case TransferStatus.inProgress:
        return Icons.sync;
      case TransferStatus.paused:
        return Icons.pause_circle;
      case TransferStatus.pending:
        return Icons.schedule;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(date);
  }
}
