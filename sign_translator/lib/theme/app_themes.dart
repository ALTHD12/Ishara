import 'package:flutter/material.dart';

enum AppTheme { dark, light, amoled, sunrise }

/// Neobrutalism design tokens for a specific theme.
class NeoThemeTokens {
  final Color background;
  final Color surface;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color secondary;
  final Brightness brightness;

  const NeoThemeTokens({
    required this.background,
    required this.surface,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.secondary,
    required this.brightness,
  });
}

class AppThemes {
  // ── Neobrutalism Constants ──────────────────────────────────────────────────
  static const double borderWidth = 3.0;
  static const double shadowOffsetX = 4.0;
  static const double shadowOffsetY = 4.0;
  static const double cornerRadius = 8.0;

  // ── Theme Palette Definitions ───────────────────────────────────────────────
  static const _palettes = <AppTheme, NeoThemeTokens>{
    AppTheme.light: NeoThemeTokens(
      background: Color(0xFFFFFBE6),   // warm cream
      surface: Color(0xFFFFFBE6),
      borderColor: Color(0xFF000000),
      textPrimary: Color(0xFF000000),
      textSecondary: Color(0xFF555555),
      accent: Color(0xFFFF3B5C),       // hot pink
      secondary: Color(0xFFFFD600),    // yellow
      brightness: Brightness.light,
    ),
    AppTheme.dark: NeoThemeTokens(
      background: Color(0xFF1A1A1A),
      surface: Color(0xFF2D2D2D),      // dark cards for contrast with light text
      borderColor: Color(0xFF000000),
      textPrimary: Color(0xFFFFFBE6),
      textSecondary: Color(0xFFAAAAAA),
      accent: Color(0xFFFF3B5C),
      secondary: Color(0xFFFFD600),
      brightness: Brightness.dark,
    ),
    AppTheme.amoled: NeoThemeTokens(
      background: Color(0xFF000000),
      surface: Color(0xFF1A1A1A),
      borderColor: Color(0xFFFFFFFF),  // white borders on pure black
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFF888888),
      accent: Color(0xFFFFD600),       // yellow accent
      secondary: Color(0xFFFF3B5C),
      brightness: Brightness.dark,
    ),
    AppTheme.sunrise: NeoThemeTokens(
      background: Color(0xFFFF8C42),   // warm orange
      surface: Color(0xFFFFFBE6),
      borderColor: Color(0xFF000000),
      textPrimary: Color(0xFF000000),
      textSecondary: Color(0xFF4A3520),
      accent: Color(0xFFFFD600),       // yellow accent
      secondary: Color(0xFFFF3B5C),
      brightness: Brightness.light,
    ),
  };

  static NeoThemeTokens getTokens(AppTheme theme) => _palettes[theme]!;

  // ── ThemeData Builder ───────────────────────────────────────────────────────
  static ThemeData getThemeData(AppTheme theme) {
    final t = _palettes[theme]!;
    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      scaffoldBackgroundColor: t.background,
      fontFamily: 'Inter',
      colorScheme: ColorScheme(
        brightness: t.brightness,
        primary: t.accent,
        onPrimary: Colors.white,
        secondary: t.secondary,
        onSecondary: Colors.black,
        error: const Color(0xFFFF3B5C),
        onError: Colors.white,
        surface: t.surface,
        onSurface: t.textPrimary,
        onSurfaceVariant: t.textSecondary,
        outline: t.borderColor,
        surfaceContainerHighest: t.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: t.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.surface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(color: t.borderColor, width: borderWidth),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        side: BorderSide(color: t.borderColor, width: borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: t.textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
            side: BorderSide(color: t.borderColor, width: borderWidth),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.borderColor, width: borderWidth),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: t.borderColor, width: borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: t.borderColor, width: borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          borderSide: BorderSide(color: t.borderColor, width: 4),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          color: t.textSecondary.withValues(alpha: 0.5),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          color: t.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          color: t.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          color: t.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          color: t.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          color: t.textSecondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          fontSize: 11,
        ),
      ),
    );
  }

  // ── Neobrutalism Decoration Helpers ─────────────────────────────────────────

  /// Standard 3px solid border using the theme's border color.
  static Border neoBorder(ThemeData theme) {
    return Border.all(
      color: theme.colorScheme.outline,
      width: borderWidth,
    );
  }

  /// Hard offset drop shadow: 4px right, 4px down, solid, zero blur.
  static List<BoxShadow> neoShadow(ThemeData theme) {
    return [
      BoxShadow(
        color: theme.colorScheme.outline,
        offset: const Offset(shadowOffsetX, shadowOffsetY),
        blurRadius: 0,
      ),
    ];
  }

  /// Combined neobrutalism BoxDecoration: border + shadow + 8px radius + fill.
  static BoxDecoration neoDecoration(ThemeData theme, {Color? color}) {
    return BoxDecoration(
      color: color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(cornerRadius),
      border: neoBorder(theme),
      boxShadow: neoShadow(theme),
    );
  }

  /// Neobrutalism BoxDecoration without shadow (for nested/flat elements).
  static BoxDecoration neoDecorationFlat(ThemeData theme, {Color? color}) {
    return BoxDecoration(
      color: color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(cornerRadius),
      border: neoBorder(theme),
    );
  }

  // ── Typography Tokens ───────────────────────────────────────────────────────

  /// Small caps label — all-caps, extra-heavy weight.
  static TextStyle labelCaps(ThemeData theme) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// Large bold quote text.
  static TextStyle quoteText(ThemeData theme) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.onSurface,
    );
  }

  /// Button label — all-caps, extra-heavy.
  static TextStyle buttonLabel(ThemeData theme) {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
      color: theme.colorScheme.onSurface,
    );
  }
}
