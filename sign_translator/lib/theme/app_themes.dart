import 'package:flutter/material.dart';

enum AppTheme { dark, light, amoled, sunrise }

class AppThemes {
  static ThemeData getThemeData(AppTheme theme, Color accentColor) {
    switch (theme) {
      case AppTheme.dark:
        return _buildTheme(
          brightness: Brightness.dark,
          background: const Color(0xFF121212),
          surface: const Color(0xFF1E1E1E),
          border: const Color(0xFF2C2C2C),
          textPrimary: const Color(0xFFFFFFFF),
          textSecondary: const Color(0xFFAAAAAA),
          accent: accentColor,
        );
      case AppTheme.light:
        return _buildTheme(
          brightness: Brightness.light,
          background: const Color(0xFFF5F5F5),
          surface: const Color(0xFFFFFFFF),
          border: const Color(0xFFE0E0E0),
          textPrimary: const Color(0xFF121212),
          textSecondary: const Color(0xFF666666),
          accent: accentColor,
        );
      case AppTheme.amoled:
        return _buildTheme(
          brightness: Brightness.dark,
          background: const Color(0xFF000000),
          surface: const Color(0xFF0A0A0A),
          border: const Color(0xFF1A1A1A),
          textPrimary: const Color(0xFFFFFFFF),
          textSecondary: const Color(0xFF888888),
          accent: accentColor,
        );
      case AppTheme.sunrise:
        return _buildTheme(
          brightness: Brightness.light,
          background: const Color(0xFFFFF8F0),
          surface: const Color(0xFFFFECCC),
          border: const Color(0xFFF0D8B8),
          textPrimary: const Color(0xFF2C1E16),
          textSecondary: const Color(0xFF8C7361),
          accent: accentColor,
        );
    }
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: border,
        surfaceContainerHighest: surface,
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          color: textPrimary,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          color: textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // --- Typography Tokens ---
  static TextStyle labelCaps(ThemeData theme) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  static TextStyle quoteText(ThemeData theme) {
    return TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
  }

  static TextStyle buttonLabel(ThemeData theme) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: theme.colorScheme.onSurface,
    );
  }
}
