import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'map_screen.dart';
import 'mon_max_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _showMap = false;

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF475569);

  void _toggleMap() {
    setState(() {
      _showMap = !_showMap;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget searchTab;
    if (_showMap) {
      searchTab = MapScreen(onBackPressed: _toggleMap);
    } else {
      searchTab = CalendarScreen(onMapPressed: _toggleMap);
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          searchTab,
          const MonMaxScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _surfaceColor,
          border: Border(
            top: BorderSide(color: _borderColor, width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: PhosphorIcons.train(PhosphorIconsStyle.regular),
                  activeIcon: PhosphorIcons.train(PhosphorIconsStyle.fill),
                  label: 'Recherche',
                ),
                _buildNavItem(
                  index: 1,
                  icon: PhosphorIcons.ticket(PhosphorIconsStyle.regular),
                  activeIcon: PhosphorIcons.ticket(PhosphorIconsStyle.fill),
                  label: 'Mon Max',
                ),
                _buildNavItem(
                  index: 2,
                  icon: PhosphorIcons.gear(PhosphorIconsStyle.regular),
                  activeIcon: PhosphorIcons.gear(PhosphorIconsStyle.fill),
                  label: 'Reglages',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? _accentColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 22,
              color: isSelected ? _accentColor : _textMuted,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _accentColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
