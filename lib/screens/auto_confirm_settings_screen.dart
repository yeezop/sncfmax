import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backend_api_service.dart';
import '../models/booking.dart';

/// Settings screen for backend-based auto-confirmation
/// This uses Puppeteer on the server to confirm bookings automatically
class AutoConfirmSettingsScreen extends StatefulWidget {
  const AutoConfirmSettingsScreen({super.key});

  @override
  State<AutoConfirmSettingsScreen> createState() => _AutoConfirmSettingsScreenState();
}

class _AutoConfirmSettingsScreenState extends State<AutoConfirmSettingsScreen> {
  final _api = BackendApiService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  String? _error;
  bool _rememberCredentials = true;

  PuppeteerStatus? _status;
  List<AutoConfirmSchedule> _schedule = [];
  bool _needs2FA = false;

  static const String _emailKey = 'sncf_email';
  static const String _passwordKey = 'sncf_password';

  // Colors
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _loadStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_emailKey);
    final savedPassword = prefs.getString(_passwordKey);

    if (savedEmail != null) {
      _emailController.text = savedEmail;
    }
    if (savedPassword != null) {
      _passwordController.text = savedPassword;
    }
  }

  Future<void> _saveCredentialsToPrefs() async {
    if (!_rememberCredentials) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, _emailController.text.trim());
    await prefs.setString(_passwordKey, _passwordController.text);
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);

    try {
      final status = await _api.getPuppeteerStatus();
      final schedule = await _api.getAutoConfirmSchedule();

      setState(() {
        _status = status;
        _schedule = schedule;
        _needs2FA = status.pending2FA;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = 'Email et mot de passe requis');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.puppeteerLogin(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result.success) {
        await _saveCredentialsToPrefs();
        await _loadStatus();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Connecte: ${result.session?.firstName ?? ""}'),
                ],
              ),
              backgroundColor: _successColor,
            ),
          );
        }
      } else if (result.needs2FA) {
        setState(() => _needs2FA = true);
      } else {
        setState(() => _error = result.error ?? 'Echec de la connexion');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit2FA() async {
    if (_codeController.text.isEmpty) {
      setState(() => _error = 'Code requis');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.puppeteerSubmit2FA(_codeController.text.trim());

      if (result.success) {
        _codeController.clear();
        setState(() => _needs2FA = false);
        await _saveCredentialsToPrefs();
        await _loadStatus();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Connecte: ${result.session?.firstName ?? ""}'),
                ],
              ),
              backgroundColor: _successColor,
            ),
          );
        }
      } else {
        setState(() => _error = result.error ?? 'Code invalide');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);

    try {
      await _api.puppeteerLogout();
      await _loadStatus();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelSchedule(String key) async {
    final success = await _api.cancelAutoConfirm(key);
    if (success) {
      await _loadStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular), color: _textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Confirmation Auto',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_status?.isAuthenticated == true)
            IconButton(
              icon: Icon(PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.regular), color: _textSecondary),
              onPressed: _isLoading ? null : _loadStatus,
            ),
        ],
      ),
      body: _isLoading && _status == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Info card
                  _buildInfoCard(),
                  const SizedBox(height: 20),

                  // Connection status / login form
                  if (_status?.isAuthenticated == true)
                    _buildConnectedCard()
                  else if (_needs2FA)
                    _build2FACard()
                  else
                    _buildLoginCard(),

                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _errorColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _errorColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), color: _errorColor, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: _errorColor, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Scheduled confirmations
                  if (_status?.isAuthenticated == true && _schedule.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildScheduleSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIcons.robot(PhosphorIconsStyle.fill), color: _accentColor, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Confirmation Automatique',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Cette fonctionnalite permet au serveur de confirmer automatiquement '
            'vos reservations TGV Max des que la fenetre de 48h s\'ouvre.\n\n'
            'Votre session reste active sur le serveur et verifie toutes les 5 minutes.',
            style: TextStyle(
              fontSize: 13,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
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
          const Text(
            'Connexion SNCF',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Connectez-vous pour activer l\'auto-confirmation',
            style: TextStyle(fontSize: 13, color: _textMuted),
          ),
          const SizedBox(height: 20),

          // Email
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(PhosphorIcons.envelope(PhosphorIconsStyle.regular), size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: _backgroundColor,
            ),
          ),
          const SizedBox(height: 16),

          // Password
          TextField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: Icon(PhosphorIcons.lock(PhosphorIconsStyle.regular), size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword
                      ? PhosphorIcons.eye(PhosphorIconsStyle.regular)
                      : PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                  size: 20,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: _backgroundColor,
            ),
          ),
          const SizedBox(height: 20),

          // Login button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Se connecter',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build2FACard() {
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
              Icon(PhosphorIcons.shieldCheck(PhosphorIconsStyle.fill), color: _warningColor, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Verification 2FA',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Entrez le code recu par SMS ou email',
            style: TextStyle(fontSize: 13, color: _textMuted),
          ),
          const SizedBox(height: 20),

          // Code input
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'Code de verification',
              prefixIcon: Icon(PhosphorIcons.keyhole(PhosphorIconsStyle.regular), size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: _backgroundColor,
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit2FA,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Valider',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _successColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: _successColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connecte',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _successColor,
                      ),
                    ),
                    if (_status?.session != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${_status!.session!.firstName ?? ""} ${_status!.session!.lastName ?? ""}',
                        style: const TextStyle(fontSize: 13, color: _textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Reservations',
                  '${_status?.bookingsCount ?? 0}',
                  PhosphorIcons.ticket(PhosphorIconsStyle.fill),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Auto-confirm',
                  '${_schedule.where((s) => s.status == "pending").length}',
                  PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isLoading ? null : _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: _errorColor,
                side: BorderSide(color: _errorColor.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.signOut(PhosphorIconsStyle.regular), size: 18),
                  const SizedBox(width: 8),
                  const Text('Deconnexion', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _accentColor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: _textMuted)),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confirmations programmees',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._schedule.map((s) => _buildScheduleCard(s)),
      ],
    );
  }

  Widget _buildScheduleCard(AutoConfirmSchedule schedule) {
    Color statusColor;
    IconData statusIcon;

    switch (schedule.status) {
      case 'confirmed':
        statusColor = _successColor;
        statusIcon = PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
        break;
      case 'failed':
      case 'needs_reauth':
        statusColor = _errorColor;
        statusIcon = PhosphorIcons.xCircle(PhosphorIconsStyle.fill);
        break;
      case 'confirming':
        statusColor = _warningColor;
        statusIcon = PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.fill);
        break;
      default:
        statusColor = _accentColor;
        statusIcon = PhosphorIcons.clock(PhosphorIconsStyle.fill);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Train ${schedule.trainNumber}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${schedule.origin ?? "?"} -> ${schedule.destination ?? "?"}',
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    schedule.statusLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          if (schedule.status == 'pending')
            IconButton(
              icon: Icon(PhosphorIcons.xCircle(PhosphorIconsStyle.regular), color: _textMuted, size: 20),
              onPressed: () => _cancelSchedule(schedule.key),
              tooltip: 'Annuler',
            ),
        ],
      ),
    );
  }
}
