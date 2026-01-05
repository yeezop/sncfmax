import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/search_preferences.dart';

/// Collapsible widget for selecting connection preferences
class ConnectionSelector extends StatefulWidget {
  final SearchPreferences preferences;
  final ValueChanged<SearchPreferences> onPreferencesChanged;

  const ConnectionSelector({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
  });

  @override
  State<ConnectionSelector> createState() => _ConnectionSelectorState();
}

class _ConnectionSelectorState extends State<ConnectionSelector>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotationAnimation;

  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _accentColor = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(_expandAnimation);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed header - always visible
          GestureDetector(
            onTap: _toggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.path(PhosphorIconsStyle.regular),
                    size: 16,
                    color: widget.preferences.allowsConnections
                        ? _accentColor
                        : _textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.preferences.connectionMode.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: widget.preferences.allowsConnections
                            ? _accentColor
                            : _textPrimary,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _rotationAnimation,
                    child: Icon(
                      PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                      size: 16,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 1,
                  color: _borderColor,
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ConnectionMode.values.map((mode) {
                      final isSelected =
                          widget.preferences.connectionMode == mode;
                      return _buildModeChip(mode, isSelected);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(ConnectionMode mode, bool isSelected) {
    return GestureDetector(
      onTap: () {
        widget.onPreferencesChanged(
            widget.preferences.copyWith(connectionMode: mode));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _accentColor.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _accentColor : _borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mode == ConnectionMode.directOnly)
              Icon(
                PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                size: 12,
                color: isSelected ? _accentColor : _textSecondary,
              )
            else
              Icon(
                PhosphorIcons.shuffle(PhosphorIconsStyle.regular),
                size: 12,
                color: isSelected ? _accentColor : _textSecondary,
              ),
            const SizedBox(width: 4),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? _accentColor : _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
