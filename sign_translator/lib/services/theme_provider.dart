import 'package:flutter/material.dart';
import '../theme/app_themes.dart';

class ThemeProvider extends ChangeNotifier {
  AppTheme _currentTheme = AppTheme.dark;
  Color _accentColor = const Color(0xFF880E4F); // Default Plum

  AppTheme get currentTheme => _currentTheme;
  Color get accentColor => _accentColor;

  ThemeData get themeData => AppThemes.getThemeData(_currentTheme, _accentColor);

  void setTheme(AppTheme theme) {
    if (_currentTheme != theme) {
      _currentTheme = theme;
      notifyListeners();
    }
  }

  void setAccentColor(Color color) {
    if (_accentColor != color) {
      _accentColor = color;
      notifyListeners();
    }
  }
}
