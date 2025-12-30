import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/font_service.dart';

class FontPickerScreen extends StatefulWidget {
  const FontPickerScreen({super.key});

  @override
  State<FontPickerScreen> createState() => _FontPickerScreenState();
}

class _FontPickerScreenState extends State<FontPickerScreen> {
  final FontService _fontService = FontService();

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _selectedColor = Color(0xFFEFF6FF);
  static const Color _selectedBorder = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _buildFontPreview(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Polices disponibles'),
                  const SizedBox(height: 12),
                  _buildFontList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: IconButton(
              icon: Icon(
                PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                size: 22,
                color: _textSecondary,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.textAa(PhosphorIconsStyle.fill),
                      size: 20,
                      color: _textPrimary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Police',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Actuellement: ${_fontService.currentFont}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Icon(
          PhosphorIcons.list(PhosphorIconsStyle.fill),
          size: 16,
          color: _textSecondary,
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildFontPreview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIcons.eye(PhosphorIconsStyle.fill),
                size: 16,
                color: _textSecondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'APERCU',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'TGV Max Checker',
            style: _fontService.getFontStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trouvez facilement vos billets gratuits TGV Max et voyagez partout en France.',
            style: _fontService.getFontStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPreviewBadge('Paris', PhosphorIcons.mapPin(PhosphorIconsStyle.fill)),
              const SizedBox(width: 8),
              Icon(
                PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                size: 14,
                color: _textMuted,
              ),
              const SizedBox(width: 8),
              _buildPreviewBadge('Lyon', PhosphorIcons.mapPin(PhosphorIconsStyle.fill)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.train(PhosphorIconsStyle.fill),
                  size: 16,
                  color: _textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '08:45',
                  style: _fontService.getFontStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                    size: 14,
                    color: _textMuted,
                  ),
                ),
                Text(
                  '10:52',
                  style: _fontService.getFontStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBBF7D0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '42 places',
                    style: _fontService.getFontStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF166534),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _textMuted),
          const SizedBox(width: 6),
          Text(
            text,
            style: _fontService.getFontStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontList() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: FontService.availableFonts.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: _borderColor),
        itemBuilder: (context, index) {
          final font = FontService.availableFonts[index];
          final isSelected = font.name == _fontService.currentFont;
          return _buildFontOption(font, isSelected);
        },
      ),
    );
  }

  Widget _buildFontOption(FontOption font, bool isSelected) {
    return GestureDetector(
      onTap: () async {
        await _fontService.setFont(font.name);
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _selectedColor : Colors.transparent,
          borderRadius: isSelected
              ? BorderRadius.circular(0)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    font.name,
                    style: _getFontPreviewStyle(font.name).copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    font.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? _selectedBorder.withOpacity(0.1) : _backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? _selectedBorder : _borderColor,
                ),
              ),
              child: Text(
                font.category,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? _selectedBorder : _textMuted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? _selectedBorder : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? _selectedBorder : _borderColor,
                  width: isSelected ? 0 : 2,
                ),
              ),
              child: isSelected
                  ? Icon(
                      PhosphorIcons.check(PhosphorIconsStyle.bold),
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _getFontPreviewStyle(String fontName) {
    switch (fontName) {
      case 'Inter':
        return GoogleFonts.inter();
      case 'Poppins':
        return GoogleFonts.poppins();
      case 'Plus Jakarta Sans':
        return GoogleFonts.plusJakartaSans();
      case 'DM Sans':
        return GoogleFonts.dmSans();
      case 'Manrope':
        return GoogleFonts.manrope();
      case 'Space Grotesk':
        return GoogleFonts.spaceGrotesk();
      case 'Outfit':
        return GoogleFonts.outfit();
      case 'Sora':
        return GoogleFonts.sora();
      case 'Nunito':
        return GoogleFonts.nunito();
      case 'Rubik':
        return GoogleFonts.rubik();
      default:
        return GoogleFonts.sora();
    }
  }
}
