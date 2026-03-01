import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/connection_model.dart';
import '../../models/file_item_model.dart';
import '../../providers/connection_provider.dart';
import '../../services/connection_manager.dart';

/// Clipboard action for copy/move operations
enum _ClipboardAction { copy, move }

enum _SortMode {
  nameAsc,
  nameDesc,
  sizeAsc,
  sizeDesc,
  dateAsc,
  dateDesc,
  typeAsc,
}

class _ClipboardData {
  final List<FileItemModel> files;
  final _ClipboardAction action;
  final String sourcePath;

  _ClipboardData({
    required this.files,
    required this.action,
    required this.sourcePath,
  });
}

class FileBrowserScreen extends StatefulWidget {
  final ConnectionModel connection;

  const FileBrowserScreen({super.key, required this.connection});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final ConnectionManager _connectionManager = ConnectionManager();
  List<FileItemModel> _files = [];
  List<String> _pathHistory = ['/'];
  bool _isConnecting = true;
  bool _isLoading = false;
  String? _errorMessage;
  String _currentPath = '/';

  // Sort
  _SortMode _sortMode = _SortMode.nameAsc;

  // Multi-select
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};

  // Clipboard for copy/move
  _ClipboardData? _clipboard;

  // Transfer progress
  bool _isTransferring = false;
  String _transferStatus = '';
  bool _cancelRequested = false;
  int _transferDone = 0;
  int _transferTotal = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _connectionManager.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final success = await _connectionManager
          .connect(widget.connection)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Connection timed out after 15 seconds');
            },
          );

      if (!mounted) return;

      if (success) {
        Provider.of<ConnectionProvider>(
          context,
          listen: false,
        ).updateLastUsed(widget.connection.id!);

        // Try remote directory first, fallback to /
        final initialDir = widget.connection.remoteDirectory;
        if (initialDir != '/') {
          try {
            await _loadDirectory(initialDir);
            return;
          } catch (_) {
            // Path invalid, fallback
          }
        }
        await _loadDirectory('/');
      } else {
        setState(() {
          _isConnecting = false;
          _errorMessage =
              'Failed to connect to ${widget.connection.host}.\nCheck credentials and server settings.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage =
            'Connection error: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final files = await _connectionManager.listDirectory(path);
      if (!mounted) return;

      _sortFiles(files);

      setState(() {
        _files = files;
        _currentPath = path;
        _isConnecting = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isConnecting = false;
        _errorMessage =
            'Failed to list directory: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  void _navigateTo(String path) {
    _pathHistory.add(path);
    _loadDirectory(path);
  }

  void _navigateUp() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      _loadDirectory(_pathHistory.last);
    }
  }

  void _sortFiles(List<FileItemModel> files) {
    files.sort((a, b) {
      // Directories always first
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      switch (_sortMode) {
        case _SortMode.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortMode.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case _SortMode.sizeAsc:
          return a.size.compareTo(b.size);
        case _SortMode.sizeDesc:
          return b.size.compareTo(a.size);
        case _SortMode.dateAsc:
          return (a.modifiedDate ?? DateTime(2000)).compareTo(
            b.modifiedDate ?? DateTime(2000),
          );
        case _SortMode.dateDesc:
          return (b.modifiedDate ?? DateTime(2000)).compareTo(
            a.modifiedDate ?? DateTime(2000),
          );
        case _SortMode.typeAsc:
          final extA = a.name.contains('.') ? a.name.split('.').last : '';
          final extB = b.name.contains('.') ? b.name.split('.').last : '';
          return extA.compareTo(extB);
      }
    });
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sort by',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            _sortTile(ctx, 'Name (A → Z)', _SortMode.nameAsc),
            _sortTile(ctx, 'Name (Z → A)', _SortMode.nameDesc),
            _sortTile(ctx, 'Size (Smallest)', _SortMode.sizeAsc),
            _sortTile(ctx, 'Size (Largest)', _SortMode.sizeDesc),
            _sortTile(ctx, 'Date (Oldest)', _SortMode.dateAsc),
            _sortTile(ctx, 'Date (Newest)', _SortMode.dateDesc),
            _sortTile(ctx, 'Type', _SortMode.typeAsc),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sortTile(BuildContext ctx, String label, _SortMode mode) {
    return ListTile(
      title: Text(label),
      trailing: _sortMode == mode
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _sortMode = mode;
          _sortFiles(_files);
        });
      },
    );
  }

  // --- Selection ---
  void _toggleSelection(FileItemModel file) {
    setState(() {
      if (_selectedPaths.contains(file.path)) {
        _selectedPaths.remove(file.path);
        if (_selectedPaths.isEmpty) _isSelectionMode = false;
      } else {
        _selectedPaths.add(file.path);
      }
    });
  }

  void _enterSelectionMode(FileItemModel file) {
    setState(() {
      _isSelectionMode = true;
      _selectedPaths.add(file.path);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths.addAll(_files.map((f) => f.path));
    });
  }

  List<FileItemModel> get _selectedFiles =>
      _files.where((f) => _selectedPaths.contains(f.path)).toList();

  // --- Storage permission helper ---
  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // Fallback to regular storage permission
    status = await Permission.storage.request();
    if (status.isGranted) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission is required. Please grant it in Settings.',
          ),
        ),
      );
    }
    return false;
  }

  // --- Overwrite prompt ---
  Future<bool> _askOverwrite(String fileName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File Exists'),
        content: Text('"$fileName" already exists. Overwrite?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _cancelTransfer() {
    setState(() {
      _cancelRequested = true;
      _transferStatus = 'Cancelling...';
    });
  }

  /// Get the download directory - uses app's external storage which is always writable
  Future<Directory> _getDownloadDir() async {
    // Use app external dir as it's always writable without scoped storage issues
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      final dlDir = Directory('${extDir.path}/Downloads');
      if (!await dlDir.exists()) await dlDir.create(recursive: true);
      return dlDir;
    }
    // Fallback
    final tmpDir = await getTemporaryDirectory();
    final dlDir = Directory('${tmpDir.path}/Downloads');
    if (!await dlDir.exists()) await dlDir.create(recursive: true);
    return dlDir;
  }

  /// Trigger Android MediaScanner so the file shows up in the file manager
  Future<void> _scanFile(String path) async {
    try {
      // Use Android's media scan broadcast
      await Process.run('am', [
        'broadcast',
        '-a',
        'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d',
        'file://$path',
      ]);
    } catch (_) {
      // Non-critical, file is still downloaded
    }
  }

  // --- Upload ---
  Future<void> _uploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isTransferring = true;
        _cancelRequested = false;
        _transferDone = 0;
        _transferTotal = result.files.length;
        _transferStatus = 'Uploading...';
      });

      int uploaded = 0;
      int failed = 0;
      int skipped = 0;
      String? lastError;

      for (final file in result.files) {
        if (_cancelRequested) break;
        if (file.path == null) continue;

        setState(() {
          _transferDone = uploaded + skipped + failed;
          _transferStatus = 'Uploading: ${file.name}';
        });

        try {
          final remotePath = '$_currentPath/${file.name}';

          // Check if file exists on server
          bool fileExists = false;
          try {
            fileExists = await _connectionManager.exists(remotePath);
          } catch (_) {
            // If exists check fails, just try uploading
          }

          if (fileExists) {
            if (!mounted) return;
            final overwrite = await _askOverwrite(file.name);
            if (!overwrite) {
              skipped++;
              continue;
            }
            // Delete existing file on server before overwriting
            try {
              await _connectionManager.deleteFile(remotePath);
            } catch (e) {
              debugPrint('Could not delete existing file: $e');
              // Try uploading anyway
            }
          }

          await _connectionManager.uploadFile(
            localPath: file.path!,
            remotePath: remotePath,
          );
          uploaded++;
          setState(() => _transferDone = uploaded + skipped + failed);
        } catch (e) {
          failed++;
          lastError = e.toString().replaceAll('Exception: ', '');
          debugPrint('Upload failed for ${file.name}: $e');
        }
      }

      if (!mounted) return;
      setState(() => _isTransferring = false);

      final parts = <String>[];
      if (uploaded > 0) parts.add('$uploaded uploaded');
      if (skipped > 0) parts.add('$skipped skipped');
      if (failed > 0) parts.add('$failed failed');
      if (_cancelRequested) parts.add('cancelled');

      String message = parts.join(', ');
      if (failed > 0 && lastError != null) {
        message += '\nError: $lastError';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
      _loadDirectory(_currentPath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTransferring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Upload error: ${e.toString().replaceAll("Exception: ", "")}',
          ),
        ),
      );
    }
  }

  // --- Download ---
  Future<void> _downloadFile(FileItemModel file) async {
    if (file.isDirectory) return;

    if (!await _ensureStoragePermission()) return;

    try {
      final downloadDir = await _getDownloadDir();
      final localPath = '${downloadDir.path}/${file.name}';
      debugPrint('Download target: $localPath');

      // Check if local file already exists
      final localFile = File(localPath);
      if (await localFile.exists()) {
        if (!mounted) return;
        final overwrite = await _askOverwrite(file.name);
        if (!overwrite) return;
      }

      setState(() {
        _isTransferring = true;
        _cancelRequested = false;
        _transferDone = 0;
        _transferTotal = 1;
        _transferStatus = 'Downloading: ${file.name}';
      });

      await _connectionManager.downloadFile(
        remotePath: file.path,
        localPath: localPath,
      );

      // Notify Android MediaScanner so file appears in file manager
      await _scanFile(localPath);

      if (!mounted) return;
      setState(() => _isTransferring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded: ${file.name}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () => OpenFilex.open(localPath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTransferring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Download failed: ${e.toString().replaceAll('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _downloadSelected() async {
    final files = _selectedFiles.where((f) => !f.isDirectory).toList();
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No files selected (folders are skipped)'),
        ),
      );
      return;
    }

    if (!await _ensureStoragePermission()) return;

    setState(() {
      _isTransferring = true;
      _cancelRequested = false;
      _transferDone = 0;
      _transferTotal = files.length;
      _transferStatus = 'Downloading...';
    });

    int downloaded = 0;
    int failed = 0;

    final downloadDir = await _getDownloadDir();

    for (final file in files) {
      if (_cancelRequested) break;

      setState(() {
        _transferDone = downloaded + failed;
        _transferStatus = 'Downloading: ${file.name}';
      });

      try {
        final localPath = '${downloadDir.path}/${file.name}';
        debugPrint('Batch download target: $localPath');
        await _connectionManager.downloadFile(
          remotePath: file.path,
          localPath: localPath,
        );
        downloaded++;
        setState(() => _transferDone = downloaded + failed);
      } catch (e) {
        failed++;
        debugPrint('Download failed for ${file.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isTransferring = false);
    _exitSelectionMode();

    final dirPath = downloadDir.path;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Downloaded $downloaded file(s)${failed > 0 ? ', $failed failed' : ''}${_cancelRequested ? ' (cancelled)' : ''}',
        ),
        duration: const Duration(seconds: 5),
        action: downloaded > 0
            ? SnackBarAction(
                label: 'OPEN FOLDER',
                onPressed: () => OpenFilex.open(dirPath),
              )
            : null,
      ),
    );
  }

  // --- Delete Selected ---
  Future<void> _deleteSelected() async {
    final files = _selectedFiles;
    if (files.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected'),
        content: Text('Delete ${files.length} item(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isTransferring = true;
      _transferStatus = 'Deleting...';
    });

    int deleted = 0;
    int failed = 0;

    for (final file in files) {
      try {
        bool result;
        if (file.isDirectory) {
          result = await _connectionManager.deleteDirectory(file.path);
        } else {
          result = await _connectionManager.deleteFile(file.path);
        }
        if (result) {
          deleted++;
        } else {
          failed++;
        }
      } catch (e) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _isTransferring = false);
    _exitSelectionMode();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Deleted $deleted item(s)${failed > 0 ? ', $failed failed' : ''}',
        ),
      ),
    );
    _loadDirectory(_currentPath);
  }

  // --- Copy / Move ---
  void _copySelected() {
    final files = _selectedFiles;
    if (files.isEmpty) return;

    setState(() {
      _clipboard = _ClipboardData(
        files: List.from(files),
        action: _ClipboardAction.copy,
        sourcePath: _currentPath,
      );
    });
    _exitSelectionMode();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${files.length} item(s) copied. Navigate to destination and paste.',
        ),
      ),
    );
  }

  void _moveSelected() {
    final files = _selectedFiles;
    if (files.isEmpty) return;

    setState(() {
      _clipboard = _ClipboardData(
        files: List.from(files),
        action: _ClipboardAction.move,
        sourcePath: _currentPath,
      );
    });
    _exitSelectionMode();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${files.length} item(s) cut. Navigate to destination and paste.',
        ),
      ),
    );
  }

  Future<void> _paste() async {
    if (_clipboard == null) return;

    final actionName = _clipboard!.action == _ClipboardAction.move
        ? 'Moved'
        : 'Copied';

    setState(() {
      _isTransferring = true;
      _transferStatus = 'Pasting...';
    });

    int succeeded = 0;
    int failed = 0;
    int skipped = 0;

    for (final file in _clipboard!.files) {
      final newPath = '$_currentPath/${file.name}';

      try {
        // Check if file already exists at destination
        bool fileExists = false;
        try {
          fileExists = await _connectionManager.exists(newPath);
        } catch (_) {}

        if (fileExists) {
          if (!mounted) return;
          final overwrite = await _askOverwrite(file.name);
          if (!overwrite) {
            skipped++;
            continue;
          }
          // Delete existing file at destination
          try {
            await _connectionManager.deleteFile(newPath);
          } catch (_) {}
        }

        if (_clipboard!.action == _ClipboardAction.move) {
          final result = await _connectionManager.rename(file.path, newPath);
          result ? succeeded++ : failed++;
        } else {
          // Copy: download temp, upload to new location
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/${file.name}';

          if (file.isDirectory) {
            failed++;
            continue;
          }

          await _connectionManager.downloadFile(
            remotePath: file.path,
            localPath: tempPath,
          );
          await _connectionManager.uploadFile(
            localPath: tempPath,
            remotePath: newPath,
          );

          // Clean up temp file
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
          succeeded++;
        }
      } catch (e) {
        failed++;
        debugPrint('Paste failed for ${file.name}: $e');
      }
    }

    if (!mounted) return;

    setState(() {
      _isTransferring = false;
      _clipboard = null;
    });

    final parts = <String>[];
    if (succeeded > 0) parts.add('$actionName $succeeded');
    if (skipped > 0) parts.add('$skipped skipped');
    if (failed > 0) parts.add('$failed failed');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(parts.join(', '))));
    _loadDirectory(_currentPath);
  }

  // --- Copy/Move single file from context menu ---
  void _copySingle(FileItemModel file) {
    setState(() {
      _clipboard = _ClipboardData(
        files: [file],
        action: _ClipboardAction.copy,
        sourcePath: _currentPath,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${file.name}" copied. Navigate to destination and paste.',
        ),
      ),
    );
  }

  void _moveSingle(FileItemModel file) {
    setState(() {
      _clipboard = _ClipboardData(
        files: [file],
        action: _ClipboardAction.move,
        sourcePath: _currentPath,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${file.name}" cut. Navigate to destination and paste.'),
      ),
    );
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pathHistory.length <= 1 && !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          _exitSelectionMode();
        } else {
          _navigateUp();
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(),
        body: _buildBody(),
        floatingActionButton:
            (!_isConnecting && _errorMessage == null && !_isSelectionMode)
            ? FloatingActionButton(
                onPressed: _uploadFiles,
                child: const Icon(Icons.upload_file),
              )
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: Text(widget.connection.name),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () async {
          if (_pathHistory.length > 1) {
            _navigateUp();
          } else {
            await _connectionManager.disconnect();
            if (mounted) Navigator.pop(context);
          }
        },
      ),
      actions: [
        if (!_isConnecting && _errorMessage == null) ...[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDirectory(_currentPath),
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_folder',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder),
                  title: Text('New Folder'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'select',
                child: ListTile(
                  leading: Icon(Icons.checklist),
                  title: Text('Select Items'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_clipboard != null)
                PopupMenuItem(
                  value: 'paste',
                  child: ListTile(
                    leading: const Icon(Icons.paste),
                    title: Text('Paste (${_clipboard!.files.length})'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'sort',
                child: ListTile(
                  leading: Icon(Icons.sort),
                  title: Text('Sort'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'disconnect',
                child: ListTile(
                  leading: Icon(Icons.link_off, color: Colors.red),
                  title: Text(
                    'Disconnect',
                    style: TextStyle(color: Colors.red),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'new_folder':
                  _showCreateFolderDialog();
                  break;
                case 'select':
                  setState(() => _isSelectionMode = true);
                  break;
                case 'paste':
                  _paste();
                  break;
                case 'sort':
                  _showSortDialog();
                  break;
                case 'disconnect':
                  _connectionManager.disconnect();
                  Navigator.pop(context);
                  break;
              }
            },
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedPaths.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Select All',
          onPressed: _selectAll,
        ),
        // Download selected files
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Download',
          onPressed: _selectedPaths.isNotEmpty ? _downloadSelected : null,
        ),
        // More actions
        PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                leading: Icon(Icons.copy),
                title: Text('Copy'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'move',
              child: ListTile(
                leading: Icon(Icons.content_cut),
                title: Text('Move'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'copy':
                _copySelected();
                break;
              case 'move':
                _moveSelected();
                break;
              case 'delete':
                _deleteSelected();
                break;
            }
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    // Transfer overlay
    if (_isTransferring) {
      final pct = _transferTotal > 0
          ? (_transferDone / _transferTotal * 100).round()
          : 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_transferTotal > 0) ...[
                Text(
                  '$_transferDone / $_transferTotal files',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _transferTotal > 0
                      ? _transferDone / _transferTotal
                      : null,
                ),
                const SizedBox(height: 8),
                Text('$pct%', style: Theme.of(context).textTheme.bodyLarge),
              ] else
                const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _transferStatus,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel, color: Colors.red),
                label: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: _cancelRequested ? null : _cancelTransfer,
              ),
            ],
          ),
        ),
      );
    }

    // Connecting state
    if (_isConnecting && _errorMessage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Connecting to ${widget.connection.host}...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.connection.protocol.displayName} • Port ${widget.connection.port}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    // Error state
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Connection Failed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed: _connect,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // File list
    return Column(
      children: [
        _buildBreadcrumbs(),
        // Clipboard banner
        if (_clipboard != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primary.withAlpha(30),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _clipboard!.action == _ClipboardAction.copy
                      ? Icons.copy
                      : Icons.content_cut,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_clipboard!.files.length} item(s) ${_clipboard!.action == _ClipboardAction.copy ? 'copied' : 'cut'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(onPressed: _paste, child: const Text('PASTE HERE')),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _clipboard = null),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        if (_isLoading) const LinearProgressIndicator(),
        Expanded(
          child: _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Empty directory',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadDirectory(_currentPath),
                  child: ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) =>
                        _buildFileItem(_files[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                _pathHistory = ['/'];
                _loadDirectory('/');
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: parts.isEmpty
                      ? Theme.of(context).colorScheme.primary.withAlpha(40)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.home, size: 16),
                    SizedBox(width: 4),
                    Text('/'),
                  ],
                ),
              ),
            ),
            for (int i = 0; i < parts.length; i++) ...[
              const Icon(Icons.chevron_right, size: 16),
              InkWell(
                onTap: () {
                  final targetPath = '/${parts.sublist(0, i + 1).join('/')}';
                  _pathHistory = ['/'];
                  for (int j = 0; j <= i; j++) {
                    _pathHistory.add('/${parts.sublist(0, j + 1).join('/')}');
                  }
                  _loadDirectory(targetPath);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: i == parts.length - 1
                        ? Theme.of(context).colorScheme.primary.withAlpha(40)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(parts[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(FileItemModel file) {
    final isSelected = _selectedPaths.contains(file.path);

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(file);
        } else if (file.isDirectory) {
          _navigateTo(file.path);
        } else {
          _showFileInfoDialog(file);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          _enterSelectionMode(file);
        }
      },
      child: Container(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withAlpha(30)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Checkbox in selection mode, otherwise file icon
            if (_isSelectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelection(file),
              )
            else
              Icon(
                file.icon,
                size: 32,
                color: file.isDirectory
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
              ),
            const SizedBox(width: 16),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (!file.isDirectory)
                        Text(
                          file.formattedSize,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (!file.isDirectory && file.modifiedDate != null)
                        Text(
                          ' • ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (file.modifiedDate != null)
                        Text(
                          DateFormat(
                            'MMM dd, yyyy HH:mm',
                          ).format(file.modifiedDate!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // 3-dot menu (not in selection mode)
            if (!_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () => _showFileActions(file),
              ),
          ],
        ),
      ),
    );
  }

  void _showFileActions(FileItemModel file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(file.icon, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!file.isDirectory)
                            Text(
                              file.formattedSize,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (file.isDirectory)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Open'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(file.path);
                  },
                ),
              if (!file.isDirectory)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _downloadFile(file);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copySingle(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_cut),
                title: const Text('Move'),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveSingle(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameDialog(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFileInfoDialog(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteDialog(file);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== DIALOGS =====================

  void _showFileInfoDialog(FileItemModel file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Type', file.isDirectory ? 'Directory' : 'File'),
            _infoRow('Path', file.path),
            if (!file.isDirectory) _infoRow('Size', file.formattedSize),
            if (file.modifiedDate != null)
              _infoRow(
                'Modified',
                DateFormat('MMM dd, yyyy HH:mm').format(file.modifiedDate!),
              ),
            if (file.permissions != null)
              _infoRow('Permissions', file.permissions!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                final result = await _connectionManager.createDirectory(
                  _currentPath,
                  name,
                );
                if (result && mounted) {
                  _loadDirectory(_currentPath);
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create folder')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(FileItemModel file) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != file.name) {
                Navigator.pop(context);
                final newPath = '$_currentPath/$newName';
                final result = await _connectionManager.rename(
                  file.path,
                  newPath,
                );
                if (result && mounted) {
                  _loadDirectory(_currentPath);
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to rename')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(FileItemModel file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Are you sure you want to delete "${file.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              bool result;
              if (file.isDirectory) {
                result = await _connectionManager.deleteDirectory(file.path);
              } else {
                result = await _connectionManager.deleteFile(file.path);
              }
              if (result && mounted) {
                _loadDirectory(_currentPath);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
