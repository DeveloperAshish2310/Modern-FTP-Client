/// Services - systemd units with start/stop/restart, status and logs.
///
/// State changes need root, so they go through sudo when the SSH user
/// isn't root. Servers without systemd get a clear message instead.
import 'package:flutter/material.dart';
import '../../models/connection_model.dart';
import '../../services/ssh_service.dart';
import '../widgets/server_widgets.dart';
import '../widgets/trigger_widgets.dart';

class _Service {
  final String unit;
  final String load;
  final String active; // active, inactive, failed, activating
  final String sub; // running, exited, dead, failed
  final String description;

  _Service(this.unit, this.load, this.active, this.sub, this.description);

  String get name => unit.endsWith('.service')
      ? unit.substring(0, unit.length - '.service'.length)
      : unit;
}

enum _Filter { running, failed, all }

class ServicesScreen extends StatefulWidget {
  final ConnectionModel connection;
  final SshService ssh;

  const ServicesScreen({super.key, required this.connection, required this.ssh});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  SshService get _ssh => widget.ssh;

  bool _loading = true;
  ToolMessage? _problem;
  List<_Service> _services = [];
  _Filter _filter = _Filter.running;
  String _query = '';

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
      final probe = await _ssh.run('command -v systemctl');
      if (!probe.success || probe.stdout.trim().isEmpty) {
        _fail(
          Icons.settings_applications_outlined,
          'No systemd',
          'This server doesn\'t use systemd, so there are no services to '
              'manage here.',
        );
        return;
      }

      final r = await _ssh.run(
        'systemctl list-units --type=service --all '
        '--no-legend --no-pager --plain',
      );
      if (!r.success) {
        _fail(Icons.error_outline, 'Couldn\'t list services', r.message);
        return;
      }

      final services = <_Service>[];
      for (final line in r.stdout.split('\n')) {
        final f = line.trim().split(RegExp(r'\s+'));
        if (f.length < 4 || !f[0].contains('.')) continue;
        services.add(
          _Service(f[0], f[1], f[2], f[3], f.sublist(4).join(' ')),
        );
      }
      if (!mounted) return;
      setState(() {
        _services = services;
        _loading = false;
      });
    } catch (e) {
      _fail(
        Icons.cloud_off,
        'Connection problem',
        e.toString().replaceAll('Exception: ', ''),
      );
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

  Future<void> _control(_Service s, String action) async {
    if (action != 'start' &&
        !await confirmAction(
          context,
          title: '${action[0].toUpperCase()}${action.substring(1)} ${s.name}?',
          message: 'Anything depending on this service will be affected.',
          action: action[0].toUpperCase() + action.substring(1),
        )) {
      return;
    }
    if (!mounted) return;
    final ok = await runAction(context, () async {
      // Non-root gets "Interactive authentication required": retried via sudo
      final r = await _ssh.runElevated('systemctl $action ${s.unit}');
      if (r.success) return null;
      if (r.sudoFailed || r.permissionDenied) {
        return describeSudoFailure(_ssh, r);
      }
      return r.message;
    }, success: '${s.name}: $action done');
    if (ok) _load();
  }

  /// journald may hide other users' logs; use sudo when we can
  String get _journalctl =>
      !_ssh.isRoot && _ssh.hasPassword ? 'sudo journalctl' : 'journalctl';

  void _showActions(_Service s) {
    final running = s.active == 'active';
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        void act(VoidCallback f) {
          Navigator.pop(ctx);
          f();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  s.name,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                subtitle: Text('${s.description}\n${s.active} (${s.sub})'),
                isThreeLine: true,
              ),
              const Divider(height: 1),
              if (!running)
                ListTile(
                  leading: const Icon(Icons.play_arrow, color: Colors.green),
                  title: const Text('Start'),
                  onTap: () => act(() => _control(s, 'start')),
                ),
              if (running)
                ListTile(
                  leading: const Icon(Icons.stop, color: Colors.red),
                  title: const Text('Stop'),
                  onTap: () => act(() => _control(s, 'stop')),
                ),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Colors.orange),
                title: const Text('Restart'),
                onTap: () => act(() => _control(s, 'restart')),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Status'),
                onTap: () => act(
                  () => showCommandOutput(
                    context,
                    connection: widget.connection,
                    ssh: _ssh,
                    title: '${s.name} status',
                    command: 'systemctl status ${s.unit} --no-pager -l -n 30',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('Logs'),
                onTap: () => act(
                  () => showCommandOutput(
                    context,
                    connection: widget.connection,
                    ssh: _ssh,
                    title: '${s.name} logs',
                    command:
                        '$_journalctl -u ${s.unit} -n 200 --no-pager -f',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final visible = _services.where((s) {
      final matchesFilter = switch (_filter) {
        _Filter.running => s.sub == 'running',
        _Filter.failed => s.active == 'failed',
        _Filter.all => true,
      };
      return matchesFilter &&
          (query.isEmpty ||
              s.unit.toLowerCase().contains(query) ||
              s.description.toLowerCase().contains(query));
    }).toList();
    final failedCount = _services.where((s) => s.active == 'failed').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
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
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search services...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final f in _Filter.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: _filter == f,
                                label: Text(switch (f) {
                                  _Filter.running => 'Running',
                                  _Filter.failed => 'Failed ($failedCount)',
                                  _Filter.all => 'All',
                                }),
                                onSelected: (_) => setState(() => _filter = f),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(child: Text('No matching services'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: visible.length,
                                itemBuilder: (_, i) =>
                                    _buildService(visible[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildService(_Service s) {
    final Color color = switch (s.active) {
      'active' => s.sub == 'running' ? Colors.green : Colors.blueGrey,
      'failed' => Colors.red,
      'activating' || 'deactivating' || 'reloading' => Colors.orange,
      _ => Colors.grey,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: () => _showActions(s),
        leading: Icon(Icons.circle, size: 12, color: color),
        title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          s.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(s.sub, style: TextStyle(color: color)),
      ),
    );
  }
}
