import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/connection_manager.dart';

/// Binary file extensions that should NOT be opened in the editor
const _binaryExtensions = {
  // Images
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'ico', 'svg', 'tiff', 'tif',
  'heic', 'heif', 'raw', 'cr2', 'nef', 'psd', 'ai',
  // Videos
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', '3gp', 'ts',
  'mpg', 'mpeg', 'vob',
  // Audio
  'mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a', 'opus', 'aiff',
  // Archives
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'zst', 'cab', 'iso', 'dmg',
  // Executables / Binary
  'exe', 'dll', 'so', 'dylib', 'apk', 'aab', 'deb', 'rpm', 'msi', 'app',
  'bin', 'dat', 'class', 'pyc', 'o', 'obj',
  // Documents (binary)
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
  // Fonts
  'ttf', 'otf', 'woff', 'woff2', 'eot',
  // Database
  'db', 'sqlite', 'sqlite3', 'mdb',
};

/// Returns true if the file can be opened in the text editor
bool isTextFile(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return !_binaryExtensions.contains(ext);
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

/// Decode off the UI thread; malformed bytes become U+FFFD instead of throwing
String _decodeText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

class _TextEditorScreenState extends State<TextEditorScreen> {
  // A multi-line TextField lays out its whole text, so big files (often a
  // single multi-MB line, e.g. SQL dumps) freeze the UI. Above these limits
  // the file opens in a lazy read-only viewer instead.
  static const _maxEditBytes = 512 * 1024;
  static const _maxEditLines = 5000;
  static const _maxEditLineLength = 5000;
  static const _maxViewBytes = 20 * 1024 * 1024;
  static const _previewLineChars = 1000;

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
  String _errorTitle = 'Failed to load file';
  static const _wrapPrefKey = 'editor_word_wrap';
  bool _wrap = true;
  int _longestLine = 0;
  bool _largeFile = false;
  List<String> _lines = [];
  int _fileBytes = 0;
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
    _loadWrapPref();
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

  static int _longestLineOf(String text) {
    var longest = 0, start = 0;
    while (true) {
      final nl = text.indexOf('\n', start);
      final end = nl == -1 ? text.length : nl;
      if (end - start > longest) longest = end - start;
      if (nl == -1) return longest;
      start = nl + 1;
    }
  }

  Future<void> _loadWrapPref() async {
    final prefs = await SharedPreferences.getInstance();
    final wrap = prefs.getBool(_wrapPrefKey);
    if (wrap != null && mounted) setState(() => _wrap = wrap);
  }

  Future<void> _toggleWrap() async {
    setState(() => _wrap = !_wrap);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wrapPrefKey, _wrap);
  }

  /// Width of one monospace character in the editor font, for unwrapped
  /// horizontal scrolling
  double _charWidth(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  void _onTextChanged() {
    final newContent = _controller.text;
    final changed = newContent != _originalContent;
    final lines = '\n'.allMatches(newContent).length + 1;
    // Unwrapped width follows the longest line; skip the scan when wrapping
    final longest = _wrap ? _longestLine : _longestLineOf(newContent);
    if (changed != _hasChanges ||
        lines != _lineCount ||
        longest != _longestLine) {
      setState(() {
        _hasChanges = changed;
        _lineCount = lines;
        _longestLine = longest;
      });
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _errorTitle = 'Failed to load file';
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
      _fileBytes = await file.length();
      if (_fileBytes > _maxViewBytes) {
        if (!mounted) return;
        setState(() {
          _errorTitle = 'File too large to open';
          _error =
              'This file is ${_formatSize(_fileBytes)}. Files over '
              '${_formatSize(_maxViewBytes)} can\'t be opened here; '
              'download it instead.';
          _isLoading = false;
        });
        return;
      }

      final content = await compute(_decodeText, await file.readAsBytes());
      final lines = content.split('\n');
      final longestLine = lines.fold<int>(
        0,
        (m, l) => l.length > m ? l.length : m,
      );
      final large =
          _fileBytes > _maxEditBytes ||
          lines.length > _maxEditLines ||
          longestLine > _maxEditLineLength;

      if (!mounted) return;
      setState(() {
        _largeFile = large;
        _lineCount = lines.length;
        _longestLine = longestLine;
        if (large) {
          _lines = lines;
          _isReadOnly = true;
        } else {
          _originalContent = content;
          _controller.text = content;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
            _hasChanges
                ? 'Modified'
                : _largeFile
                ? '$_lineCount lines • ${_formatSize(_fileBytes)} • read-only'
                : '$_lineCount lines',
            style: TextStyle(
              fontSize: 12,
              color: _hasChanges ? Colors.orange : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        if (!_isLoading && _error == null)
          IconButton(
            icon: Icon(_wrap ? Icons.wrap_text : Icons.notes),
            tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
            onPressed: _toggleWrap,
          ),
        if (!_isLoading && _error == null && !_largeFile) ...[
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
              Text(_errorTitle, style: Theme.of(context).textTheme.titleMedium),
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

    if (_largeFile) return _buildLargeViewer();

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

  // Shared by the gutter and the text so line numbers stay aligned
  static const _fontSize = 13.0;
  static const _lineHeight = 1.5;
  static const _strut = StrutStyle(
    fontSize: _fontSize,
    height: _lineHeight,
    forceStrutHeight: true,
  );

  TextStyle _editorTextStyle(bool isDark) => TextStyle(
    fontSize: _fontSize,
    fontFamily: 'monospace',
    height: _lineHeight,
    color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
  );

  Widget _buildEditor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStyle = _editorTextStyle(isDark);

    final editor = TextField(
      controller: _controller,
      focusNode: _editorFocus,
      readOnly: _isReadOnly,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: textStyle,
      strutStyle: _strut,
      decoration: const InputDecoration(
        // The app theme fills and outlines inputs; an editor wants neither
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    );

    // Wrapped lines span several rows, so a per-line gutter can't line up
    if (_wrap) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: editor,
      );
    }

    final lineNumWidth = (_lineCount.toString().length * 10.0 + 24).clamp(
      40.0,
      80.0,
    );
    // Room for the longest line plus a little slack to type at its end
    final textWidth = (_longestLine + 4) * _charWidth(textStyle) + 16;

    return SingleChildScrollView(
      controller: _scrollController,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers gutter: same strut as the text, same scroll view
          Container(
            width: lineNumWidth,
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
            padding: const EdgeInsets.only(top: 12, bottom: 12, right: 6),
            child: Text(
              List.generate(_lineCount, (i) => '${i + 1}').join('\n'),
              textAlign: TextAlign.right,
              strutStyle: _strut,
              style: textStyle.copyWith(
                color: isDark ? Colors.grey[600] : Colors.grey[500],
              ),
            ),
          ),
          Container(
            width: 1,
            color: isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: textWidth > constraints.maxWidth - 16
                      ? textWidth
                      : constraints.maxWidth - 16,
                  child: editor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Read-only viewer for large files: builds only the visible lines and
  /// shortens very long ones, so layout cost stays bounded
  Widget _buildLargeViewer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final numberStyle = TextStyle(
      fontSize: 12,
      fontFamily: 'monospace',
      color: isDark ? Colors.grey[600] : Colors.grey[500],
    );
    final textStyle = TextStyle(
      fontSize: 13,
      fontFamily: 'monospace',
      height: 1.4,
      color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
    );
    final numberWidth = _lineCount.toString().length * 8.0 + 16;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.orange.withValues(alpha: 0.15),
          child: Text(
            'Large file: opened read-only. Lines longer than '
            '$_previewLineChars characters are shortened. Download the file '
            'to see or edit all of it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Unwrapped: lines are capped at _previewLineChars, so a fixed
              // content width is enough for horizontal scrolling
              final shownLongest = _longestLine > _previewLineChars
                  ? _previewLineChars + 30
                  : _longestLine;
              final contentWidth = _wrap
                  ? constraints.maxWidth
                  : (numberWidth +
                            16 +
                            (shownLongest + 2) * _charWidth(textStyle))
                        .clamp(constraints.maxWidth, double.infinity);

              final list = ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final line = _lines[i];
                  final shown = line.length > _previewLineChars
                      ? '${line.substring(0, _previewLineChars)} … '
                            '(+${line.length - _previewLineChars} chars)'
                      : line;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: numberWidth,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: numberStyle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          shown,
                          style: textStyle,
                          softWrap: _wrap,
                          maxLines: _wrap ? null : 1,
                        ),
                      ),
                    ],
                  );
                },
              );

              if (_wrap) return Scrollbar(child: list);
              return Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: contentWidth, child: list),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
