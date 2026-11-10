/// Command trigger UI: list section, editor dialog and live-output run sheet.
import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/database_helper.dart';
import '../../models/connection_model.dart';
import '../../models/trigger_model.dart';
import '../../services/ssh_service.dart';

/// Trigger list for one connection: header with Add button + one tile each.
///
/// [ssh] is reused when the caller already holds a connection (the server
/// screen); otherwise each run opens its own short-lived connection.
class TriggerListSection extends StatefulWidget {
  final ConnectionModel connection;
  final SshService? ssh;

  const TriggerListSection({super.key, required this.connection, this.ssh});

  @override
  State<TriggerListSection> createState() => _TriggerListSectionState();
}

class _TriggerListSectionState extends State<TriggerListSection> {
  final DatabaseHelper _db = DatabaseHelper();
  List<TriggerModel> _triggers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _db.getTriggers(connectionId: widget.connection.id);
    if (!mounted) return;
    setState(() {
      _triggers = rows.map(TriggerModel.fromMap).toList();
      _loading = false;
    });
  }

  Future<void> _add() async {
    final saved = await showTriggerEditor(context, widget.connection.id!);
    if (saved) _load();
  }

  Future<void> _edit(TriggerModel trigger) async {
    final saved = await showTriggerEditor(
      context,
      widget.connection.id!,
      trigger: trigger,
    );
    if (saved) _load();
  }

  Future<void> _delete(TriggerModel trigger) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trigger'),
        content: Text('Delete "${trigger.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteTrigger(trigger.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('TRIGGERS', style: theme.textTheme.titleSmall),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Trigger'),
              onPressed: _add,
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_triggers.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.bolt, size: 36, color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text('No triggers yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Save commands like "sudo systemctl restart docker" '
                    'and run them with one tap.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else
          for (final t in _triggers)
            TriggerTile(
              trigger: t,
              onRun: () => runTrigger(
                context,
                connection: widget.connection,
                trigger: t,
                ssh: widget.ssh,
              ),
              onEdit: () => _edit(t),
              onDelete: () => _delete(t),
            ),
      ],
    );
  }
}

class TriggerTile extends StatelessWidget {
  final TriggerModel trigger;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TriggerTile({
    super.key,
    required this.trigger,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onRun,
        leading: CircleAvatar(
          backgroundColor: Colors.green.withValues(alpha: 0.15),
          child: const Icon(Icons.play_arrow, color: Colors.green),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                trigger.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trigger.confirm) ...[
              const SizedBox(width: 6),
              const Icon(Icons.shield_outlined, size: 14, color: Colors.orange),
            ],
          ],
        ),
        subtitle: Text(
          trigger.command,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'run', child: Text('Run')),
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
          onSelected: (v) {
            if (v == 'run') onRun();
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
        ),
      ),
    );
  }
}

/// Create or edit a trigger. Returns true when saved.
Future<bool> showTriggerEditor(
  BuildContext context,
  int connectionId, {
  TriggerModel? trigger,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _TriggerEditorDialog(connectionId: connectionId, trigger: trigger),
  );
  return saved ?? false;
}

/// Owns its controllers so they outlive the dialog's closing animation
class _TriggerEditorDialog extends StatefulWidget {
  final int connectionId;
  final TriggerModel? trigger;

  const _TriggerEditorDialog({required this.connectionId, this.trigger});

  @override
  State<_TriggerEditorDialog> createState() => _TriggerEditorDialogState();
}

class _TriggerEditorDialogState extends State<_TriggerEditorDialog> {
  late final _nameCtrl = TextEditingController(text: widget.trigger?.name);
  late final _cmdCtrl = TextEditingController(text: widget.trigger?.command);
  late bool _confirm = widget.trigger?.confirm ?? false;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = DatabaseHelper();
    final trigger = widget.trigger;
    if (trigger == null) {
      await db.insertTrigger(
        TriggerModel(
          connectionId: widget.connectionId,
          name: _nameCtrl.text.trim(),
          command: _cmdCtrl.text.trim(),
          confirm: _confirm,
        ).toMap(),
      );
    } else {
      await db.updateTrigger(
        trigger.id!,
        trigger
            .copyWith(
              name: _nameCtrl.text.trim(),
              command: _cmdCtrl.text.trim(),
              confirm: _confirm,
            )
            .toMap(),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.trigger == null ? 'Add Trigger' : 'Edit Trigger'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: widget.trigger == null,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Restart Docker',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cmdCtrl,
                minLines: 2,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Command',
                  hintText: 'sudo systemctl restart docker',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a command' : null,
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirm,
                onChanged: (v) => setState(() => _confirm = v),
                title: const Text('Ask before running'),
                subtitle: const Text('For restarts, deletes and similar'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Confirm (if the trigger asks for it), then run it and stream the output
Future<void> runTrigger(
  BuildContext context, {
  required ConnectionModel connection,
  required TriggerModel trigger,
  SshService? ssh,
}) async {
  if (trigger.confirm) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Run "${trigger.name}"?'),
        content: Text(
          trigger.command,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  if (!context.mounted) return;
  await showCommandOutput(
    context,
    connection: connection,
    title: trigger.name,
    command: trigger.command,
    ssh: ssh,
  );
}

/// Run [command] in a bottom sheet that streams its output live, with
/// Stop and Copy. Also used for logs and status views in the server tools.
Future<void> showCommandOutput(
  BuildContext context, {
  required ConnectionModel connection,
  required String title,
  required String command,
  SshService? ssh,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CommandOutputSheet(
      connection: connection,
      title: title,
      command: command,
      ssh: ssh,
    ),
  );
}

class _CommandOutputSheet extends StatefulWidget {
  final ConnectionModel connection;
  final String title;
  final String command;
  final SshService? ssh;

  const _CommandOutputSheet({
    required this.connection,
    required this.title,
    required this.command,
    this.ssh,
  });

  @override
  State<_CommandOutputSheet> createState() => _CommandOutputSheetState();
}

class _CommandOutputSheetState extends State<_CommandOutputSheet> {
  final StringBuffer _output = StringBuffer();
  final ScrollController _scroll = ScrollController();
  late final SshService _ssh;
  late final bool _ownsSsh;
  SSHSession? _session;
  bool _running = true;
  int? _exitCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsSsh = widget.ssh == null;
    _ssh = widget.ssh ?? SshService(widget.connection);
    _run();
  }

  Future<void> _run() async {
    try {
      // execute() supplies the saved password to any sudo in the command
      final session = await _ssh.execute(widget.command);
      _session = session;
      void append(String text) {
        if (!mounted) return;
        setState(() => _output.write(text));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }

      // Take the done futures before awaiting: a stream that has already
      // finished won't complete an asFuture() attached later
      final outDone = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(append)
          .asFuture<void>();
      final errDone = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(append)
          .asFuture<void>();
      await Future.wait([session.done, outDone, errDone]);
      if (!mounted) return;
      setState(() {
        _running = false;
        _exitCode = session.exitCode;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _session?.close();
    if (_ownsSsh) _ssh.close();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String status;
    if (_running) {
      statusColor = Theme.of(context).colorScheme.primary;
      status = 'Running...';
    } else if (_error != null) {
      statusColor = Colors.red;
      status = 'Failed';
    } else if (_exitCode == 0 || _exitCode == null) {
      statusColor = Colors.green;
      status = _exitCode == null ? 'Finished' : 'Exit code 0';
    } else {
      statusColor = Colors.orange;
      status = 'Exit code $_exitCode';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (_running)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  Text(status, style: TextStyle(color: statusColor)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '\$ ${widget.command}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF060914),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      _error ??
                          (_output.isEmpty && !_running
                              ? '(no output)'
                              : _output.toString()),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _error != null
                            ? Colors.red[300]
                            : const Color(0xFFD7DBEA),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: _output.toString()),
                    ),
                  ),
                  const Spacer(),
                  if (_running)
                    OutlinedButton(
                      onPressed: () {
                        _session?.close();
                        setState(() {
                          _running = false;
                          _error = 'Stopped';
                        });
                      },
                      child: const Text('Stop'),
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
