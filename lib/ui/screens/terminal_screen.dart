/// SSH Terminal - interactive PTY shell rendered with xterm.
///
/// Output streams straight into the emulator; history, tab completion and
/// full-screen programs (top, nano, vim) work because it's a real shell.
/// An extra-keys row supplies keys missing from phone keyboards.
import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../../models/connection_model.dart';
import '../../services/ssh_service.dart';

class TerminalScreen extends StatefulWidget {
  final ConnectionModel connection;

  const TerminalScreen({super.key, required this.connection});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalController _controller = TerminalController();
  late final SshService _ssh = SshService(widget.connection);
  SSHSession? _session;
  bool _connecting = true;
  bool _closed = false;
  bool _ctrl = false;
  bool _alt = false;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) {
      // Apply sticky Ctrl/Alt from the extra-keys row to typed characters
      if ((_ctrl || _alt) && data.length == 1) {
        final key = _letterKey(data);
        if (key != null) {
          _terminal.keyInput(key, ctrl: _ctrl, alt: _alt);
          setState(() => _ctrl = _alt = false);
          return;
        }
      }
      _session?.write(utf8.encode(data));
    };
    _terminal.onResize = (w, h, pw, ph) {
      _session?.resizeTerminal(w, h, pw, ph);
    };
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _closed = false;
    });
    _terminal.write('Connecting to ${widget.connection.host}...\r\n');
    try {
      final session = await _ssh.shell(
        width: _terminal.viewWidth,
        height: _terminal.viewHeight,
      );
      _session = session;
      // The view may have been laid out while we were connecting
      session.resizeTerminal(_terminal.viewWidth, _terminal.viewHeight);
      if (!mounted) return;
      setState(() => _connecting = false);

      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
      session.done.then((_) {
        if (!mounted) return;
        _terminal.write('\r\n[Session closed]\r\n');
        setState(() => _closed = true);
      });
    } catch (e) {
      if (!mounted) return;
      _terminal.write(
        '\r\n\x1b[31mConnection failed: '
        '${e.toString().replaceAll('Exception: ', '')}\x1b[0m\r\n',
      );
      setState(() {
        _connecting = false;
        _closed = true;
      });
    }
  }

  Future<void> _reconnect() async {
    _session?.close();
    _ssh.close();
    _terminal.write('\r\n');
    await _connect();
  }

  @override
  void dispose() {
    _session?.close();
    _ssh.close();
    _controller.dispose();
    super.dispose();
  }

  static TerminalKey? _letterKey(String ch) {
    final c = ch.toLowerCase().codeUnitAt(0);
    if (c < 0x61 || c > 0x7a) return null;
    return TerminalKey.values.byName('key${String.fromCharCode(c).toUpperCase()}');
  }

  void _sendKey(TerminalKey key) {
    _terminal.keyInput(key, ctrl: _ctrl, alt: _alt);
    if (_ctrl || _alt) setState(() => _ctrl = _alt = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060914),
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Terminal'),
            Text(
              '${widget.connection.username}@${widget.connection.host}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_closed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: _reconnect,
            ),
        ],
        bottom: _connecting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TerminalView(
                _terminal,
                controller: _controller,
                autofocus: true,
                backgroundOpacity: 0,
                padding: const EdgeInsets.all(6),
                textStyle: const TerminalStyle(fontSize: 13),
                theme: _theme,
              ),
            ),
            _ExtraKeys(
              ctrl: _ctrl,
              alt: _alt,
              onCtrl: () => setState(() => _ctrl = !_ctrl),
              onAlt: () => setState(() => _alt = !_alt),
              onKey: _sendKey,
              onText: (t) => _terminal.textInput(t),
            ),
          ],
        ),
      ),
    );
  }

  static const _theme = TerminalTheme(
    cursor: Color(0xFFB4A9FF),
    selection: Color(0x806D5DFC),
    foreground: Color(0xFFD7DBEA),
    background: Color(0xFF060914),
    black: Color(0xFF1C2340),
    red: Color(0xFFF87171),
    green: Color(0xFF4ADE80),
    yellow: Color(0xFFFACC15),
    blue: Color(0xFF60A5FA),
    magenta: Color(0xFFC084FC),
    cyan: Color(0xFF22D3EE),
    white: Color(0xFFD7DBEA),
    brightBlack: Color(0xFF6B7280),
    brightRed: Color(0xFFFCA5A5),
    brightGreen: Color(0xFF86EFAC),
    brightYellow: Color(0xFFFDE68A),
    brightBlue: Color(0xFF93C5FD),
    brightMagenta: Color(0xFFD8B4FE),
    brightCyan: Color(0xFF67E8F9),
    brightWhite: Colors.white,
    searchHitBackground: Color(0xFFFACC15),
    searchHitBackgroundCurrent: Color(0xFF4ADE80),
    searchHitForeground: Colors.black,
  );
}

/// Esc / Tab / Ctrl / Alt / arrows / symbols that phone keyboards hide
class _ExtraKeys extends StatelessWidget {
  final bool ctrl;
  final bool alt;
  final VoidCallback onCtrl;
  final VoidCallback onAlt;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<String> onText;

  const _ExtraKeys({
    required this.ctrl,
    required this.alt,
    required this.onCtrl,
    required this.onAlt,
    required this.onKey,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget key(String label, VoidCallback onTap, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: active ? accent : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 42),
              height: 38,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : null,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            key('Esc', () => onKey(TerminalKey.escape)),
            key('Tab', () => onKey(TerminalKey.tab)),
            key('Ctrl', onCtrl, active: ctrl),
            key('Alt', onAlt, active: alt),
            key('↑', () => onKey(TerminalKey.arrowUp)),
            key('↓', () => onKey(TerminalKey.arrowDown)),
            key('←', () => onKey(TerminalKey.arrowLeft)),
            key('→', () => onKey(TerminalKey.arrowRight)),
            for (final s in ['|', '/', '-', '~', '>', '&', r'$', '*'])
              key(s, () => onText(s)),
            key('Home', () => onKey(TerminalKey.home)),
            key('End', () => onKey(TerminalKey.end)),
            key('PgUp', () => onKey(TerminalKey.pageUp)),
            key('PgDn', () => onKey(TerminalKey.pageDown)),
          ],
        ),
      ),
    );
  }
}
