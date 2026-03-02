import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import '../../providers/theme_provider.dart';
import '../../core/constants/app_constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _appLockEnabled = false;
  bool _biometricsAvailable = false;
  int _defaultFtpPort = AppConstants.ftpPort;
  int _defaultSftpPort = AppConstants.sftpPort;
  int _connectionTimeout = AppConstants.connectionTimeout;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final canAuth =
        await _localAuth.canCheckBiometrics ||
        await _localAuth.isDeviceSupported();

    if (!mounted) return;
    setState(() {
      _appLockEnabled = prefs.getBool('app_lock') ?? false;
      _biometricsAvailable = canAuth;
      _defaultFtpPort =
          prefs.getInt('default_ftp_port') ?? AppConstants.ftpPort;
      _defaultSftpPort =
          prefs.getInt('default_sftp_port') ?? AppConstants.sftpPort;
      _connectionTimeout =
          prefs.getInt('connection_timeout') ?? AppConstants.connectionTimeout;
    });
  }

  Future<void> _savePref(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ============ APPEARANCE ============
          _sectionHeader('Appearance'),
          SwitchListTile(
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            title: const Text('Dark Mode'),
            subtitle: Text(isDark ? 'Dark theme active' : 'Light theme active'),
            value: isDark,
            onChanged: (val) => themeProvider.setThemeMode(val),
          ),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Accent Color'),
            subtitle: Text(themeProvider.accentColor),
            trailing: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: themeProvider.availableColors[themeProvider.accentColor],
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            onTap: () => _showAccentColorPicker(themeProvider),
          ),

          // ============ SECURITY ============
          _sectionHeader('Security'),
          SwitchListTile(
            secondary: const Icon(Icons.lock),
            title: const Text('App Lock'),
            subtitle: Text(
              _biometricsAvailable
                  ? 'Require biometrics to open app'
                  : 'Biometrics not available on this device',
            ),
            value: _appLockEnabled,
            onChanged: _biometricsAvailable
                ? (val) async {
                    if (val) {
                      // Verify biometrics first
                      try {
                        final authed = await _localAuth.authenticate(
                          localizedReason: 'Authenticate to enable App Lock',
                          options: const AuthenticationOptions(
                            biometricOnly: true,
                          ),
                        );
                        if (!authed) return;
                      } catch (_) {
                        return;
                      }
                    }
                    setState(() => _appLockEnabled = val);
                    _savePref('app_lock', val);
                  }
                : null,
          ),

          // ============ CONNECTION DEFAULTS ============
          _sectionHeader('Connection Defaults'),
          ListTile(
            leading: const Icon(Icons.router),
            title: const Text('Default FTP Port'),
            subtitle: Text('$_defaultFtpPort'),
            onTap: () =>
                _showPortDialog('Default FTP Port', _defaultFtpPort, (val) {
                  setState(() => _defaultFtpPort = val);
                  _savePref('default_ftp_port', val);
                }),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Default SFTP Port'),
            subtitle: Text('$_defaultSftpPort'),
            onTap: () =>
                _showPortDialog('Default SFTP Port', _defaultSftpPort, (val) {
                  setState(() => _defaultSftpPort = val);
                  _savePref('default_sftp_port', val);
                }),
          ),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Connection Timeout'),
            subtitle: Text('$_connectionTimeout seconds'),
            onTap: () => _showTimeoutDialog(),
          ),

          // ============ ABOUT ============
          _sectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About FTP Client'),
            onTap: () => _showAboutDialog(),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Version'),
            subtitle: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  // ============ ACCENT COLOR PICKER ============
  void _showAccentColorPicker(ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Accent Color',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: themeProvider.availableColors.entries.map((entry) {
                  final isSelected = themeProvider.accentColor == entry.key;
                  return GestureDetector(
                    onTap: () {
                      themeProvider.setAccentColor(entry.key);
                      Navigator.pop(ctx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: entry.value.withAlpha(128),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ============ PORT DIALOG ============
  void _showPortDialog(
    String title,
    int currentValue,
    void Function(int) onSave,
  ) {
    final controller = TextEditingController(text: '$currentValue');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port number',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val > 0 && val <= 65535) {
                onSave(val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ============ TIMEOUT DIALOG ============
  void _showTimeoutDialog() {
    final controller = TextEditingController(text: '$_connectionTimeout');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Timeout'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Timeout (seconds)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val >= 5 && val <= 300) {
                setState(() => _connectionTimeout = val);
                _savePref('connection_timeout', val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ============ ABOUT DIALOG ============
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.cloud_sync,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('FTP Client'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0'),
            SizedBox(height: 12),
            Text(
              'A modern FTP/SFTP client for Android with advanced file '
              'management, background transfers, built-in text editor, '
              'and real-time notifications.',
            ),
            SizedBox(height: 16),
            Text('Features:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('• FTP, SFTP & FTPS support'),
            Text('• Background downloads & uploads'),
            Text('• Built-in text file editor'),
            Text('• Transfer notifications'),
            Text('• Dark & Light themes'),
            Text('• Accent color customization'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
