import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/booking.dart';
import '../services/backend_api_service.dart';

class SncfLoginScreen extends StatefulWidget {
  const SncfLoginScreen({super.key});

  @override
  State<SncfLoginScreen> createState() => _SncfLoginScreenState();
}

class _SncfLoginScreenState extends State<SncfLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isCheckingAuth = false;
  String? _currentUrl;

  // Completer for async JS communication
  Completer<String>? _jsCompleter;

  static const String _loginUrl = 'https://www.maxjeune-tgvinoui.sncf/sncf-connect/mes-voyages';

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _successColor = Color(0xFF22C55E);

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('[SncfLogin] JS Channel received: ${message.message.substring(0, message.message.length > 100 ? 100 : message.message.length)}...');
          if (_jsCompleter != null && !_jsCompleter!.isCompleted) {
            _jsCompleter!.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[SncfLogin] Page started: $url');
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) async {
            debugPrint('[SncfLogin] Page finished: $url');
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });

            // Auto-validate when user reaches mes-voyages (logged in)
            if (url.contains('mes-voyages') && !_isCheckingAuth) {
              debugPrint('[SncfLogin] Detected mes-voyages, auto-validating...');
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted && !_isCheckingAuth) {
                _checkAndSyncAuth();
              }
            }
          },
          onWebResourceError: (error) {
            debugPrint('[SncfLogin] WebResource Error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
  }

  Future<String> _runJsAsync(String jsCode) async {
    _jsCompleter = Completer<String>();

    final wrappedJs = '''
      (async function() {
        try {
          $jsCode
        } catch(e) {
          FlutterChannel.postMessage(JSON.stringify({error: e.toString()}));
        }
      })();
    ''';

    debugPrint('[SncfLogin] Executing JS...');
    await _controller.runJavaScript(wrappedJs);

    return _jsCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => '{"error": "Timeout"}',
    );
  }

  Future<void> _checkAndSyncAuth() async {
    if (_isCheckingAuth) return;

    setState(() => _isCheckingAuth = true);

    try {
      debugPrint('[SncfLogin] Step 1: Fetching customer data...');

      // Step 1: Get customer info
      final customerResult = await _runJsAsync('''
        const resp = await fetch("https://www.maxjeune-tgvinoui.sncf/api/public/customer/read-customer", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "x-client-app": "MAX_JEUNE"
          },
          body: JSON.stringify({productTypes: ["TGV_MAX_JEUNE", "FIDEL", "IDTGV_MAX"]})
        });
        const data = await resp.json();
        FlutterChannel.postMessage(JSON.stringify(data));
      ''');

      debugPrint('[SncfLogin] Customer result: ${customerResult.substring(0, customerResult.length > 200 ? 200 : customerResult.length)}');

      final customer = json.decode(customerResult);

      if (customer['error'] != null) {
        throw Exception('Erreur: ${customer['error']}');
      }

      if (customer['cards'] == null) {
        throw Exception('Non connecte - pas de carte trouvee');
      }

      final cards = customer['cards'] as List;
      final card = cards.firstWhere(
        (c) => c['productType'] == 'TGV_MAX_JEUNE',
        orElse: () => null,
      );

      if (card == null) {
        throw Exception('Pas de carte TGV Max trouvee');
      }

      final cardNumber = card['cardNumber'] as String;
      debugPrint('[SncfLogin] Step 2: Card found: $cardNumber, fetching bookings...');

      // Step 2: Get bookings
      final startDate = DateTime.now().subtract(const Duration(days: 90));
      final startDateStr = startDate.toIso8601String();

      final bookingsResult = await _runJsAsync('''
        const resp = await fetch("https://www.maxjeune-tgvinoui.sncf/api/public/reservation/travel-consultation", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "x-client-app": "MAX_JEUNE",
            "x-distribution-channel": "OUI"
          },
          body: JSON.stringify({cardNumber: "$cardNumber", startDate: "$startDateStr"})
        });
        const data = await resp.json();
        FlutterChannel.postMessage(JSON.stringify(data));
      ''');

      debugPrint('[SncfLogin] Bookings result length: ${bookingsResult.length}');

      final bookings = json.decode(bookingsResult);
      final bookingsList = bookings is List ? bookings : [];

      debugPrint('[SncfLogin] Step 3: Found ${bookingsList.length} bookings, storing locally...');

      // Step 3: Store locally
      final session = UserSession(
        isAuthenticated: true,
        cardNumber: cardNumber,
        firstName: customer['firstName'],
        lastName: customer['lastName'],
        email: customer['email'],
      );

      final bookingObjects = bookingsList
          .map((b) => Booking.fromJson(b as Map<String, dynamic>))
          .toList();

      await BookingsStore().storeSession(session, bookingObjects);

      debugPrint('[SncfLogin] Stored ${bookingObjects.length} bookings locally');

      // Step 4: Store session on backend for refresh capability
      debugPrint('[SncfLogin] Step 4: Storing session on backend...');
      try {
        await BackendApiService().storeSession(
          cardNumber: cardNumber,
          firstName: customer['firstName'] ?? '',
          lastName: customer['lastName'] ?? '',
          email: customer['email'],
          bookings: bookingsList.cast<Map<String, dynamic>>(),
        );
        debugPrint('[SncfLogin] Session stored on backend successfully');
      } catch (e) {
        // Non-blocking - we still have local data
        debugPrint('[SncfLogin] Warning: Failed to store session on backend: $e');
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
                Text('${customer['firstName']} - ${bookingsList.length} reservations'),
              ],
            ),
            backgroundColor: _successColor,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      debugPrint('[SncfLogin] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingAuth = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_isLoading || _isCheckingAuth)
              LinearProgressIndicator(
                backgroundColor: _borderColor,
                color: _isCheckingAuth ? _successColor : _accentColor,
                minHeight: 2,
              ),
            _buildInfoBanner(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
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
              onPressed: () => Navigator.of(context).pop(false),
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
                      PhosphorIcons.signIn(PhosphorIconsStyle.fill),
                      size: 18,
                      color: _textPrimary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Connexion SNCF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _currentUrl?.contains('login') == true
                      ? 'Entrez vos identifiants'
                      : 'Connectez-vous a votre compte',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _accentColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: _isCheckingAuth ? null : _checkAndSyncAuth,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isCheckingAuth)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else ...[
                    const Text(
                      'Valider',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      PhosphorIcons.check(PhosphorIconsStyle.bold),
                      size: 16,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
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
              PhosphorIcons.info(PhosphorIconsStyle.duotone),
              size: 20,
              color: _textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.userCircle(PhosphorIconsStyle.regular),
                      size: 14,
                      color: _textSecondary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Connexion securisee',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Connectez-vous avec vos identifiants SNCF Connect pour voir vos reservations.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
