import 'package:flutter/material.dart';
import '../theme/app_themes.dart';

class ThemeProvider extends ChangeNotifier {
  AppTheme _currentTheme = AppTheme.light; // Neobrutalism default: warm cream

  AppTheme get currentTheme => _currentTheme;

  ThemeData get themeData => AppThemes.getThemeData(_currentTheme);

  NeoThemeTokens get tokens => AppThemes.getTokens(_currentTheme);

  void setTheme(AppTheme theme) {
    if (_currentTheme != theme) {
      _currentTheme = theme;
      notifyListeners();
    }
  }
}
