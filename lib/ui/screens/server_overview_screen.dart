/// Server screen for SSH/SFTP devices.
///
/// Live CPU / RAM / storage usage and system info from a [ServerMonitor],
/// buttons for the file manager and terminal, and the device's triggers.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/page_transitions.dart';
import '../../models/connection_model.dart';
import '../../providers/connection_provider.dart';
import '../../services/server_monitor.dart';
import '../../services/ssh_service.dart';
import '../widgets/server_widgets.dart';
import '../widgets/trigger_widgets.dart';
import 'add_connection_screen.dart';
import 'docker_screen.dart';
import 'file_browser_screen.dart';
import 'processes_screen.dart';
import 'services_screen.dart';
import 'terminal_screen.dart';

class ServerOverviewScreen extends StatefulWidget {
  final ConnectionModel connection;

  const ServerOverviewScreen({super.key, required this.connection});

  @override
  State<ServerOverviewScreen> createState() => _ServerOverviewScreenState();
}

class _ServerOverviewScreenState extends State<ServerOverviewScreen> {
  late ConnectionModel _connection = widget.connection;
  late ServerMonitor _monitor = ServerMonitor(_connection);

  @override
  void initState() {
    super.initState();
    _monitor.start();
    Provider.of<ConnectionProvider>(
      context,
      listen: false,
    ).updateLastUsed(_connection.id!);
  }

  @override
  void dispose() {
    _monitor.dispose();
    super.dispose();
  }

  void _openFiles() {
    Navigator.push(
      context,
      SlidePageRoute(page: FileBrowserScreen(connection: _connection)),
    );
  }

  void _openTerminal() {
    Navigator.push(
      context,
      SlidePageRoute(page: TerminalScreen(connection: _connection)),
    );
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      SlidePageRoute(page: AddConnectionScreen(connection: _connection)),
    );
    if (!mounted) return;
    // Pick up edited credentials/host and reconnect with them
    final provider = Provider.of<ConnectionProvider>(context, listen: false);
    final updated = provider.connections
        .where((c) => c.id == _connection.id)
        .firstOrNull;
    if (updated == null) return;
    setState(() {
      _connection = updated;
      _monitor.dispose();
      _monitor = ServerMonitor(_connection)..start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _monitor,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              Text(_connection.name),
              Text(
                'SFTP • ${_connection.host}:${_connection.port}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: () => _monitor.reconnect(),
            ),
          ],
        ),
        body: Consumer<ServerMonitor>(
          builder: (context, monitor, _) => RefreshIndicator(
            onRefresh: monitor.reconnect,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusRow(monitor),
                const SizedBox(height: 12),
                _buildGauges(monitor),
                const SizedBox(height: 12),
                _buildInfoCard(monitor),
                const SizedBox(height: 12),
                _buildActions(),
                const SizedBox(height: 20),
                _buildTools(monitor),
                const SizedBox(height: 12),
                TriggerListSection(connection: _connection, ssh: monitor.ssh),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(ServerMonitor monitor) {
    final String status;
    if (monitor.connecting) {
      status = 'Connecting...';
    } else if (monitor.error != null) {
      status = 'Disconnected';
    } else {
      status = 'Connected';
    }

    return Row(
      children: [
        StatusChip(label: status, active: status == 'Connected'),
        const Spacer(),
        if (monitor.stats != null)
          Text(
            'Uptime: ${formatUptime(monitor.stats!.uptime)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _buildGauges(ServerMonitor monitor) {
    final s = monitor.stats;
    if (s == null && monitor.error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.cloud_off, size: 36, color: Colors.redAccent),
              const SizedBox(height: 8),
              Text(monitor.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: monitor.reconnect,
              ),
            ],
          ),
        ),
      );
    }

    String pct(double v) => s == null ? '--' : '${(v * 100).round()}%';
    return Row(
      children: [
        Expanded(
          child: RingGauge(
            value: s?.cpu ?? 0,
            color: Colors.green,
            label: 'CPU',
            valueText: pct(s?.cpu ?? 0),
            caption: monitor.info?.coreSummary ?? ' ',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RingGauge(
            value: s?.memFraction ?? 0,
            color: Theme.of(context).colorScheme.primary,
            label: 'RAM',
            valueText: pct(s?.memFraction ?? 0),
            caption: s == null
                ? ' '
                : '${formatBytes(s.memUsed)} / ${formatBytes(s.memTotal)}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RingGauge(
            value: s?.diskFraction ?? 0,
            color: Colors.orange,
            label: 'Storage',
            valueText: pct(s?.diskFraction ?? 0),
            caption: s == null
                ? ' '
                : '${formatBytes(s.diskUsed)} / ${formatBytes(s.diskTotal)}',
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ServerMonitor monitor) {
    final info = monitor.info;
    final s = monitor.stats;
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            row(Icons.computer, 'OS', info?.os ?? '--'),
            row(Icons.memory, 'Kernel', info?.kernel ?? '--'),
            row(Icons.developer_board, 'CPU', info?.cpuModel ?? '--'),
            row(
              Icons.lan,
              'IP / Port',
              '${_connection.host}:${_connection.port}',
            ),
            row(
              Icons.speed,
              'Load',
              s == null || s.loadAverage.length < 3
                  ? '--'
                  : '${s.loadAverage.map((l) => l.toStringAsFixed(2)).join('  ')}'
                        '  (1, 5, 15 min)',
            ),
            row(
              Icons.swap_vert,
              'Network',
              s == null
                  ? '--'
                  : '↓ ${formatBytes(s.rxPerSec)}/s   ↑ ${formatBytes(s.txPerSec)}/s',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.folder),
            label: const Text('File Manager'),
            onPressed: _openFiles,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.terminal),
            label: const Text('Terminal'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _openTerminal,
          ),
        ),
      ],
    );
  }

  /// Each tool opens its own screen and loads only when opened
  Widget _buildTools(ServerMonitor monitor) {
    void open(Widget page) =>
        Navigator.push(context, SlidePageRoute(page: page));

    Widget tile(IconData icon, String label, Color color, VoidCallback onTap) {
      return Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TOOLS', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: tile(
                Icons.inventory_2_outlined,
                'Docker',
                Colors.lightBlue,
                () => open(
                  DockerScreen(connection: _connection, ssh: monitor.ssh),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: tile(
                Icons.memory,
                'Processes',
                Colors.green,
                () => open(
                  ProcessesScreen(connection: _connection, ssh: monitor.ssh),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: tile(
                Icons.settings_applications_outlined,
                'Services',
                Colors.orange,
                () => open(
                  ServicesScreen(connection: _connection, ssh: monitor.ssh),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: tile(
                Icons.power_settings_new,
                'Power',
                Colors.red,
                () => _showPower(monitor),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPower(ServerMonitor monitor) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restart_alt, color: Colors.orange),
              title: const Text('Reboot'),
              subtitle: const Text('Restart the server'),
              onTap: () {
                Navigator.pop(ctx);
                _power(monitor, reboot: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.power_settings_new, color: Colors.red),
              title: const Text('Shut down'),
              subtitle: const Text(
                "Turn the server off. You'll need physical access or "
                'Wake-on-LAN to start it again.',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _power(monitor, reboot: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _power(ServerMonitor monitor, {required bool reboot}) async {
    final verb = reboot ? 'Reboot' : 'Shut down';
    final ok = await confirmAction(
      context,
      title: '$verb ${_connection.name}?',
      message: reboot
          ? 'All connections, containers and services will restart.'
          : 'The server will power off and go offline.',
      action: verb,
    );
    if (!ok || !mounted) return;

    final target = reboot ? 'reboot' : 'poweroff';
    await runAction(context, () async {
      try {
        final r = await monitor.ssh.runElevated(
          'command -v systemctl >/dev/null && systemctl $target || $target',
        );
        // A working reboot often kills the session before it reports back
        if (r.success || r.exitCode == null) return null;
        if (r.sudoFailed || r.permissionDenied) {
          return describeSudoFailure(monitor.ssh, r);
        }
        return r.message;
      } catch (_) {
        return null; // connection dropped: the server is going down
      }
    }, success: reboot ? 'Reboot command sent' : 'Shutdown command sent');
  }
}
