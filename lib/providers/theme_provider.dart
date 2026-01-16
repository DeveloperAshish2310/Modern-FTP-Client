import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

/// Theme provider for managing app theme and accent color
class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = true;
  String _accentColor = 'Blue';
  SharedPreferences? _prefs;

  bool get isDarkMode => _isDarkMode;
  String get accentColor => _accentColor;

  ThemeData get theme => AppTheme.getTheme(_isDarkMode, _accentColor);

  /// Initialize theme from preferences
  Future<void> loadTheme() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs?.getBool('dark_mode') ?? true;
    _accentColor = _prefs?.getString('accent_color') ?? 'Blue';
    notifyListeners();
  }

  /// Toggle between dark and light mode
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _prefs?.setBool('dark_mode', _isDarkMode);
    notifyListeners();
  }

  /// Set specific theme mode
  Future<void> setThemeMode(bool isDark) async {
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      await _prefs?.setBool('dark_mode', _isDarkMode);
      notifyListeners();
    }
  }

  /// Set accent color
  Future<void> setAccentColor(String color) async {
    if (AppConstants.accentColors.containsKey(color)) {
      _accentColor = color;
      await _prefs?.setString('accent_color', color);
      notifyListeners();
    }
  }

  /// Get all available accent colors
  Map<String, Color> get availableColors {
    return AppConstants.accentColors.map(
      (key, value) => MapEntry(key, Color(value)),
    );
  }
}
