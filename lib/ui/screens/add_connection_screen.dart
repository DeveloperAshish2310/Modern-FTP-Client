import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import '../../models/connection_model.dart';

class AddConnectionScreen extends StatefulWidget {
  final ConnectionModel? connection; // For editing existing connection

  const AddConnectionScreen({super.key, this.connection});

  @override
  State<AddConnectionScreen> createState() => _AddConnectionScreenState();
}

class _AddConnectionScreenState extends State<AddConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _sshKeyController;
  late TextEditingController _remoteDirController;

  ConnectionProtocol _selectedProtocol = ConnectionProtocol.ftp;
  bool _obscurePassword = true;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing connection data if editing
    _nameController = TextEditingController(
      text: widget.connection?.name ?? '',
    );
    _hostController = TextEditingController(
      text: widget.connection?.host ?? '',
    );
    _portController = TextEditingController(
      text:
          widget.connection?.port.toString() ??
          _selectedProtocol.defaultPort.toString(),
    );
    _usernameController = TextEditingController(
      text: widget.connection?.username ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.connection?.password ?? '',
    );
    _sshKeyController = TextEditingController(
      text: widget.connection?.sshKeyPath ?? '',
    );
    _remoteDirController = TextEditingController(
      text: widget.connection?.remoteDirectory ?? '/',
    );

    if (widget.connection != null) {
      _selectedProtocol = widget.connection!.protocol;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _sshKeyController.dispose();
    _remoteDirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.connection != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Connection' : 'Add Connection'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Connection name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Connection Name',
                hintText: 'My FTP Server',
                prefixIcon: Icon(Icons.label),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a connection name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Protocol selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protocol',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ConnectionProtocol>(
                      segments: const [
                        ButtonSegment(
                          value: ConnectionProtocol.ftp,
                          label: Text('FTP'),
                          icon: Icon(Icons.folder_shared),
                        ),
                        ButtonSegment(
                          value: ConnectionProtocol.ftps,
                          label: Text('FTPS'),
                          icon: Icon(Icons.lock),
                        ),
                        ButtonSegment(
                          value: ConnectionProtocol.sftp,
                          label: Text('SFTP'),
                          icon: Icon(Icons.vpn_key),
                        ),
                      ],
                      selected: {_selectedProtocol},
                      onSelectionChanged:
                          (Set<ConnectionProtocol> newSelection) {
                            setState(() {
                              _selectedProtocol = newSelection.first;
                              _portController.text = _selectedProtocol
                                  .defaultPort
                                  .toString();
                            });
                          },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Host
            TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: 'ftp.example.com',
                prefixIcon: Icon(Icons.dns),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a host';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Port
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a port';
                }
                if (int.tryParse(value) == null) {
                  return 'Please enter a valid port number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Username
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a username';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password (hide for SFTP if using SSH key)
            if (_selectedProtocol != ConnectionProtocol.sftp ||
                _sshKeyController.text.isEmpty)
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
              ),
            const SizedBox(height: 16),

            // SSH Key for SFTP
            if (_selectedProtocol == ConnectionProtocol.sftp)
              Column(
                children: [
                  TextFormField(
                    controller: _sshKeyController,
                    decoration: const InputDecoration(
                      labelText: 'SSH Key Path (Optional)',
                      hintText: '/path/to/private/key',
                      prefixIcon: Icon(Icons.key),
                      helperText: 'Leave empty to use password authentication',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            // Advanced options toggle
            TextButton.icon(
              icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
              label: Text(
                _showAdvanced
                    ? 'Hide Advanced Options'
                    : 'Show Advanced Options',
              ),
              onPressed: () {
                setState(() {
                  _showAdvanced = !_showAdvanced;
                });
              },
            ),

            if (_showAdvanced) ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Advanced Settings',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                'Additional settings like timeout and encoding can be added here.',
              ),
              const SizedBox(height: 16),
              // Remote Directory
              TextFormField(
                controller: _remoteDirController,
                decoration: const InputDecoration(
                  labelText: 'Remote Directory',
                  hintText: '/',
                  prefixIcon: Icon(Icons.folder),
                  helperText:
                      'Initial directory to open. Falls back to / if invalid.',
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 24),

            // Save button
            ElevatedButton(
              onPressed: _saveConnection,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(isEditing ? 'Save Changes' : 'Add Connection'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveConnection() async {
    if (_formKey.currentState!.validate()) {
      final connectionProvider = Provider.of<ConnectionProvider>(
        context,
        listen: false,
      );

      final connection = ConnectionModel(
        id: widget.connection?.id,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.parse(_portController.text),
        username: _usernameController.text.trim(),
        password: _passwordController.text.isEmpty
            ? null
            : _passwordController.text,
        protocol: _selectedProtocol,
        sshKeyPath: _sshKeyController.text.isEmpty
            ? null
            : _sshKeyController.text,
        remoteDirectory: _remoteDirController.text.trim().isEmpty
            ? '/'
            : _remoteDirController.text.trim(),
        createdAt: widget.connection?.createdAt ?? DateTime.now(),
        isFavorite: widget.connection?.isFavorite ?? false,
      );

      final success = widget.connection != null
          ? await connectionProvider.updateConnection(connection)
          : await connectionProvider.addConnection(connection);

      if (mounted) {
        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.connection != null
                    ? 'Connection updated successfully'
                    : 'Connection added successfully',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save connection'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
