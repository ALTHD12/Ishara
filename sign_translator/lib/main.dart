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
          theme: themeProvider.themeData,
          home: const HomeScreen(),
        );
      },
    );
  }
}
