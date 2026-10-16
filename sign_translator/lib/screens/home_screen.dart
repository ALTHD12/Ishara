import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../services/theme_provider.dart';
import '../services/sign_classifier_service.dart';
import '../theme/app_themes.dart';
import '../widgets/neo_decorations.dart';
import '../widgets/connection_status_badge.dart';
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _buildCustomToggle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Text(
              'ISHARA',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 2.0,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: DotGridBackground(
        dotColor: theme.colorScheme.outline,
        child: AnimatedSwitcher(
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
      ),
    );
  }

  Widget _buildCustomToggle() {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          _isISLToEnglish = !_isISLToEnglish;
        });
      },
      child: Container(
        width: 140,
        height: 42,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
          border: AppThemes.neoBorder(theme),
          boxShadow: AppThemes.neoShadow(theme),
        ),
        child: Row(
          children: [
            // ISL side
            Expanded(
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: _isISLToEnglish
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(AppThemes.cornerRadius - 2),
                    bottomLeft: const Radius.circular(AppThemes.cornerRadius - 2),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'ISL',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.0,
                    color: _isISLToEnglish
                        ? theme.colorScheme.surface
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            // Vertical divider
            Container(
              width: AppThemes.borderWidth,
              color: theme.colorScheme.outline,
            ),
            // EN side
            Expanded(
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: !_isISLToEnglish
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topRight: const Radius.circular(AppThemes.cornerRadius - 2),
                    bottomRight: const Radius.circular(AppThemes.cornerRadius - 2),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'EN',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.0,
                    color: !_isISLToEnglish
                        ? theme.colorScheme.surface
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
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
      onTap: () => provider.setTheme(theme),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Neobrutalism drawer header ──────────────────────────────────────
          Container(
            height: 160,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline,
                  width: AppThemes.borderWidth,
                ),
              ),
            ),
            alignment: Alignment.bottomLeft,
            child: Text(
              'ISHARA',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 3.0,
              ),
            ),
          ),
          ExpansionTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(
              'THEME',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildThemeThumbnail(context, AppTheme.dark, 'DARK', themeProvider),
                      const SizedBox(width: 12),
                      _buildThemeThumbnail(context, AppTheme.light, 'LIGHT', themeProvider),
                      const SizedBox(width: 12),
                      _buildThemeThumbnail(context, AppTheme.amoled, 'AMOLED', themeProvider),
                      const SizedBox(width: 12),
                      _buildThemeThumbnail(context, AppTheme.sunrise, 'SUNRISE', themeProvider),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(
              'DATA TRAINING MODE',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 14,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DataRecorderScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: Text(
              'BACKEND SERVER',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 14,
              ),
            ),
            subtitle: Text(context.watch<SignClassifierService>().serverAddress),
            onTap: () {
              Navigator.pop(context);
              showServerSettingsDialog(context);
            },
          ),
          // Overlay face detail: FULL 478-point mesh or LIGHT contour points.
          StatefulBuilder(
            builder: (context, setTileState) => SwitchListTile(
              secondary: const Icon(Icons.face_retouching_natural),
              title: Text(
                'FACE MESH',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(AppConfig.faceMeshFull ? 'FULL' : 'LIGHT'),
              value: AppConfig.faceMeshFull,
              onChanged: (v) async {
                await context.read<SignClassifierService>().setFaceMeshFull(v);
                setTileState(() {});
              },
            ),
          ),
          // Live debug readout on the ISL->English screen (decision reason,
          // RTT / fps / bytes, overlay age). Persisted in AppConfig.
          StatefulBuilder(
            builder: (context, setTileState) => SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: Text(
                'DEBUG READOUT',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 14,
                ),
              ),
              value: AppConfig.debugReadout,
              onChanged: (v) async {
                await AppConfig.setDebugReadout(v);
                setTileState(() {});
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(
              'ABOUT',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 14,
              ),
            ),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ABOUT ISHARA'),
      ),
      body: DotGridBackground(
        dotColor: theme.colorScheme.outline,
        child: Center(
          child: NeoContainer(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'ISHARA',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: 3.0,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'SIGN TRANSLATOR',
                  style: AppThemes.labelCaps(theme),
                ),
                const SizedBox(height: 16),
                Text(
                  'VERSION 1.0.0',
                  style: AppThemes.labelCaps(theme),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bridging the gap with\nAI-powered ISL translation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
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

  const ThemePreviewThumbnail({
    super.key,
    required this.theme,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Generate the target theme data to preview
    final previewTheme = AppThemes.getThemeData(theme);
    final tokens = AppThemes.getTokens(theme);
    final currentTheme = Theme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 100,
            decoration: BoxDecoration(
              color: tokens.background,
              borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
              border: Border.all(
                color: isSelected ? currentTheme.colorScheme.primary : tokens.borderColor,
                width: isSelected ? AppThemes.borderWidth : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.borderColor,
                  offset: const Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppThemes.cornerRadius - 2),
              child: Column(
                children: [
                  // Fake App Bar
                  Container(
                    height: 14,
                    color: tokens.surface,
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: tokens.borderColor, width: 1),
                        ),
                      ),
                    ),
                  ),
                  // Divider line
                  Container(height: 1.5, color: tokens.borderColor),
                  // Fake Camera/Avatar Area
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme == AppTheme.amoled 
                            ? Colors.black 
                            : tokens.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: tokens.borderColor, width: 1.5),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.person_outline,
                          size: 20,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                  ),
                  // Fake Primary Button
                  Container(
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: tokens.borderColor, width: 1),
                    ),
                  ),
                  // Fake Text/Context Area
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: tokens.borderColor, width: 1.5),
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
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              letterSpacing: 1.0,
              color: isSelected
                  ? currentTheme.colorScheme.primary
                  : currentTheme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
