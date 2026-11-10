/// Server Monitor - live system stats read over SSH.
///
/// Polls standard Linux sources (/proc/stat, /proc/meminfo, df, /proc/uptime,
/// /proc/net/dev) every few seconds. CPU and network rates are computed from
/// the delta between consecutive samples.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/connection_model.dart';
import 'ssh_service.dart';

/// Static facts about the server, fetched once per connection
class ServerInfo {
  final String os;
  final String kernel;
  final String cpuModel;
  final String hostname;
  final int threads;
  final int? cores;

  ServerInfo({
    required this.os,
    required this.kernel,
    required this.cpuModel,
    required this.hostname,
    required this.threads,
    this.cores,
  });

  String get coreSummary {
    if (cores != null && cores != threads) {
      return '$cores Cores ($threads Threads)';
    }
    return '$threads ${threads == 1 ? 'Core' : 'Cores'}';
  }
}

/// One sample of live usage
class ServerStats {
  final double cpu; // 0..1
  final int memTotal; // bytes
  final int memUsed;
  final int diskTotal;
  final int diskUsed;
  final Duration uptime;
  final double rxPerSec; // bytes/sec, 0 on first sample
  final double txPerSec;
  final List<double> loadAverage; // 1, 5, 15 minutes

  ServerStats({
    required this.cpu,
    required this.memTotal,
    required this.memUsed,
    required this.diskTotal,
    required this.diskUsed,
    required this.uptime,
    required this.rxPerSec,
    required this.txPerSec,
    required this.loadAverage,
  });

  double get memFraction => memTotal > 0 ? memUsed / memTotal : 0;
  double get diskFraction => diskTotal > 0 ? diskUsed / diskTotal : 0;
}

class ServerMonitor extends ChangeNotifier {
  static const pollInterval = Duration(seconds: 3);

  static const _infoCommand = r'''
. /etc/os-release 2>/dev/null
echo "OS=${PRETTY_NAME:-$(uname -s)}"
echo "KERNEL=$(uname -r)"
m=$(grep -m1 -i 'model name' /proc/cpuinfo | cut -d: -f2-)
[ -z "$m" ] && m=$(lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2-)
echo "CPU=$(echo $m)"
echo "THREADS=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"
echo "CORES=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/{c=$2} /^Socket\(s\)/{s=$2} END{if(c&&s) print c*s}')"
echo "HOST=$(hostname)"
''';

  static const _statsCommand = r'''
echo "==STAT"; head -1 /proc/stat
echo "==MEM"; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo
echo "==DF"; df -Pk / | tail -1
echo "==UP"; cut -d' ' -f1 /proc/uptime
echo "==NET"; tail -n +3 /proc/net/dev
echo "==LOAD"; cat /proc/loadavg
''';

  final ConnectionModel connection;
  final SshService ssh;

  ServerInfo? info;
  ServerStats? stats;
  String? error;
  bool connecting = true;

  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  int? _prevCpuTotal;
  int? _prevCpuIdle;
  int? _prevRx;
  int? _prevTx;
  DateTime? _prevNetAt;

  ServerMonitor(this.connection) : ssh = SshService(connection);

  bool get isConnected => ssh.isConnected && error == null;

  Future<void> start() async {
    connecting = true;
    error = null;
    _notify();
    try {
      await ssh.connect();
      info = _parseInfo((await ssh.run(_infoCommand)).stdout);
      connecting = false;
      await _poll();
      _timer?.cancel();
      _timer = Timer.periodic(pollInterval, (_) => _poll());
    } catch (e) {
      connecting = false;
      error = _describe(e);
      _notify();
    }
  }

  /// Retry after a failure (the poll loop also reconnects on its own)
  Future<void> reconnect() async {
    ssh.close();
    await start();
  }

  Future<void> _poll() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      // run() reconnects if the previous connection dropped
      stats = _parseStats((await ssh.run(_statsCommand)).stdout);
      error = null;
    } catch (e) {
      error = _describe(e);
      ssh.close();
    } finally {
      _polling = false;
      _notify();
    }
  }

  ServerInfo _parseInfo(String out) {
    final values = <String, String>{};
    for (final line in out.split('\n')) {
      final eq = line.indexOf('=');
      if (eq > 0) values[line.substring(0, eq)] = line.substring(eq + 1).trim();
    }
    return ServerInfo(
      os: values['OS']?.isNotEmpty == true ? values['OS']! : 'Unknown',
      kernel: values['KERNEL'] ?? '',
      cpuModel: values['CPU']?.isNotEmpty == true ? values['CPU']! : 'Unknown',
      hostname: values['HOST'] ?? '',
      threads: int.tryParse(values['THREADS'] ?? '') ?? 1,
      cores: int.tryParse(values['CORES'] ?? ''),
    );
  }

  ServerStats _parseStats(String out) {
    final sections = <String, List<String>>{};
    String? current;
    for (final line in out.split('\n')) {
      if (line.startsWith('==')) {
        current = line.substring(2).trim();
        sections[current] = [];
      } else if (current != null && line.trim().isNotEmpty) {
        sections[current]!.add(line);
      }
    }

    // CPU: "cpu user nice system idle iowait irq softirq steal ..."
    double cpu = 0;
    final cpuFields = _numbers(sections['STAT']?.first ?? '');
    if (cpuFields.length >= 4) {
      final total = cpuFields.take(8).fold<int>(0, (a, b) => a + b);
      final idle = cpuFields[3] + (cpuFields.length > 4 ? cpuFields[4] : 0);
      if (_prevCpuTotal != null && total > _prevCpuTotal!) {
        cpu = 1 - (idle - _prevCpuIdle!) / (total - _prevCpuTotal!);
      } else if (total > 0) {
        cpu = 1 - idle / total; // average since boot until we have a delta
      }
      _prevCpuTotal = total;
      _prevCpuIdle = idle;
    }

    // Memory (kB)
    int memTotal = 0, memAvailable = 0;
    for (final line in sections['MEM'] ?? const <String>[]) {
      final n = _numbers(line);
      if (n.isEmpty) continue;
      if (line.startsWith('MemTotal')) memTotal = n.first * 1024;
      if (line.startsWith('MemAvailable')) memAvailable = n.first * 1024;
    }

    // Disk: "fs 1024-blocks used available capacity mount" (kB)
    int diskTotal = 0, diskUsed = 0;
    final df = (sections['DF']?.first ?? '').trim().split(RegExp(r'\s+'));
    if (df.length >= 4) {
      final used = int.tryParse(df[2]) ?? 0;
      final available = int.tryParse(df[3]) ?? 0;
      diskUsed = used * 1024;
      diskTotal = (used + available) * 1024; // matches df's Use%
    }

    final uptimeSecs =
        double.tryParse((sections['UP']?.first ?? '').trim()) ?? 0;

    // Network: sum all interfaces except loopback
    int rx = 0, tx = 0;
    for (final line in sections['NET'] ?? const <String>[]) {
      final colon = line.indexOf(':');
      if (colon < 0 || line.substring(0, colon).trim() == 'lo') continue;
      final n = _numbers(line.substring(colon + 1));
      if (n.length >= 9) {
        rx += n[0];
        tx += n[8];
      }
    }
    final now = DateTime.now();
    double rxRate = 0, txRate = 0;
    if (_prevNetAt != null) {
      final secs = now.difference(_prevNetAt!).inMilliseconds / 1000;
      if (secs > 0) {
        rxRate = ((rx - _prevRx!).clamp(0, 1 << 62)) / secs;
        txRate = ((tx - _prevTx!).clamp(0, 1 << 62)) / secs;
      }
    }
    _prevRx = rx;
    _prevTx = tx;
    _prevNetAt = now;

    // "0.52 0.48 0.40 1/234 5678"
    final loadAverage = (sections['LOAD']?.first ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .take(3)
        .map((v) => double.tryParse(v) ?? 0)
        .toList();

    return ServerStats(
      cpu: cpu.clamp(0.0, 1.0),
      memTotal: memTotal,
      memUsed: memTotal - memAvailable,
      diskTotal: diskTotal,
      diskUsed: diskUsed,
      uptime: Duration(seconds: uptimeSecs.round()),
      rxPerSec: rxRate,
      txPerSec: txRate,
      loadAverage: loadAverage,
    );
  }

  static List<int> _numbers(String line) => RegExp(r'\d+')
      .allMatches(line)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  static String _describe(Object e) =>
      e.toString().replaceAll('Exception: ', '');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    ssh.close();
    super.dispose();
  }
}
