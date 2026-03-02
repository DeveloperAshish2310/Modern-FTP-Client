import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'providers/theme_provider.dart';
import 'providers/connection_provider.dart';
import 'core/utils/permission_helper.dart';
import 'ui/screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const FTPClientApp());
}

class FTPClientApp extends StatelessWidget {
  const FTPClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider()..loadConnections(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'FTP Client',
            theme: themeProvider.theme,
            debugShowCheckedModeBanner: false,
            home: const _AppGate(),
          );
        },
      ),
    );
  }
}

/// Gate that checks app lock + requests storage permission before showing dashboard
class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _isAuthenticated = false;
  bool _isChecking = true;
  bool _authFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLock());
  }

  Future<void> _checkLock() async {
    final prefs = await SharedPreferences.getInstance();
    final lockEnabled = prefs.getBool('app_lock') ?? false;

    if (!lockEnabled) {
      // No lock — go straight through
      if (mounted) {
        setState(() {
          _isAuthenticated = true;
          _isChecking = false;
        });
        await PermissionHelper.requestStoragePermission(context);
        await PermissionHelper.requestNotificationPermission();
      }
      return;
    }

    // App lock is enabled — authenticate
    await _authenticate();
  }

  Future<void> _authenticate() async {
    setState(() {
      _isChecking = true;
      _authFailed = false;
    });

    try {
      final localAuth = LocalAuthentication();
      final authed = await localAuth.authenticate(
        localizedReason: 'Authenticate to access FTP Client',
        options: const AuthenticationOptions(
          biometricOnly: false, // Allow PIN/password/fingerprint
          stickyAuth: true,
        ),
      );

      if (!mounted) return;

      if (authed) {
        setState(() {
          _isAuthenticated = true;
          _isChecking = false;
        });
        await PermissionHelper.requestStoragePermission(context);
        await PermissionHelper.requestNotificationPermission();
      } else {
        setState(() {
          _isChecking = false;
          _authFailed = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _authFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return const DashboardScreen();
    }

    // Lock screen
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'FTP Client',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _isChecking
                  ? 'Authenticating...'
                  : _authFailed
                  ? 'Authentication required'
                  : 'Locked',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            if (_isChecking)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
              ),
          ],
        ),
      ),
    );
  }
}
