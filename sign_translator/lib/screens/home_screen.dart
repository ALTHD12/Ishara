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
              RadioListTile<AppTheme>(
                title: const Text('Dark'),
                value: AppTheme.dark,
                groupValue: themeProvider.currentTheme,
                onChanged: (val) {
                  if (val != null) themeProvider.setTheme(val);
                },
              ),
              RadioListTile<AppTheme>(
                title: const Text('Light'),
                value: AppTheme.light,
                groupValue: themeProvider.currentTheme,
                onChanged: (val) {
                  if (val != null) themeProvider.setTheme(val);
                },
              ),
              RadioListTile<AppTheme>(
                title: const Text('AMOLED'),
                value: AppTheme.amoled,
                groupValue: themeProvider.currentTheme,
                onChanged: (val) {
                  if (val != null) themeProvider.setTheme(val);
                },
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
