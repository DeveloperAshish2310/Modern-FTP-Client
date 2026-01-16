import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'providers/connection_provider.dart';
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
            home: const DashboardScreen(),
          );
        },
      ),
    );
  }
}
