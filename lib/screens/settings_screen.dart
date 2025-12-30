import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/font_service.dart';
import '../services/backend_api_service.dart';
import '../models/booking.dart';
import '../models/sncf_connect_session.dart';
import 'font_picker_screen.dart';
import 'sncf_booking_webview_screen.dart';
import '../models/train_proposal.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FontService _fontService = FontService();
  final BookingsStore _bookingsStore = BookingsStore();
  final BackendApiService _backendApi = BackendApiService();
  final SncfConnectStore _sncfConnectStore = SncfConnectStore();

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _fontService.addListener(_onFontChanged);
    _loadSncfConnectSession();
  }

  Future<void> _loadSncfConnectSession() async {
    await _sncfConnectStore.loadSession();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fontService.removeListener(_onFontChanged);
    super.dispose();
  }

  void _onFontChanged() {
    setState(() {});
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deconnexion'),
        content: const Text('Voulez-vous vraiment vous deconnecter de TGV Max ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deconnecter'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _bookingsStore.clear();
      _backendApi.logout();
      setState(() {});
    }
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _buildSectionTitle('Compte TGV Max', PhosphorIcons.train(PhosphorIconsStyle.fill)),
                  const SizedBox(height: 12),
                  _buildAccountSection(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('SNCF Connect', PhosphorIcons.ticket(PhosphorIconsStyle.fill)),
                  const SizedBox(height: 12),
                  _buildSncfConnectSection(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Apparence', PhosphorIcons.paintBrush(PhosphorIconsStyle.fill)),
                  const SizedBox(height: 12),
                  _buildFontSelector(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('A propos', PhosphorIcons.info(PhosphorIconsStyle.fill)),
                  const SizedBox(height: 12),
                  _buildAboutSection(),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.gear(PhosphorIconsStyle.fill),
            size: 24,
            color: _textPrimary,
          ),
          const SizedBox(width: 10),
          const Text(
            'Reglages',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
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

  Widget _buildAccountSection() {
    final isAuthenticated = _bookingsStore.isAuthenticated;
    final session = _bookingsStore.userSession;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          // TGV Max status
          _buildStatusRow(
            PhosphorIcons.train(PhosphorIconsStyle.fill),
            'TGV Max',
            isAuthenticated ? 'Connecte' : 'Non connecte',
            isAuthenticated ? const Color(0xFF10B981) : _textMuted,
          ),
          if (isAuthenticated && session != null) ...[
            const Divider(height: 24, color: _borderColor),
            _buildAboutRow(
              PhosphorIcons.identificationCard(PhosphorIconsStyle.fill),
              'Nom',
              session.displayName,
            ),
            if (session.cardNumber != null) ...[
              const Divider(height: 24, color: _borderColor),
              _buildAboutRow(
                PhosphorIcons.creditCard(PhosphorIconsStyle.fill),
                'Carte TGV Max',
                _formatCardNumber(session.cardNumber!),
              ),
            ],
            const Divider(height: 24, color: _borderColor),
            _buildLogoutButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(IconData icon, String label, String status, Color statusColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: _textSecondary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _logout,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              PhosphorIcons.signOut(PhosphorIconsStyle.fill),
              size: 16,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Se deconnecter de TGV Max',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
            size: 16,
            color: Colors.red.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  String _formatCardNumber(String cardNumber) {
    if (cardNumber.length <= 4) return cardNumber;
    return '•••• ${cardNumber.substring(cardNumber.length - 4)}';
  }

  Widget _buildSncfConnectSection() {
    final isAuthenticated = _sncfConnectStore.isAuthenticated;
    final session = _sncfConnectStore.session;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          // SNCF Connect status
          _buildStatusRow(
            PhosphorIcons.ticket(PhosphorIconsStyle.fill),
            'Reservations',
            isAuthenticated ? 'Connecte' : 'Non connecte',
            isAuthenticated ? const Color(0xFF10B981) : _textMuted,
          ),
          if (isAuthenticated && session != null) ...[
            if (session.displayName != null) ...[
              const Divider(height: 24, color: _borderColor),
              _buildAboutRow(
                PhosphorIcons.user(PhosphorIconsStyle.fill),
                'Compte',
                session.displayName!,
              ),
            ],
            if (session.email != null && session.email!.isNotEmpty) ...[
              const Divider(height: 24, color: _borderColor),
              _buildAboutRow(
                PhosphorIcons.envelope(PhosphorIconsStyle.fill),
                'Email',
                session.email!,
              ),
            ],
            if (session.authenticatedAt != null) ...[
              const Divider(height: 24, color: _borderColor),
              _buildAboutRow(
                PhosphorIcons.clock(PhosphorIconsStyle.fill),
                'Connecte le',
                _formatDate(session.authenticatedAt!),
              ),
            ],
            const Divider(height: 24, color: _borderColor),
            _buildSncfConnectLogoutButton(),
          ] else ...[
            const Divider(height: 24, color: _borderColor),
            _buildSncfConnectLoginButton(),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) {
      return 'Il y a ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      return 'Il y a ${diff.inHours}h';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildSncfConnectLoginButton() {
    return GestureDetector(
      onTap: _loginSncfConnect,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              PhosphorIcons.signIn(PhosphorIconsStyle.fill),
              size: 16,
              color: const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Se connecter pour reserver',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
            size: 16,
            color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSncfConnectLogoutButton() {
    return GestureDetector(
      onTap: _logoutSncfConnect,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              PhosphorIcons.signOut(PhosphorIconsStyle.fill),
              size: 16,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Se deconnecter de SNCF Connect',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
            size: 16,
            color: Colors.red.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Future<void> _loginSncfConnect() async {
    // Create a dummy train for navigation - user will search on SNCF Connect
    final now = DateTime.now();
    final dummyTrain = TrainProposal(
      trainNumber: '',
      trainType: 'TGV',
      departureTime: now.toIso8601String(),
      arrivalTime: now.toIso8601String(),
      origin: '',
      destination: '',
      availableSeats: 0,
    );

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SncfBookingWebviewScreen(
          train: dummyTrain,
          originCode: '',
          originName: '',
          destinationCode: '',
          destinationName: '',
          date: now,
        ),
      ),
    );

    if (result == true) {
      await _loadSncfConnectSession();
    }
  }

  Future<void> _logoutSncfConnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deconnexion SNCF Connect'),
        content: const Text('Voulez-vous vraiment vous deconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deconnecter'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sncfConnectStore.clearSession();
      setState(() {});
    }
  }

  Widget _buildFontSelector() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FontPickerScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _backgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                PhosphorIcons.textAa(PhosphorIconsStyle.duotone),
                size: 20,
                color: _textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Police de caracteres',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fontService.currentFont,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
              size: 18,
              color: _textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildAboutRow(
            PhosphorIcons.appWindow(PhosphorIconsStyle.fill),
            'Version',
            '1.0.0',
          ),
          const Divider(height: 24, color: _borderColor),
          _buildAboutRow(
            PhosphorIcons.code(PhosphorIconsStyle.fill),
            'Developpe avec',
            'Flutter',
          ),
          const Divider(height: 24, color: _borderColor),
          _buildAboutRow(
            PhosphorIcons.textAa(PhosphorIconsStyle.fill),
            'Fonts',
            'Google Fonts',
          ),
        ],
      ),
    );
  }

  Widget _buildAboutRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: _textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }
}
