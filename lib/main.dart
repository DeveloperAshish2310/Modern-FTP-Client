import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
            home: const _PermissionGate(),
          );
        },
      ),
    );
  }
}

/// Gate that requests storage permission on first launch before showing dashboard
class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  @override
  void initState() {
    super.initState();
    // Request permission after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermission();
    });
  }

  Future<void> _requestPermission() async {
    await PermissionHelper.requestStoragePermission(context);
    // Always proceed to dashboard (permission is optional but recommended)
  }

  @override
  Widget build(BuildContext context) {
    return const DashboardScreen();
  }
}
