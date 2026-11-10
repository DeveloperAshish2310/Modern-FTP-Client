/// Docker - list containers with live CPU/memory, start/stop/restart, logs.
///
/// Falls back to `sudo docker` when the SSH user isn't in the docker group,
/// and explains clearly when Docker is missing, stopped or not permitted.
import 'package:flutter/material.dart';
import '../../models/connection_model.dart';
import '../../services/ssh_service.dart';
import '../widgets/server_widgets.dart';
import '../widgets/trigger_widgets.dart';

class _Container {
  final String id;
  final String name;
  final String image;
  final String state; // running, exited, paused, restarting, created, dead
  final String status; // "Up 3 hours", "Exited (0) 2 days ago"
  final String ports;

  _Container(this.id, this.name, this.image, this.state, this.status, this.ports);

  bool get running => state == 'running';
}

class DockerScreen extends StatefulWidget {
  final ConnectionModel connection;
  final SshService ssh;

  const DockerScreen({super.key, required this.connection, required this.ssh});

  @override
  State<DockerScreen> createState() => _DockerScreenState();
}

class _DockerScreenState extends State<DockerScreen> {
  // '|' separates fields; none of these columns contain it
  static const _psFormat =
      '{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}';
  static const _statsFormat = '{{.ID}}|{{.CPUPerc}}|{{.MemUsage}}';

  SshService get _ssh => widget.ssh;

  bool _loading = true;
  ToolMessage? _problem;
  List<_Container> _containers = [];
  final Map<String, String> _stats = {}; // id -> "1.2% • 120MiB / 6GiB"

  /// The SSH user can't reach the Docker socket, so prefix with sudo
  bool _useSudo = false;
  String get _docker => _useSudo ? 'sudo docker' : 'docker';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    try {
      final probe = await _ssh.run('command -v docker');
      if (!probe.success || probe.stdout.trim().isEmpty) {
        _fail(
          Icons.inventory_2_outlined,
          'Docker not installed',
          'Docker isn\'t installed on this server, or it isn\'t in the '
              'PATH of ${widget.connection.username}.',
        );
        return;
      }

      var result = await _ssh.run("$_docker ps -a --format '$_psFormat'");
      if (result.permissionDenied && !_ssh.isRoot && !_useSudo) {
        final retry = await _ssh.run("sudo docker ps -a --format '$_psFormat'");
        if (retry.success) {
          _useSudo = true;
          result = retry;
        } else {
          _fail(
            Icons.lock_outline,
            'No permission for Docker',
            '${widget.connection.username} can\'t access Docker. Either add '
                'it to the docker group:\n\n'
                'sudo usermod -aG docker ${widget.connection.username}\n\n'
                'or let the app use sudo: ${describeSudoFailure(_ssh, retry)}',
            color: Colors.orange,
          );
          return;
        }
      }

      if (!result.success) {
        final err = result.stderr.toLowerCase();
        if (err.contains('cannot connect to the docker daemon') ||
            err.contains('is the docker daemon running')) {
          _fail(
            Icons.power_off_outlined,
            'Docker isn\'t running',
            'Docker is installed but its service is stopped. Start it with:\n\n'
                'sudo systemctl start docker',
            color: Colors.orange,
          );
        } else {
          _fail(Icons.error_outline, 'Couldn\'t list containers', result.message);
        }
        return;
      }

      final containers = <_Container>[];
      for (final line in result.stdout.split('\n')) {
        final f = line.split('|');
        if (f.length < 6) continue;
        containers.add(
          _Container(f[0], f[1], f[2], f[3], f[4], f.sublist(5).join('|')),
        );
      }
      // Running first, then by name
      containers.sort((a, b) {
        if (a.running != b.running) return a.running ? -1 : 1;
        return a.name.compareTo(b.name);
      });

      if (!mounted) return;
      setState(() {
        _containers = containers;
        _loading = false;
      });
      _loadStats();
    } catch (e) {
      _fail(
        Icons.cloud_off,
        'Connection problem',
        e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// `docker stats` takes a couple of seconds, so it fills in after the list
  Future<void> _loadStats() async {
    if (!_containers.any((c) => c.running)) return;
    try {
      final r = await _ssh.run(
        "$_docker stats --no-stream --format '$_statsFormat'",
      );
      if (!r.success || !mounted) return;
      final stats = <String, String>{};
      for (final line in r.stdout.split('\n')) {
        final f = line.split('|');
        if (f.length < 3) continue;
        stats[f[0]] = '${f[1]} CPU • ${f[2].split('/').first.trim()}';
      }
      setState(() => _stats
        ..clear()
        ..addAll(stats));
    } catch (_) {
      // Stats are optional; the list is still useful without them
    }
  }

  void _fail(IconData icon, String title, String message, {Color? color}) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _problem = ToolMessage(
        icon: icon,
        title: title,
        message: message,
        color: color,
        onRetry: _load,
      );
    });
  }

  Future<void> _containerAction(_Container c, String action) async {
    if (action != 'start' &&
        !await confirmAction(
          context,
          title: '${action[0].toUpperCase()}${action.substring(1)} ${c.name}?',
          message: 'Anything using this container will be interrupted.',
          action: action[0].toUpperCase() + action.substring(1),
        )) {
      return;
    }
    if (!mounted) return;
    final ok = await runAction(context, () async {
      final r = await _ssh.run('$_docker $action ${c.id}');
      if (r.success) return null;
      return r.sudoFailed ? describeSudoFailure(_ssh, r) : r.message;
    }, success: '${c.name}: $action done');
    if (ok) _load();
  }

  void _showLogs(_Container c) {
    showCommandOutput(
      context,
      connection: widget.connection,
      ssh: _ssh,
      title: '${c.name} logs',
      command: '$_docker logs --tail 200 -f ${c.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _containers.where((c) => c.running).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Docker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _problem ??
                (_containers.isEmpty
                    ? ToolMessage(
                        icon: Icons.inventory_2_outlined,
                        title: 'No containers',
                        message: 'Docker is running but has no containers.',
                        onRetry: _load,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              '$running RUNNING • ${_containers.length} TOTAL'
                              '${_useSudo ? ' • VIA SUDO' : ''}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            for (final c in _containers) _buildContainer(c),
                          ],
                        ),
                      )),
    );
  }

  Widget _buildContainer(_Container c) {
    final Color color = switch (c.state) {
      'running' => Colors.green,
      'paused' || 'restarting' => Colors.orange,
      'dead' => Colors.red,
      _ => Colors.grey,
    };
    final stats = _stats[c.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _showLogs(c),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.inventory_2, color: color),
        ),
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.image, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              stats != null ? '${c.status} • $stats' : c.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => [
            if (!c.running)
              const PopupMenuItem(value: 'start', child: Text('Start')),
            if (c.running)
              const PopupMenuItem(value: 'stop', child: Text('Stop')),
            const PopupMenuItem(value: 'restart', child: Text('Restart')),
            const PopupMenuItem(value: 'logs', child: Text('Logs')),
          ],
          onSelected: (v) {
            if (v == 'logs') {
              _showLogs(c);
            } else {
              _containerAction(c, v);
            }
          },
        ),
      ),
    );
  }
}
