import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/isl_converter_service.dart';
import 'services/sign_classifier_service.dart';
import 'services/theme_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — important for consistent hand detection
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ISLConverterService()),
        ChangeNotifierProvider(create: (_) => SignClassifierService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const ISLApp(),
    ),
  );
}

class ISLApp extends StatelessWidget {
  const ISLApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'ISL Translator',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF8F9FA),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6B5CE7),
              surface: Colors.white,
              surfaceContainerHighest: Color(0xFFE9ECEF),
              onSurface: Colors.black87,
              outline: Colors.black12,
              primaryContainer: Color(0xFFE0E7FF),
              onPrimaryContainer: Color(0xFF6B5CE7),
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0D0D12),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6B5CE7), // purple accent
              surface: Color(0xFF1A1A2E), // card background
              surfaceContainerHighest: Color(0xFF24243A),
              onSurface: Colors.white,
              outline: Colors.white12,
              primaryContainer: Color(0xFF2D2A4A),
              onPrimaryContainer: Colors.white,
            ),
            useMaterial3: true,
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}
