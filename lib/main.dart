import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/font_service.dart';
import 'models/booking.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  final fontService = FontService();
  await fontService.initialize();

  // Initialize BookingsStore to restore session
  await BookingsStore().initialize();

  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

  runApp(MyApp(
    showOnboarding: !onboardingComplete,
    fontService: fontService,
  ));
}

class MyApp extends StatefulWidget {
  final bool showOnboarding;
  final FontService fontService;

  const MyApp({
    super.key,
    required this.showOnboarding,
    required this.fontService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    widget.fontService.addListener(_onFontChanged);
  }

  @override
  void dispose() {
    widget.fontService.removeListener(_onFontChanged);
    super.dispose();
  }

  void _onFontChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.light().textTheme;
    final textTheme = widget.fontService.getTextTheme(baseTextTheme);

    return MaterialApp(
      title: 'TGV Max',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: textTheme,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF64748B),
          onPrimary: Colors.white,
          secondary: Color(0xFF94A3B8),
          onSecondary: Colors.white,
          tertiary: Color(0xFF78716C),
          onTertiary: Colors.white,
          error: Color(0xFFB91C1C),
          onError: Colors.white,
          surface: Color(0xFFFAFAFA),
          onSurface: Color(0xFF1E293B),
          surfaceContainerHighest: Color(0xFFF1F5F9),
          outline: Color(0xFFE2E8F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFF1E293B),
          titleTextStyle: textTheme.titleLarge?.copyWith(
            color: const Color(0xFF1E293B),
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          color: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8F0),
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: widget.showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
