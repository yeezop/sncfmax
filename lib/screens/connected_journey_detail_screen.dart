import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../models/connected_journey.dart';

class ConnectedJourneyDetailScreen extends StatelessWidget {
  final ConnectedJourney journey;
  final DateTime date;

  const ConnectedJourneyDetailScreen({
    super.key,
    required this.journey,
    required this.date,
  });

  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
            color: _textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          DateFormat('EEEE d MMMM', 'fr_FR').format(date),
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 16),
            _buildTimelineCard(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          // Route
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      journey.originName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      journey.formattedDeparture,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                  color: _textMuted,
                  size: 20,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      journey.destinationName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      textAlign: TextAlign.end,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      journey.formattedArrival,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat(
                  icon: PhosphorIcons.timer(PhosphorIconsStyle.regular),
                  label: 'Durée',
                  value: journey.formattedTotalDuration,
                ),
                Container(width: 1, height: 40, color: _borderColor),
                _buildStat(
                  icon: PhosphorIcons.shuffle(PhosphorIconsStyle.regular),
                  label: 'Correspondances',
                  value: '${journey.connectionCount}',
                  valueColor: _accentColor,
                ),
                Container(width: 1, height: 40, color: _borderColor),
                _buildStat(
                  icon: PhosphorIcons.seatbelt(PhosphorIconsStyle.regular),
                  label: 'Places',
                  value: '${journey.availableSeats}',
                  valueColor: _getSeatColor(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: _textMuted),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: valueColor ?? _textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: _textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.path(PhosphorIconsStyle.fill),
                  size: 16,
                  color: _accentColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Détail du trajet',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (int i = 0; i < journey.segments.length; i++) ...[
                  _buildSegmentDetail(journey.segments[i], i == 0, i == journey.segments.length - 1),
                  if (i < journey.segments.length - 1)
                    _buildConnectionDetail(journey.connections[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentDetail(JourneySegment segment, bool isFirst, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Top line (extends from previous connection)
                if (!isFirst)
                  Expanded(
                    child: SizedBox(
                      width: 2,
                      child: CustomPaint(
                        painter: _DottedLinePainter(color: _accentColor.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                // Circle indicator
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: _surfaceColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                // Bottom line (extends to next connection)
                if (!isLast)
                  Expanded(
                    child: SizedBox(
                      width: 2,
                      child: CustomPaint(
                        painter: _DottedLinePainter(color: _accentColor.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
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
                  // Train info
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.train(PhosphorIconsStyle.fill),
                              size: 14,
                              color: _accentColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${segment.trainType} ${segment.trainNumber}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _getSeatBgColor(segment.availableSeats),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.seatbelt(PhosphorIconsStyle.fill),
                              size: 14,
                              color: _getSeatColorForCount(segment.availableSeats),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${segment.availableSeats}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _getSeatColorForCount(segment.availableSeats),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Departure
                  Row(
                    children: [
                      Text(
                        segment.formattedDeparture,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          segment.originName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Duration indicator
                  Row(
                    children: [
                      Container(
                        width: 60,
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(
                              PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                              size: 14,
                              color: _textMuted,
                            ),
                            Text(
                              segment.train.formattedDuration,
                              style: const TextStyle(
                                fontSize: 11,
                                color: _textMuted,
                              ),
                            ),
                            Icon(
                              PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                              size: 14,
                              color: _textMuted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Arrival
                  Row(
                    children: [
                      Text(
                        segment.formattedArrival,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          segment.destinationName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionDetail(ConnectionInfo connection) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline with connection marker
          SizedBox(
            width: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dotted line through the entire height
                Positioned.fill(
                  child: Center(
                    child: SizedBox(
                      width: 2,
                      child: CustomPaint(
                        painter: _DottedLinePainter(color: _accentColor.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                ),
                // Connection marker (circle with white fill and border)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _accentColor, width: 2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Connection info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
                      size: 18,
                      color: const Color(0xFF92400E),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Correspondance à ${connection.stationName}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Arrivée ${connection.formattedArrival} • Départ ${connection.formattedDeparture}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.clockCountdown(PhosphorIconsStyle.fill),
                            size: 14,
                            color: const Color(0xFF92400E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            connection.formattedWaitTime,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeatColor() {
    if (journey.availableSeats > 20) return const Color(0xFF166534);
    if (journey.availableSeats > 5) return const Color(0xFF854D0E);
    return const Color(0xFF991B1B);
  }

  Color _getSeatColorForCount(int count) {
    if (count > 20) return const Color(0xFF166534);
    if (count > 5) return const Color(0xFF854D0E);
    return const Color(0xFF991B1B);
  }

  Color _getSeatBgColor(int count) {
    if (count > 20) return const Color(0xFFDCFCE7);
    if (count > 5) return const Color(0xFFFEF9C3);
    return const Color(0xFFFEE2E2);
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashHeight = 4.0;
    const dashSpace = 4.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
