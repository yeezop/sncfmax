import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontService extends ChangeNotifier {
  static final FontService _instance = FontService._internal();
  factory FontService() => _instance;
  FontService._internal();

  static const String _fontKey = 'selected_font';
  String _currentFont = 'Sora';

  String get currentFont => _currentFont;

  // Available fonts with descriptions
  static final List<FontOption> availableFonts = [
    FontOption(
      name: 'Inter',
      description: 'Moderne et lisible',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Poppins',
      description: 'Geometrique et elegant',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Plus Jakarta Sans',
      description: 'Professionnel et raffine',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'DM Sans',
      description: 'Minimaliste et epure',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Manrope',
      description: 'Moderne et polyvalent',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Space Grotesk',
      description: 'Tech et contemporain',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Outfit',
      description: 'Clean et accessible',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Sora',
      description: 'Futuriste et unique',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Nunito',
      description: 'Doux et amical',
      category: 'Sans-serif',
    ),
    FontOption(
      name: 'Rubik',
      description: 'Arrondi et moderne',
      category: 'Sans-serif',
    ),
  ];

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _currentFont = prefs.getString(_fontKey) ?? 'Sora';
    notifyListeners();
  }

  Future<void> setFont(String fontName) async {
    if (_currentFont != fontName) {
      _currentFont = fontName;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fontKey, fontName);
      notifyListeners();
    }
  }

  TextTheme getTextTheme(TextTheme base) {
    switch (_currentFont) {
      case 'Inter':
        return GoogleFonts.interTextTheme(base);
      case 'Poppins':
        return GoogleFonts.poppinsTextTheme(base);
      case 'Plus Jakarta Sans':
        return GoogleFonts.plusJakartaSansTextTheme(base);
      case 'DM Sans':
        return GoogleFonts.dmSansTextTheme(base);
      case 'Manrope':
        return GoogleFonts.manropeTextTheme(base);
      case 'Space Grotesk':
        return GoogleFonts.spaceGroteskTextTheme(base);
      case 'Outfit':
        return GoogleFonts.outfitTextTheme(base);
      case 'Sora':
        return GoogleFonts.soraTextTheme(base);
      case 'Nunito':
        return GoogleFonts.nunitoTextTheme(base);
      case 'Rubik':
        return GoogleFonts.rubikTextTheme(base);
      default:
        return GoogleFonts.soraTextTheme(base);
    }
  }

  TextStyle getFontStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    TextStyle Function({
      double? fontSize,
      FontWeight? fontWeight,
      Color? color,
      double? letterSpacing,
      double? height,
    }) fontFunction;

    switch (_currentFont) {
      case 'Inter':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Poppins':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Plus Jakarta Sans':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.plusJakartaSans(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'DM Sans':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.dmSans(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Manrope':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.manrope(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Space Grotesk':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.spaceGrotesk(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Outfit':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.outfit(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Sora':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.sora(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Nunito':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.nunito(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      case 'Rubik':
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.rubik(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
        break;
      default:
        fontFunction = ({fontSize, fontWeight, color, letterSpacing, height}) =>
            GoogleFonts.sora(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              letterSpacing: letterSpacing,
              height: height,
            );
    }

    return fontFunction(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

class FontOption {
  final String name;
  final String description;
  final String category;

  FontOption({
    required this.name,
    required this.description,
    required this.category,
  });
}
