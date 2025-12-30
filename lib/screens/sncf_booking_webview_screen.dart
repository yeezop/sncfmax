import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/train_proposal.dart';
import '../models/sncf_connect_session.dart';

class SncfBookingWebviewScreen extends StatefulWidget {
  final TrainProposal train;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final DateTime date;

  const SncfBookingWebviewScreen({
    super.key,
    required this.train,
    required this.originCode,
    required this.originName,
    required this.destinationCode,
    required this.destinationName,
    required this.date,
  });

  @override
  State<SncfBookingWebviewScreen> createState() => _SncfBookingWebviewScreenState();
}

class _SncfBookingWebviewScreenState extends State<SncfBookingWebviewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isBookingComplete = false;
  bool _isCheckingAuth = false;
  bool _isAuthenticated = false;
  Completer<String>? _jsCompleter;

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
    _checkExistingSession();
    _initWebView();
  }

  Future<void> _checkExistingSession() async {
    await SncfConnectStore().loadSession();
    if (mounted) {
      setState(() {
        _isAuthenticated = SncfConnectStore().isAuthenticated;
      });
    }
  }

  String _buildSearchUrl() {
    // Load SNCF Connect homepage - user will fill in the search
    // We display the search info in the banner above
    return 'https://www.sncf-connect.com/';
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

    await _controller.runJavaScript(wrappedJs);

    return _jsCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => '{"error": "Timeout"}',
    );
  }

  Future<void> _checkAndSaveSession() async {
    if (_isCheckingAuth) return;

    setState(() => _isCheckingAuth = true);

    try {
      debugPrint('[SncfBooking] Checking authentication...');

      // Try to get user info from SNCF Connect via API call
      final result = await _runJsAsync('''
        // Method 1: Try fetching user info from SNCF Connect API (multiple endpoints)
        const apiEndpoints = [
          { url: "https://www.sncf-connect.com/bff/api/v1/user", headers: {"x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876"} },
          { url: "https://www.sncf-connect.com/bff/api/v1/account", headers: {"x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876"} },
          { url: "https://www.sncf-connect.com/api/front/account/profile", headers: {} }
        ];

        for (const endpoint of apiEndpoints) {
          try {
            const resp = await fetch(endpoint.url, {
              method: "GET",
              credentials: "include",
              headers: {
                "Accept": "application/json",
                ...endpoint.headers
              }
            });
            if (resp.ok) {
              const user = await resp.json();
              console.log("API response from " + endpoint.url + ":", JSON.stringify(user).substring(0, 200));
              const firstName = user.firstName || user.givenName || user.prenom || '';
              const lastName = user.lastName || user.familyName || user.nom || '';
              const email = user.email || user.mail || '';
              if (firstName || lastName || email || user.id) {
                FlutterChannel.postMessage(JSON.stringify({
                  authenticated: true,
                  complete: true,
                  firstName: firstName,
                  lastName: lastName,
                  email: email,
                  visitorId: user.id || user.visitorId || ''
                }));
                return;
              }
            }
          } catch(e) {
            console.log("API " + endpoint.url + " failed:", e);
          }
        }

        // Method 2: Check __NEXT_DATA__ for user info
        const userDataScript = document.querySelector('script[id="__NEXT_DATA__"]');
        if (userDataScript) {
          try {
            const data = JSON.parse(userDataScript.textContent);
            const searchPaths = [
              data?.props?.pageProps?.user,
              data?.props?.pageProps?.initialProps?.user,
              data?.props?.initialState?.user?.data,
              data?.props?.pageProps?.session?.user,
              data?.props?.pageProps?.account,
              data?.props?.user
            ];
            for (const user of searchPaths) {
              if (user && (user.firstName || user.email || user.prenom)) {
                FlutterChannel.postMessage(JSON.stringify({
                  authenticated: true,
                  complete: true,
                  firstName: user.firstName || user.prenom || '',
                  lastName: user.lastName || user.nom || '',
                  email: user.email || '',
                  visitorId: user.visitorId || user.id || ''
                }));
                return;
              }
            }
          } catch(e) {
            console.log("__NEXT_DATA__ parse error:", e);
          }
        }

        // Method 3: Check for logged-in indicators in DOM and extract info
        const loggedInIndicators = [
          '[data-testid="header-account-button"]',
          '[data-testid="user-menu"]',
          '[data-testid="account-menu"]',
          '.header-account',
          '.user-logged',
          'button[aria-label*="compte"]',
          'button[aria-label*="Compte"]',
          'a[href*="/account"]',
          '[class*="UserMenu"]',
          '[class*="AccountMenu"]',
          '[class*="logged"]'
        ];

        for (const selector of loggedInIndicators) {
          const el = document.querySelector(selector);
          if (el) {
            console.log("Found logged-in indicator:", selector);
            const text = (el.textContent || el.innerText || '').trim();

            // Extract initials from button text like "ADCompte" -> "AD"
            let initials = '';
            const match = text.match(/^([A-Z]{1,3})/);
            if (match) {
              initials = match[1];
            }

            FlutterChannel.postMessage(JSON.stringify({
              authenticated: true,
              partial: true,
              foundSelector: selector,
              elementText: text.substring(0, 100),
              initials: initials
            }));
            return;
          }
        }

        // Method 4: Check cookies for auth indicators
        const cookies = document.cookie;
        const hasAuthCookie = cookies.includes('access_token') ||
                             cookies.includes('refresh_token') ||
                             cookies.includes('logged') ||
                             cookies.includes('session') ||
                             cookies.includes('sncf_') ||
                             cookies.includes('connect_');

        if (hasAuthCookie) {
          console.log("Found auth cookies");
          FlutterChannel.postMessage(JSON.stringify({
            authenticated: true,
            partial: true,
            source: 'cookies'
          }));
          return;
        }

        // Debug: log what we found
        console.log("No auth indicators found. Page title:", document.title);
        FlutterChannel.postMessage(JSON.stringify({authenticated: false, debug: document.title}));
      ''');

      debugPrint('[SncfBooking] Auth check result: $result');

      final data = json.decode(result);

      if (data['authenticated'] == true) {
        // Extract firstName from initials if available
        String? firstName = data['firstName'];
        String? lastName = data['lastName'];

        // If we only have initials, use them as display hint
        if ((firstName == null || firstName.isEmpty) && data['initials'] != null) {
          firstName = data['initials'];
        }

        final session = SncfConnectSession(
          isAuthenticated: true,
          firstName: firstName,
          lastName: lastName,
          email: data['email'],
          visitorId: data['visitorId'],
          authenticatedAt: DateTime.now(),
        );

        await SncfConnectStore().storeSession(session);

        if (mounted) {
          setState(() => _isAuthenticated = true);

          final displayText = session.displayName ??
              (data['initials'] != null ? data['initials'] : 'OK');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                      color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('Connecte: $displayText'),
                ],
              ),
              backgroundColor: const Color(0xFF22C55E),
              duration: const Duration(seconds: 2),
            ),
          );

          // Auto-close if we got complete auth or user has been authenticated
          if (data['complete'] == true || data['partial'] == true) {
            debugPrint('[SncfBooking] Authentication confirmed, closing page...');
            await Future.delayed(const Duration(milliseconds: 1500));
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SncfBooking] Auth check error: $e');
    } finally {
      if (mounted) {
        setState(() => _isCheckingAuth = false);
      }
    }
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
          debugPrint('[SncfBooking] JS Channel received: ${message.message.substring(0, message.message.length > 100 ? 100 : message.message.length)}...');
          if (_jsCompleter != null && !_jsCompleter!.isCompleted) {
            _jsCompleter!.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            debugPrint('[SncfBooking] Navigation request: $url');

            // Block about: URLs (popups, iframes)
            if (url.startsWith('about:')) {
              debugPrint('[SncfBooking] Blocking about: URL');
              return NavigationDecision.prevent;
            }

            // Block tracking/analytics URLs
            if (url.contains('doubleclick.net') ||
                url.contains('weborama.') ||
                url.contains('facebook.com') ||
                url.contains('google-analytics') ||
                url.contains('googletagmanager') ||
                url.contains('datadoghq') ||
                url.contains('criteo.') ||
                url.contains('adsrvr.org')) {
              debugPrint('[SncfBooking] Blocking tracking URL');
              return NavigationDecision.prevent;
            }

            // Only allow SNCF domains and required services
            final uri = Uri.tryParse(url);
            if (uri != null && uri.host.isNotEmpty) {
              final host = uri.host.toLowerCase();
              // Allow SNCF domains
              if (host.contains('sncf') ||
                  host.contains('oui.') ||
                  host.contains('voyages-sncf') ||
                  host.contains('monidentifiant.')) {
                return NavigationDecision.navigate;
              }
              // Allow DataDome captcha (required for anti-bot)
              if (host.contains('captcha-delivery.com') ||
                  host.contains('datadome.')) {
                return NavigationDecision.navigate;
              }
              debugPrint('[SncfBooking] Blocking non-SNCF domain: $host');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            debugPrint('[SncfBooking] Page started: $url');
            // Only update loading state for SNCF pages
            if (url.contains('sncf') || url.contains('monidentifiant')) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (url) async {
            debugPrint('[SncfBooking] Page finished: $url');

            // Only process SNCF pages
            if (!url.contains('sncf') && !url.contains('monidentifiant')) {
              return;
            }

            setState(() {
              _isLoading = false;
            });

            // Inject JavaScript to handle popups - redirect window.open to same window
            await _controller.runJavaScript('''
              // Override window.open to navigate in same window
              window.open = function(url, target, features) {
                if (url) {
                  window.location.href = url;
                }
                return window;
              };

              // Convert target="_blank" links to same window
              document.querySelectorAll('a[target="_blank"]').forEach(function(link) {
                link.removeAttribute('target');
              });

              // Handle dynamically added links
              const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                  mutation.addedNodes.forEach(function(node) {
                    if (node.nodeType === 1) {
                      if (node.tagName === 'A' && node.target === '_blank') {
                        node.removeAttribute('target');
                      }
                      node.querySelectorAll && node.querySelectorAll('a[target="_blank"]').forEach(function(link) {
                        link.removeAttribute('target');
                      });
                    }
                  });
                });
              });
              observer.observe(document.body, { childList: true, subtree: true });
            ''');

            // Check if we reached the confirmation page
            if (url.contains('/confirmation') || url.contains('/order-confirmation') || url.contains('/finalization')) {
              setState(() {
                _isBookingComplete = true;
              });
            }

            // Detect OAuth callback - wait for redirect to complete
            if (url.contains('/authenticate?code=') || url.contains('&code=')) {
              debugPrint('[SncfBooking] OAuth callback detected, waiting for redirect...');
              // Don't check auth yet, wait for next page load
              return;
            }

            // Check for authentication after landing on main SNCF pages (after OAuth redirect)
            if ((url.contains('sncf-connect.com') || url.contains('oui.sncf')) &&
                !url.contains('login') &&
                !url.contains('monidentifiant') &&
                !url.contains('/authenticate') &&
                !_isAuthenticated) {
              // Delay to let page fully load and session to be established
              await Future.delayed(const Duration(milliseconds: 2000));
              if (mounted && !_isAuthenticated) {
                await _checkAndSaveSession();
              }
            }
          },
          onWebResourceError: (error) {
            debugPrint('[SncfBooking] WebResource Error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_buildSearchUrl()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_isLoading)
              LinearProgressIndicator(
                backgroundColor: _borderColor,
                color: _isBookingComplete ? _successColor : _accentColor,
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
              onPressed: () => Navigator.of(context).pop(_isBookingComplete),
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
                      _isBookingComplete
                        ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                        : PhosphorIcons.ticket(PhosphorIconsStyle.fill),
                      size: 18,
                      color: _isBookingComplete ? _successColor : _textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isBookingComplete ? 'Reservation confirmee' : 'Reservation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _isBookingComplete ? _successColor : _textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.train.trainType} ${widget.train.trainNumber} - ${widget.train.formattedDeparture}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_isBookingComplete)
            Container(
              decoration: BoxDecoration(
                color: _successColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Termine',
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
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: _isAuthenticated ? _successColor : _accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton(
                onPressed: _isCheckingAuth ? null : _checkAndSaveSession,
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
                      Text(
                        _isAuthenticated ? 'Connecte' : 'Valider',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _isAuthenticated
                            ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                            : PhosphorIcons.check(PhosphorIconsStyle.bold),
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

  String _formatDate() {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = ['jan', 'fev', 'mar', 'avr', 'mai', 'juin', 'juil', 'aout', 'sep', 'oct', 'nov', 'dec'];
    return '${days[widget.date.weekday - 1]} ${widget.date.day} ${months[widget.date.month - 1]}';
  }

  Widget _buildInfoBanner() {
    if (_isBookingComplete) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _successColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _successColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _successColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                size: 20,
                color: _successColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reservation reussie!',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _successColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Votre billet TGV Max a ete reserve. Consultez vos emails.',
                    style: TextStyle(
                      fontSize: 12,
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                size: 16,
                color: _accentColor,
              ),
              const SizedBox(width: 8),
              const Text(
                'Recherchez ce trajet:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.fill), size: 14, color: _textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.originName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold), size: 14, color: _textMuted),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.fill), size: 14, color: _textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.destinationName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.calendar(PhosphorIconsStyle.fill), size: 14, color: _textMuted),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.train(PhosphorIconsStyle.fill), size: 14, color: _accentColor),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.train.trainNumber} - ${widget.train.formattedDeparture}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentColor),
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
}
