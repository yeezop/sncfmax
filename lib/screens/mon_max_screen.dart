import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/booking.dart';
import '../services/backend_api_service.dart';
import '../services/silent_refresh_service.dart';
import 'sncf_login_screen.dart';
import 'auto_confirm_settings_screen.dart';

class MonMaxScreen extends StatefulWidget {
  const MonMaxScreen({super.key});

  @override
  State<MonMaxScreen> createState() => _MonMaxScreenState();
}

class _MonMaxScreenState extends State<MonMaxScreen> {
  final BookingsStore _store = BookingsStore();

  bool _isLoading = false;
  String? _error;
  Set<String> _scheduledAutoConfirms = {};

  static const String _autoConfirmKey = 'auto_confirm_bookings';

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _loadScheduledAutoConfirms();
    _checkAndRunAutoConfirms();
  }

  Future<void> _loadScheduledAutoConfirms() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_autoConfirmKey) ?? [];
    setState(() {
      _scheduledAutoConfirms = list.toSet();
    });
  }

  Future<void> _saveScheduledAutoConfirms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_autoConfirmKey, _scheduledAutoConfirms.toList());
  }

  Future<void> _checkAndRunAutoConfirms() async {
    if (!_store.isAuthenticated) return;

    final prefs = await SharedPreferences.getInstance();
    final scheduledIds = prefs.getStringList(_autoConfirmKey) ?? [];
    if (scheduledIds.isEmpty) return;

    // Find bookings that are now ready to confirm
    for (final orderId in scheduledIds.toList()) {
      final booking = _store.bookings.where((b) => b.orderId == orderId).firstOrNull;
      if (booking == null) {
        // Booking not found, remove from list
        scheduledIds.remove(orderId);
        continue;
      }

      if (booking.canConfirmNow || booking.needsConfirmation) {
        debugPrint('[MonMax] Auto-confirming booking: ${booking.orderId}');

        // Try to confirm
        final result = await SilentRefreshService().confirmBooking(booking);

        if (result.success) {
          // Update local status
          final bookings = _store.bookings;
          final index = bookings.indexWhere((b) => b.orderId == booking.orderId);
          if (index != -1) {
            final updatedBooking = Booking(
              arrivalDateTime: booking.arrivalDateTime,
              departureDateTime: booking.departureDateTime,
              origin: booking.origin,
              destination: booking.destination,
              trainNumber: booking.trainNumber,
              coachNumber: booking.coachNumber,
              seatNumber: booking.seatNumber,
              dvNumber: booking.dvNumber,
              orderId: booking.orderId,
              serviceItemId: booking.serviceItemId,
              travelClass: booking.travelClass,
              travelStatus: booking.travelStatus,
              travelConfirmed: 'CONFIRMED',
              reservationDate: booking.reservationDate,
              avantage: booking.avantage,
              marketingCarrierRef: booking.marketingCarrierRef,
            );
            bookings[index] = updatedBooking;
            await _store.updateBookings(bookings);
          }

          // Remove from scheduled list
          scheduledIds.remove(orderId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('${booking.origin.shortName} → ${booking.destination.shortName} confirmé auto !'),
                    ),
                  ],
                ),
                backgroundColor: _successColor,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    }

    // Save updated list
    await prefs.setStringList(_autoConfirmKey, scheduledIds);
    setState(() {
      _scheduledAutoConfirms = scheduledIds.toSet();
    });
  }

  void _refresh() {
    setState(() {});
  }

  Future<void> _openLogin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const SncfLoginScreen(),
      ),
    );

    if (result == true) {
      _refresh();
    }
  }

  void _openAutoConfirmSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AutoConfirmSettingsScreen(),
      ),
    );
  }

  /// Refresh bookings silently using WebView cookies (real fresh data)
  Future<void> _refreshSilently() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('[MonMax] Starting silent refresh...');
      final result = await SilentRefreshService().refreshBookings();

      if (result.success && result.bookings != null) {
        // Update local store
        await _store.updateBookings(result.bookings!);

        // Also update backend cache
        try {
          final session = _store.userSession;
          if (session != null && result.bookingsRaw != null) {
            await BackendApiService().storeSession(
              cardNumber: session.cardNumber ?? '',
              firstName: session.firstName ?? '',
              lastName: session.lastName ?? '',
              email: session.email,
              bookings: result.bookingsRaw!,
            );
          }
        } catch (e) {
          debugPrint('[MonMax] Failed to update backend: $e');
        }

        if (mounted) {
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
                  Text('${result.bookings!.length} reservations'),
                ],
              ),
              backgroundColor: _successColor,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (result.needsReauth) {
        // Session expired - show message but keep cached data visible
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    PhosphorIcons.warning(PhosphorIconsStyle.fill),
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Session expiree. Reconnectez-vous pour actualiser.'),
                  ),
                ],
              ),
              backgroundColor: _warningColor,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Connexion',
                textColor: Colors.white,
                onPressed: _openLogin,
              ),
            ),
          );
        }
      } else {
        throw Exception(result.error ?? 'Erreur inconnue');
      }
    } catch (e) {
      debugPrint('[MonMax] Refresh error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    await _store.clear();
    BackendApiService().logout(); // Also logout from backend
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: _textSecondary,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (_error != null)
              Expanded(child: _buildError())
            else if (!_store.isAuthenticated)
              Expanded(child: _buildLoginPrompt())
            else
              Expanded(child: _buildBookingsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    PhosphorIcons.ticket(PhosphorIconsStyle.fill),
                    size: 24,
                    color: _textPrimary,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Mon Max',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _store.isAuthenticated
                        ? 'Bonjour, ${_store.userSession?.firstName ?? ""}!'
                        : 'Vos reservations TGV Max',
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (_store.isAuthenticated && _store.lastUpdated != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _store.isDataStale
                            ? _warningColor.withOpacity(0.1)
                            : _successColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _store.lastUpdatedFormatted,
                        style: TextStyle(
                          fontSize: 11,
                          color: _store.isDataStale ? _warningColor : _successColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (_store.isAuthenticated)
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: IconButton(
                    icon: Icon(
                      PhosphorIcons.robot(PhosphorIconsStyle.regular),
                      size: 22,
                      color: _textSecondary,
                    ),
                    onPressed: _openAutoConfirmSettings,
                    tooltip: 'Confirmation auto',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: IconButton(
                    icon: Icon(
                      PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.regular),
                      size: 22,
                      color: _textSecondary,
                    ),
                    onPressed: _refreshSilently, // Silent refresh using WebView cookies
                    tooltip: 'Actualiser',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: IconButton(
                    icon: Icon(
                      PhosphorIcons.signOut(PhosphorIconsStyle.regular),
                      size: 22,
                      color: _textSecondary,
                    ),
                    onPressed: _logout,
                    tooltip: 'Deconnexion',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                PhosphorIcons.userCircle(PhosphorIconsStyle.duotone),
                size: 64,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Connectez-vous',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connectez-vous a votre compte SNCF\npour voir vos reservations TGV Max',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIcons.signIn(PhosphorIconsStyle.bold),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Se connecter',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                PhosphorIcons.warningCircle(PhosphorIconsStyle.duotone),
                size: 48,
                color: const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _error ?? 'Une erreur est survenue',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _openLogin,
              icon: Icon(PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.regular)),
              label: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList() {
    final bookings = _store.bookings;
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.ticket(PhosphorIconsStyle.duotone),
              size: 64,
              color: _textMuted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucune reservation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vous n\'avez pas encore de reservations',
              style: TextStyle(
                fontSize: 14,
                color: _textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Separate upcoming and past bookings
    final now = DateTime.now();
    final upcomingBookings = bookings.where((b) => b.departure.isAfter(now)).toList()
      ..sort((a, b) => a.departure.compareTo(b.departure)); // Soonest first
    final pastBookings = bookings.where((b) => b.departure.isBefore(now)).toList()
      ..sort((a, b) => b.departure.compareTo(a.departure)); // Most recent first

    return RefreshIndicator(
      onRefresh: _refreshSilently, // Silent refresh using WebView cookies
      color: _accentColor,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          if (upcomingBookings.isNotEmpty) ...[
            _buildSectionHeader('A venir', upcomingBookings.length),
            ...upcomingBookings.map((b) => _buildBookingCard(b, isUpcoming: true)),
          ],
          if (pastBookings.isNotEmpty) ...[
            _buildSectionHeader('Passes', pastBookings.length),
            ...pastBookings.map((b) => _buildBookingCard(b, isUpcoming: false)),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _borderColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Booking booking, {required bool isUpcoming}) {
    final statusColor = booking.isConfirmed
        ? _successColor
        : booking.needsConfirmation
            ? _warningColor
            : booking.isTooEarly
                ? _accentColor
                : _textMuted;

    // Colors for past bookings are more muted
    final cardTextPrimary = isUpcoming ? _textPrimary : _textMuted;
    final cardTextSecondary = isUpcoming ? _textSecondary : _textMuted.withOpacity(0.7);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUpcoming ? _surfaceColor : _surfaceColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: booking.isToday ? _accentColor.withOpacity(0.5) : _borderColor.withOpacity(isUpcoming ? 1 : 0.5),
          width: booking.isToday ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header with date
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isUpcoming ? _backgroundColor : Colors.transparent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.calendar(PhosphorIconsStyle.fill),
                  size: 16,
                  color: isUpcoming ? _accentColor : _textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  booking.formattedDate,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isUpcoming ? _accentColor : _textMuted,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        booking.isConfirmed
                            ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                            : booking.needsConfirmation
                                ? PhosphorIcons.warning(PhosphorIconsStyle.fill)
                                : PhosphorIcons.clock(PhosphorIconsStyle.fill),
                        size: 12,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        booking.confirmationStatus,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
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
                            booking.formattedDeparture,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: cardTextPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            booking.origin.shortName,
                            style: TextStyle(
                              fontSize: 13,
                              color: cardTextSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Icon(
                            PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                            size: 18,
                            color: cardTextSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            booking.formattedDuration,
                            style: TextStyle(
                              fontSize: 11,
                              color: cardTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            booking.formattedArrival,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: cardTextPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            booking.destination.shortName,
                            style: TextStyle(
                              fontSize: 13,
                              color: cardTextSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Details row
                Row(
                  children: [
                    Expanded(
                      child: _buildSeatInfo(
                        'Voiture',
                        booking.coachNumber,
                        PhosphorIcons.trainSimple(PhosphorIconsStyle.fill),
                        muted: !isUpcoming,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSeatInfo(
                        'Place',
                        booking.seatNumber,
                        PhosphorIcons.armchair(PhosphorIconsStyle.fill),
                        muted: !isUpcoming,
                      ),
                    ),
                  ],
                ),

                // Action buttons for upcoming bookings
                if (isUpcoming && !booking.isConfirmed) ...[
                  const SizedBox(height: 16),

                  // Too early to confirm - show when available + auto button
                  if (booking.isTooEarly) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _accentColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _accentColor.withAlpha(50)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIcons.clockCountdown(PhosphorIconsStyle.fill),
                            size: 18,
                            color: _accentColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Confirmable dès ${booking.confirmationAvailableFormatted}',
                              style: TextStyle(
                                fontSize: 13,
                                color: _accentColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _scheduledAutoConfirms.contains(booking.orderId)
                            ? _buildActionButton(
                                label: 'Programmé',
                                icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                                color: _successColor,
                                onPressed: () => _scheduleAutoConfirm(booking),
                              )
                            : _buildActionButton(
                                label: 'Confirmer auto',
                                icon: PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                                color: _accentColor,
                                onPressed: () => _scheduleAutoConfirm(booking),
                              ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            label: 'Annuler',
                            icon: PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                            color: const Color(0xFFDC2626),
                            onPressed: () => _cancelBooking(booking),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Ready to confirm
                  if (booking.needsConfirmation) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: 'Confirmer',
                            icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                            color: _successColor,
                            onPressed: () => _confirmBooking(booking),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            label: 'Annuler',
                            icon: PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                            color: const Color(0xFFDC2626),
                            onPressed: () => _cancelBooking(booking),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],

                // Cancel only for confirmed bookings
                if (isUpcoming && booking.isConfirmed) ...[
                  const SizedBox(height: 16),
                  _buildActionButton(
                    label: 'Annuler',
                    icon: PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                    color: const Color(0xFFDC2626),
                    onPressed: () => _cancelBooking(booking),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: _isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(128)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le trajet'),
        content: Text(
          'Confirmer le trajet ${booking.origin.shortName} → ${booking.destination.shortName} du ${booking.formattedDate} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _successColor),
            child: const Text('Confirmer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final result = await SilentRefreshService().confirmBooking(booking);

      if (result.success) {
        // Update local status immediately
        final bookings = _store.bookings;
        final index = bookings.indexWhere((b) => b.orderId == booking.orderId);
        if (index != -1) {
          final updatedBooking = Booking(
            arrivalDateTime: booking.arrivalDateTime,
            departureDateTime: booking.departureDateTime,
            origin: booking.origin,
            destination: booking.destination,
            trainNumber: booking.trainNumber,
            coachNumber: booking.coachNumber,
            seatNumber: booking.seatNumber,
            dvNumber: booking.dvNumber,
            orderId: booking.orderId,
            serviceItemId: booking.serviceItemId,
            travelClass: booking.travelClass,
            travelStatus: booking.travelStatus,
            travelConfirmed: 'CONFIRMED', // Updated status
            reservationDate: booking.reservationDate,
            avantage: booking.avantage,
            marketingCarrierRef: booking.marketingCarrierRef,
          );
          bookings[index] = updatedBooking;
          await _store.updateBookings(bookings);
          setState(() {});
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Trajet confirme !'),
                ],
              ),
              backgroundColor: _successColor,
            ),
          );
        }
      } else if (result.needsReauth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Session expiree'),
              backgroundColor: _warningColor,
              action: SnackBarAction(
                label: 'Connexion',
                textColor: Colors.white,
                onPressed: _openLogin,
              ),
            ),
          );
        }
      } else {
        throw Exception(result.error ?? 'Erreur inconnue');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scheduleAutoConfirm(Booking booking) async {
    final isAlreadyScheduled = _scheduledAutoConfirms.contains(booking.orderId);

    if (isAlreadyScheduled) {
      // Unschedule
      _scheduledAutoConfirms.remove(booking.orderId);
      await _saveScheduledAutoConfirms();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(PhosphorIcons.bellSlash(PhosphorIconsStyle.fill), color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Expanded(child: Text('Confirmation auto annulee')),
              ],
            ),
            backgroundColor: _textSecondary,
          ),
        );
      }
    } else {
      // Schedule locally
      _scheduledAutoConfirms.add(booking.orderId);
      await _saveScheduledAutoConfirms();
      setState(() {});

      // Also try to schedule on backend (if connected via Puppeteer)
      final backendScheduled = await BackendApiService().scheduleAutoConfirm(booking);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(PhosphorIcons.bellRinging(PhosphorIconsStyle.fill), color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    backendScheduled
                        ? 'Confirmation auto programmee (serveur)'
                        : 'Confirmation auto programmee pour ${booking.confirmationAvailableFormatted}',
                  ),
                ),
              ],
            ),
            backgroundColor: backendScheduled ? _successColor : _accentColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler le trajet'),
        content: Text(
          'Voulez-vous vraiment annuler le trajet ${booking.origin.shortName} → ${booking.destination.shortName} du ${booking.formattedDate} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Oui, annuler', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final customerName = _store.userSession?.lastName ?? '';
      final result = await SilentRefreshService().cancelBooking(booking, customerName);

      if (result.success) {
        // Remove booking from local list immediately
        final bookings = _store.bookings;
        bookings.removeWhere((b) => b.orderId == booking.orderId);
        await _store.updateBookings(bookings);
        setState(() {});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Trajet annule !'),
                ],
              ),
              backgroundColor: _successColor,
            ),
          );
        }
      } else if (result.needsReauth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Session expiree'),
              backgroundColor: _warningColor,
              action: SnackBarAction(
                label: 'Connexion',
                textColor: Colors.white,
                onPressed: _openLogin,
              ),
            ),
          );
        }
      } else {
        throw Exception(result.error ?? 'Erreur inconnue');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSeatInfo(String label, String value, IconData icon, {bool muted = false}) {
    final labelColor = muted ? _textMuted.withOpacity(0.5) : _textMuted;
    final valueColor = muted ? _textMuted : _textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: muted ? _backgroundColor.withOpacity(0.5) : _backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: muted ? _borderColor.withOpacity(0.5) : _borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: labelColor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
