import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_provider.dart';
import '../theme/app_themes.dart';
import 'isl_to_english_screen.dart';
import 'english_to_isl_screen.dart';
import 'data_recorder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isISLToEnglish = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _buildCustomToggle(),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.circle, color: Colors.green, size: 12),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _isISLToEnglish
            ? const ISLToEnglishScreen(key: ValueKey('isl_to_en'))
            : const EnglishToISLScreen(key: ValueKey('en_to_isl')),
      ),
    );
  }

  Widget _buildCustomToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isISLToEnglish = !_isISLToEnglish;
        });
      },
      child: Container(
        width: 140,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(30), // Pill shaped
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: _isISLToEnglish ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: 70,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary, // Dynamic Accent Color
                  borderRadius: BorderRadius.circular(30),
                ),
                alignment: Alignment.center,
                child: Text(
                  _isISLToEnglish ? 'ISL' : 'EN',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Unselected text labels to keep it visible on both sides
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'ISL',
                      style: TextStyle(
                        color: _isISLToEnglish ? Colors.transparent : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'EN',
                      style: TextStyle(
                        color: !_isISLToEnglish ? Colors.transparent : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorSwatch(BuildContext context, Color color, ThemeProvider provider) {
    final isSelected = provider.accentColor == color;
    return GestureDetector(
      onTap: () => provider.setAccentColor(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              )
          ],
        ),
      ),
    );
  }

  Widget _buildThemeThumbnail(BuildContext context, AppTheme theme, String label, ThemeProvider provider) {
    return ThemePreviewThumbnail(
      theme: theme,
      label: label,
      isSelected: provider.currentTheme == theme,
      accentColor: provider.accentColor,
      onTap: () => provider.setTheme(theme),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Ishara',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ExpansionTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildThemeThumbnail(context, AppTheme.dark, 'Dark', themeProvider),
                      const SizedBox(width: 12),
                      _buildThemeThumbnail(context, AppTheme.light, 'Light', themeProvider),
                      const SizedBox(width: 12),
                      _buildThemeThumbnail(context, AppTheme.amoled, 'AMOLED', themeProvider),
                      const SizedBox(width: 12),
                      _buildThemeThumbnail(context, AppTheme.sunrise, 'Sunrise', themeProvider),
                    ],
                  ),
                ),
              ),
              // Color Picker Pill
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildColorSwatch(context, Colors.redAccent, themeProvider),
                    _buildColorSwatch(context, Colors.blueAccent, themeProvider),
                    _buildColorSwatch(context, Colors.greenAccent, themeProvider),
                    _buildColorSwatch(context, Colors.white, themeProvider),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Data Training Mode'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DataRecorderScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPlaceholderScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AboutPlaceholderScreen extends StatelessWidget {
  const AboutPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Ishara'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Color(0xFF880E4F)),
              const SizedBox(height: 24),
              Text(
                'Ishara Sign Translator',
                style: AppThemes.quoteText(Theme.of(context)),
              ),
              const SizedBox(height: 16),
              Text(
                'Version 1.0.0\nBridging the gap with AI-powered ISL translation.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThemePreviewThumbnail extends StatelessWidget {
  final AppTheme theme;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color accentColor;

  const ThemePreviewThumbnail({
    super.key,
    required this.theme,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // Generate the target theme data to preview
    final previewTheme = AppThemes.getThemeData(theme, accentColor);
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 100,
            decoration: BoxDecoration(
              color: previewTheme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? accentColor : previewTheme.colorScheme.outline,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9), // slightly less than container to fit inside border
              child: Column(
                children: [
                  // Fake App Bar
                  Container(
                    height: 14,
                    color: previewTheme.colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 6,
                        decoration: BoxDecoration(
                          color: previewTheme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  // Fake Camera/Avatar Area
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme == AppTheme.amoled 
                            ? Colors.black 
                            : previewTheme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: previewTheme.colorScheme.outlineVariant),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.person_outline,
                          size: 20,
                          color: previewTheme.colorScheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  // Fake Primary Button
                  Container(
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: previewTheme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  // Fake Text/Context Area
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      decoration: BoxDecoration(
                        color: previewTheme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: previewTheme.colorScheme.outlineVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

