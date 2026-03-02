import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/connection_manager.dart';

/// Text file extensions that can be opened in the editor
const textExtensions = {
  // Code
  'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'java', 'kt', 'c', 'cpp', 'h',
  'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'swift', 'lua', 'pl', 'sh', 'bash',
  'zsh', 'bat', 'ps1', 'r', 'scala', 'ex', 'exs', 'hs', 'sql',
  // Web
  'html', 'htm', 'css', 'scss', 'sass', 'less', 'vue', 'svelte',
  // Config
  'json', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'env', 'properties',
  'xml', 'plist', 'gradle',
  // Text / Docs
  'txt', 'md', 'rst', 'csv', 'tsv', 'log', 'gitignore', 'dockerignore',
  'editorconfig', 'htaccess',
  // Build / CI
  'dockerfile', 'makefile', 'cmake', 'gemfile', 'rakefile',
};

/// Returns true if the file extension is a known text file
bool isTextFile(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  final baseName = fileName.toLowerCase();
  // Check extension OR well-known filenames
  return textExtensions.contains(ext) ||
      {
        'makefile',
        'dockerfile',
        'gemfile',
        'rakefile',
        'procfile',
        'license',
        'readme',
        'changelog',
        '.gitignore',
        '.dockerignore',
        '.env',
        '.editorconfig',
        '.htaccess',
      }.contains(baseName);
}

class TextEditorScreen extends StatefulWidget {
  final String remotePath;
  final String fileName;
  final ConnectionManager connectionManager;

  const TextEditorScreen({
    super.key,
    required this.remotePath,
    required this.fileName,
    required this.connectionManager,
  });

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _editorFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _isSearching = false;
  bool _isReadOnly = false;
  String? _error;
  String _originalContent = '';
  String? _localTempPath;
  int _lineCount = 1;

  // Search state
  List<int> _searchMatches = [];
  int _currentMatchIndex = -1;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFile();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _editorFocus.dispose();
    _searchController.dispose();
    // Clean up temp file
    if (_localTempPath != null) {
      File(_localTempPath!).delete().catchError((_) => File(''));
    }
    super.dispose();
  }

  void _onTextChanged() {
    final newContent = _controller.text;
    final changed = newContent != _originalContent;
    final lines = '\n'.allMatches(newContent).length + 1;
    if (changed != _hasChanges || lines != _lineCount) {
      setState(() {
        _hasChanges = changed;
        _lineCount = lines;
      });
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      _localTempPath =
          '${tempDir.path}/ftp_editor_${DateTime.now().millisecondsSinceEpoch}_${widget.fileName}';

      await widget.connectionManager.downloadFile(
        remotePath: widget.remotePath,
        localPath: _localTempPath!,
      );

      final file = File(_localTempPath!);
      final content = await file.readAsString();

      if (!mounted) return;
      setState(() {
        _originalContent = content;
        _controller.text = content;
        _lineCount = '\n'.allMatches(content).length + 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Try reading as binary — might not be a text file
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFile() async {
    if (!_hasChanges || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      // Write content to temp file
      final file = File(_localTempPath!);
      await file.writeAsString(_controller.text);

      // Upload back to server
      await widget.connectionManager.uploadFile(
        localPath: _localTempPath!,
        remotePath: widget.remotePath,
      );

      if (!mounted) return;
      setState(() {
        _originalContent = _controller.text;
        _hasChanges = false;
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${widget.fileName}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Save failed: ${e.toString().replaceAll("Exception: ", "")}',
          ),
        ),
      );
    }
  }

  // ================= SEARCH =================
  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
        _searchMatches.clear();
        _currentMatchIndex = -1;
      }
    });
  }

  void _performSearch(String query) {
    _searchQuery = query;
    _searchMatches.clear();
    _currentMatchIndex = -1;

    if (query.isEmpty) {
      setState(() {});
      return;
    }

    final text = _controller.text.toLowerCase();
    final q = query.toLowerCase();
    int start = 0;
    while (true) {
      final idx = text.indexOf(q, start);
      if (idx == -1) break;
      _searchMatches.add(idx);
      start = idx + 1;
    }

    if (_searchMatches.isNotEmpty) {
      _currentMatchIndex = 0;
      _goToMatch(0);
    }
    setState(() {});
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatches.length;
    _goToMatch(_currentMatchIndex);
    setState(() {});
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _searchMatches.length) %
        _searchMatches.length;
    _goToMatch(_currentMatchIndex);
    setState(() {});
  }

  void _goToMatch(int matchIndex) {
    final pos = _searchMatches[matchIndex];
    _controller.selection = TextSelection(
      baseOffset: pos,
      extentOffset: pos + _searchQuery.length,
    );
    _editorFocus.requestFocus();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final save = await _showUnsavedDialog();
        if (!mounted) return;
        if (save == true) {
          await _saveFile();
          if (mounted) Navigator.pop(context);
        } else if (save == false) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(appBar: _buildAppBar(), body: _buildBody()),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.fileName, style: const TextStyle(fontSize: 16)),
          Text(
            _hasChanges ? 'Modified' : '$_lineCount lines',
            style: TextStyle(
              fontSize: 12,
              color: _hasChanges ? Colors.orange : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        if (!_isLoading && _error == null) ...[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: Icon(_isReadOnly ? Icons.lock : Icons.edit),
            tooltip: _isReadOnly ? 'Read Only' : 'Editable',
            onPressed: () => setState(() => _isReadOnly = !_isReadOnly),
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: 'Save to server',
            onPressed: _hasChanges && !_isSaving ? _saveFile : null,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading file...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to load file',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadFile,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        if (_isSearching) _buildSearchBar(),
        // Editor with line numbers
        Expanded(child: _buildEditor()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search...',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                suffixText: _searchMatches.isNotEmpty
                    ? '${_currentMatchIndex + 1}/${_searchMatches.length}'
                    : null,
              ),
              onChanged: _performSearch,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            onPressed: _searchMatches.isNotEmpty ? _prevMatch : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 20),
            onPressed: _searchMatches.isNotEmpty ? _nextMatch : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _toggleSearch,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final lineNumWidth = (_lineCount.toString().length * 10.0 + 24).clamp(
      40.0,
      80.0,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line numbers gutter
        Container(
          width: lineNumWidth,
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: List.generate(_lineCount, (i) {
                  return SizedBox(
                    height: 20.0,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.grey[600] : Colors.grey[500],
                        height: 1.5,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        // Vertical divider
        Container(
          width: 1,
          color: isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
        ),
        // Code editor
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: _controller,
                focusNode: _editorFocus,
                readOnly: _isReadOnly,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.5,
                  color: isDark
                      ? const Color(0xFFD4D4D4)
                      : const Color(0xFF1E1E1E),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.only(top: 8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<bool?> _showUnsavedDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved changes. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
