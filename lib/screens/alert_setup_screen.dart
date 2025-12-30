import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';

class AlertSetupScreen extends StatefulWidget {
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final DateTime date;

  const AlertSetupScreen({
    super.key,
    required this.originCode,
    required this.originName,
    required this.destinationCode,
    required this.destinationName,
    required this.date,
  });

  @override
  State<AlertSetupScreen> createState() => _AlertSetupScreenState();
}

class _AlertSetupScreenState extends State<AlertSetupScreen> {
  // Muted color palette (same as calendar screen)
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _accentLight = Color(0xFFDBEAFE);

  // Form state
  TimeOfDay _startTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);
  bool _notifyOnFirstAvailable = true;
  bool _notifyOnMultipleSeats = false;
  int _minSeats = 1;
  bool _isCreatingAlert = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRouteCard(),
                    const SizedBox(height: 20),
                    _buildDateCard(),
                    const SizedBox(height: 20),
                    _buildTimeRangeCard(),
                    const SizedBox(height: 20),
                    _buildNotificationOptionsCard(),
                    const SizedBox(height: 32),
                    _buildCreateButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
              color: _textPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.bell(PhosphorIconsStyle.fill),
                      size: 20,
                      color: _accentColor,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Nouvelle alerte',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Soyez notifie des que des places se liberent',
                  style: TextStyle(
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

  Widget _buildRouteCard() {
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
                PhosphorIcons.path(PhosphorIconsStyle.fill),
                size: 16,
                color: _textMuted,
              ),
              const SizedBox(width: 8),
              const Text(
                'TRAJET',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Depart',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.originName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(left: 5),
            width: 2,
            height: 24,
            decoration: BoxDecoration(
              color: _borderColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  border: Border.all(color: _accentColor, width: 3),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Arrivee',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.destinationName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard() {
    final formattedDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(widget.date);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accentLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              PhosphorIcons.calendar(PhosphorIconsStyle.fill),
              size: 24,
              color: _accentColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DATE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeCard() {
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
                PhosphorIcons.clock(PhosphorIconsStyle.fill),
                size: 16,
                color: _textMuted,
              ),
              const SizedBox(width: 8),
              const Text(
                'PLAGE HORAIRE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTimeSelector(
                  label: 'De',
                  time: _startTime,
                  onTap: () => _selectTime(isStart: true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTimeSelector(
                  label: 'A',
                  time: _endTime,
                  onTap: () => _selectTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.info(PhosphorIconsStyle.fill),
                  size: 16,
                  color: _textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vous serez alerte uniquement pour les trains dans cette plage horaire',
                    style: TextStyle(
                      fontSize: 12,
                      color: _textSecondary,
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

  Widget _buildTimeSelector({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    final formattedTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formattedTime,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                Icon(
                  PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                  size: 16,
                  color: _textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationOptionsCard() {
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
                PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                size: 16,
                color: _textMuted,
              ),
              const SizedBox(width: 8),
              const Text(
                'OPTIONS DE NOTIFICATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSwitchOption(
            icon: PhosphorIcons.lightning(PhosphorIconsStyle.fill),
            title: 'Premiere place disponible',
            subtitle: 'Alerte des qu\'une place se libere',
            value: _notifyOnFirstAvailable,
            onChanged: (value) {
              setState(() {
                _notifyOnFirstAvailable = value;
              });
            },
          ),
          const SizedBox(height: 12),
          _buildSwitchOption(
            icon: PhosphorIcons.usersThree(PhosphorIconsStyle.fill),
            title: 'Plusieurs places',
            subtitle: 'Alerte seulement si $_minSeats+ places',
            value: _notifyOnMultipleSeats,
            onChanged: (value) {
              setState(() {
                _notifyOnMultipleSeats = value;
                if (!value) _minSeats = 1;
              });
            },
          ),
          if (_notifyOnMultipleSeats) ...[
            const SizedBox(height: 16),
            _buildSeatsSlider(),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? _accentLight.withOpacity(0.5) : _backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? _accentColor.withOpacity(0.3) : _borderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value ? _accentColor : _borderColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? Colors.white : _textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSeatsSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nombre minimum de places',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_minSeats',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _borderColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withOpacity(0.2),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _minSeats.toDouble(),
              min: 2,
              max: 10,
              divisions: 8,
              onChanged: (value) {
                setState(() {
                  _minSeats = value.round();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isCreatingAlert ? null : _createAlert,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isCreatingAlert
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Creer l\'alerte',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _selectTime({required bool isStart}) async {
    final initialTime = isStart ? _startTime : _endTime;

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accentColor,
              onPrimary: Colors.white,
              surface: _surfaceColor,
              onSurface: _textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _createAlert() async {
    setState(() {
      _isCreatingAlert = true;
    });

    // Simulate API call - TODO: implement actual alert creation
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isCreatingAlert = false;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Alerte creee avec succes !'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );

      Navigator.of(context).pop(true);
    }
  }
}
