import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/connected_journey.dart';

/// Card widget to display a connected journey with multiple segments
class ConnectedJourneyCard extends StatelessWidget {
  final ConnectedJourney journey;
  final VoidCallback? onTap;

  const ConnectedJourneyCard({
    super.key,
    required this.journey,
    this.onTap,
  });

  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);

  Color get _seatColor {
    if (journey.availableSeats > 20) return const Color(0xFF166534);
    if (journey.availableSeats > 5) return const Color(0xFF854D0E);
    return const Color(0xFF991B1B);
  }

  Color get _seatBgColor {
    if (journey.availableSeats > 20) return const Color(0xFFDCFCE7);
    if (journey.availableSeats > 5) return const Color(0xFFFEF9C3);
    return const Color(0xFFFEE2E2);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with times, duration and seats
            _buildHeader(),

            // Divider
            Container(
              height: 1,
              color: _borderColor,
            ),

            // Journey segments timeline
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSegmentsTimeline(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Times and duration
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Departure -> Arrival times
                Row(
                  children: [
                    Text(
                      journey.formattedDeparture,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: _textPrimary,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(
                        PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                        size: 16,
                        color: _textMuted,
                      ),
                    ),
                    Text(
                      journey.formattedArrival,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Duration and connections count
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.timer(PhosphorIconsStyle.regular),
                      size: 14,
                      color: _textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      journey.formattedTotalDuration,
                      style: TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      PhosphorIcons.shuffle(PhosphorIconsStyle.regular),
                      size: 14,
                      color: _accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${journey.connectionCount} corresp.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Seats badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _seatBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  PhosphorIcons.seatbelt(PhosphorIconsStyle.fill),
                  size: 18,
                  color: _seatColor,
                ),
                const SizedBox(height: 2),
                Text(
                  '${journey.availableSeats}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: _seatColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentsTimeline() {
    return Column(
      children: [
        for (int i = 0; i < journey.segments.length; i++) ...[
          _buildSegmentRow(journey.segments[i], i == 0, i == journey.segments.length - 1),
          if (i < journey.segments.length - 1)
            _buildConnectionRow(journey.connections[i]),
        ],
      ],
    );
  }

  Widget _buildSegmentRow(JourneySegment segment, bool isFirst, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline indicator column
          SizedBox(
            width: 24,
            child: Column(
              children: [
                // Top line (extends from previous connection or nothing for first)
                if (!isFirst)
                  Expanded(
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _accentColor.withValues(alpha: 0.3),
                            _accentColor.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _DottedLinePainter(color: _accentColor.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                // Circle indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                // Bottom line (extends to next connection or nothing for last)
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
          const SizedBox(width: 8),
          // Segment details
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // Train type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      segment.trainType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Train number
                  Text(
                    segment.trainNumber,
                    style: TextStyle(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                  ),
                  const Spacer(),

                  // Times
                  Text(
                    '${segment.formattedDeparture} - ${segment.formattedArrival}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Seats for this segment
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.seatbelt(PhosphorIconsStyle.regular),
                        size: 12,
                        color: _textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${segment.availableSeats}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
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

  Widget _buildConnectionRow(ConnectionInfo connection) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline with connection marker
          SizedBox(
            width: 24,
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
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _accentColor, width: 2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Connection info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
                    size: 14,
                    color: _accentColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      connection.stationName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIcons.clockCountdown(PhosphorIconsStyle.regular),
                          size: 12,
                          color: const Color(0xFF92400E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          connection.formattedWaitTime,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
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
        ],
      ),
    );
  }
}

/// Custom painter for dotted vertical line
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
    final centerX = size.width / 2;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(centerX, startY),
        Offset(centerX, (startY + dashHeight).clamp(0, size.height)),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
