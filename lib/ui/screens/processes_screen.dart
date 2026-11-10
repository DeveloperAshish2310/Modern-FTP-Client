/// Processes - top processes by CPU or memory, with search and kill.
///
/// Refreshes every few seconds while open. Killing another user's process
/// is retried through sudo; failures are explained instead of swallowed.
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/connection_model.dart';
import '../../services/ssh_service.dart';
import '../widgets/server_widgets.dart';

class _Process {
  final int pid;
  final String user;
  final double cpu;
  final double mem;
  final int rssKb;
  final String command;

  _Process(this.pid, this.user, this.cpu, this.mem, this.rssKb, this.command);
}

class ProcessesScreen extends StatefulWidget {
  final ConnectionModel connection;
  final SshService ssh;

  const ProcessesScreen({
    super.key,
    required this.connection,
    required this.ssh,
  });

  @override
  State<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends State<ProcessesScreen> {
  static const _refreshInterval = Duration(seconds: 5);
  static const _limit = 100;

  SshService get _ssh => widget.ssh;

  bool _loading = true;
  bool _refreshing = false;
  ToolMessage? _problem;
  List<_Process> _processes = [];
  bool _sortByMemory = false;
  String _query = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) {
      if (_problem == null) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _problem = null;
      });
    }
    try {
      final sort = _sortByMemory ? '-pmem' : '-pcpu';
      // Trailing '=' drops the header; comm is last so spaces stay intact
      final r = await _ssh.run(
        // First line is this shell's PID so the probe can hide itself
        'echo \$\$; ps -eo pid=,ppid=,user:32=,pcpu=,pmem=,rss=,comm= '
        '--sort=$sort | head -n ${_limit + 3}',
      );
      if (!r.success || r.stdout.trim().isEmpty) {
        _fail(
          Icons.error_outline,
          'Couldn\'t list processes',
          r.commandNotFound || r.stderr.contains('unrecognized')
              ? 'This server\'s ps doesn\'t support the options needed '
                    '(it may be BusyBox).'
              : r.message,
        );
        return;
      }

      final lines = r.stdout.split('\n');
      final selfPid = int.tryParse(lines.first.trim());
      final processes = <_Process>[];
      for (final line in lines.skip(1)) {
        final f = line.trim().split(RegExp(r'\s+'));
        if (f.length < 7) continue;
        final pid = int.tryParse(f[0]);
        if (pid == null) continue;
        // Hide the shell running this probe and its ps/head children
        if (pid == selfPid || int.tryParse(f[1]) == selfPid) continue;
        processes.add(
          _Process(
            pid,
            f[2],
            double.tryParse(f[3]) ?? 0,
            double.tryParse(f[4]) ?? 0,
            int.tryParse(f[5]) ?? 0,
            f.sublist(6).join(' '),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _processes = processes;
        _loading = false;
        _problem = null;
      });
    } catch (e) {
      if (!silent) {
        _fail(
          Icons.cloud_off,
          'Connection problem',
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  void _fail(IconData icon, String title, String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _problem = ToolMessage(
        icon: icon,
        title: title,
        message: message,
        onRetry: _load,
      );
    });
  }

  Future<void> _kill(_Process p, {required bool force}) async {
    final signal = force ? 'KILL' : 'TERM';
    final ok = await confirmAction(
      context,
      title: '${force ? 'Force kill' : 'Kill'} ${p.command}?',
      message: force
          ? 'PID ${p.pid} will be stopped immediately (SIGKILL) without a '
                'chance to clean up.'
          : 'PID ${p.pid} will be asked to exit (SIGTERM).',
      action: force ? 'Force kill' : 'Kill',
    );
    if (!ok || !mounted) return;
    await runAction(context, () async {
      // Another user's process: runElevated retries with sudo
      final r = await _ssh.runElevated('kill -$signal ${p.pid}');
      if (r.success) return null;
      if (r.sudoFailed || r.permissionDenied) {
        return describeSudoFailure(_ssh, r);
      }
      return r.message;
    }, success: 'Sent SIG$signal to ${p.command} (${p.pid})');
    _load(silent: true);
  }

  void _showDetails(_Process p) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.command, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'PID ${p.pid} • ${p.user}\n'
                'CPU ${p.cpu.toStringAsFixed(1)}% • '
                'Memory ${p.mem.toStringAsFixed(1)}% '
                '(${formatBytes(p.rssKb * 1024)})',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _kill(p, force: false);
                      },
                      child: const Text('Kill'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _kill(p, force: true);
                      },
                      child: const Text('Force kill'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final visible = query.isEmpty
        ? _processes
        : _processes
              .where(
                (p) =>
                    p.command.toLowerCase().contains(query) ||
                    p.user.toLowerCase().contains(query) ||
                    p.pid.toString() == query,
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processes'),
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: false,
                checked: !_sortByMemory,
                child: const Text('By CPU'),
              ),
              CheckedPopupMenuItem(
                value: true,
                checked: _sortByMemory,
                child: const Text('By memory'),
              ),
            ],
            onSelected: (byMemory) {
              setState(() => _sortByMemory = byMemory);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _problem ??
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search name, user or PID...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: visible.length,
                        itemBuilder: (_, i) => _buildProcess(visible[i]),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildProcess(_Process p) {
    final theme = Theme.of(context);
    final cpuColor = p.cpu >= 50
        ? Colors.red
        : p.cpu >= 10
        ? Colors.orange
        : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: () => _showDetails(p),
        title: Text(p.command, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('PID ${p.pid} • ${p.user}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${p.cpu.toStringAsFixed(1)}% CPU',
              style: TextStyle(color: cpuColor, fontWeight: FontWeight.w600),
            ),
            Text(
              formatBytes(p.rssKb * 1024),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
