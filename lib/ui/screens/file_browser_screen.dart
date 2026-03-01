import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/connection_model.dart';
import '../../models/file_item_model.dart';
import '../../providers/connection_provider.dart';
import '../../services/connection_manager.dart';

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
        // Update last used timestamp
        Provider.of<ConnectionProvider>(
          context,
          listen: false,
        ).updateLastUsed(widget.connection.id!);
        await _loadDirectory('/');
      } else {
        setState(() {
          _isConnecting = false;
          _errorMessage =
              'Failed to connect to ${widget.connection.host}.\nPlease check your credentials and server settings.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage =
            'Connection error: ${e.toString().replaceAll('Exception: ', '')}';
      });
      debugPrint('Connection error: $e');
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

      // Sort: directories first, then alphabetically
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

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
      debugPrint('List directory error: $e');
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pathHistory.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _navigateUp();
        }
      },
      child: Scaffold(
        appBar: AppBar(
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
            if (!_isConnecting)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _loadDirectory(_currentPath),
              ),
            if (!_isConnecting)
              PopupMenuButton<String>(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'new_folder',
                    child: Row(
                      children: [
                        Icon(Icons.create_new_folder),
                        SizedBox(width: 8),
                        Text('New Folder'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'disconnect',
                    child: Row(
                      children: [
                        Icon(Icons.link_off, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Disconnect', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'new_folder':
                      _showCreateFolderDialog();
                      break;
                    case 'disconnect':
                      _connectionManager.disconnect();
                      Navigator.pop(context);
                      break;
                  }
                },
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
        // Breadcrumbs
        _buildBreadcrumbs(),
        const Divider(height: 1),
        // Loading indicator
        if (_isLoading) const LinearProgressIndicator(),
        // File list
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
                    itemBuilder: (context, index) {
                      return _buildFileItem(_files[index]);
                    },
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
    return InkWell(
      onTap: () {
        if (file.isDirectory) {
          _navigateTo(file.path);
        } else {
          _showFileInfoDialog(file);
        }
      },
      onLongPress: () => _showFileActions(file),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // File icon
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
            // Action button
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
      builder: (context) => SafeArea(
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
                      child: Text(
                        file.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
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
                    Navigator.pop(context);
                    _navigateTo(file.path);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(context);
                  _showFileInfoDialog(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteDialog(file);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

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
