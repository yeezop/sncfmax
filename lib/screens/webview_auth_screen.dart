import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../services/cookie_manager.dart';

class WebViewAuthScreen extends StatefulWidget {
  const WebViewAuthScreen({super.key});

  @override
  State<WebViewAuthScreen> createState() => _WebViewAuthScreenState();
}

class _WebViewAuthScreenState extends State<WebViewAuthScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _loadAttempts = 0;

  static const String _targetUrl = 'https://www.maxjeune-tgvinoui.sncf/recherche';

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF64748B);
  static const Color _successColor = Color(0xFF166534);

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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[WebView] Page started: $url');
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            debugPrint('[WebView] Page finished: $url');
            setState(() => _isLoading = false);

            _loadAttempts++;

            if (url.contains('maxjeune-tgvinoui.sncf') &&
                !url.contains('captcha-delivery.com')) {
              await _extractCookies();
            }
          },
          onWebResourceError: (error) {
            debugPrint('[WebView] Error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  Future<void> _extractCookies() async {
    try {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      ) as String;

      debugPrint('[WebView] Raw cookies: $cookies');

      if (cookies.isNotEmpty && cookies != '""') {
        final cleanCookies = cookies.replaceAll('"', '');
        final cookieList = cleanCookies.split('; ').map((c) => c.trim()).toList();

        CookieManager().setCookies(cookieList);

        if (CookieManager().hasDataDomeCookie()) {
          debugPrint('[WebView] DataDome cookie found! Session ready.');
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
                    const Text('Session initialisee avec succes'),
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
        }
      }
    } catch (e) {
      debugPrint('[WebView] Error extracting cookies: $e');
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
            if (_isLoading)
              const LinearProgressIndicator(
                backgroundColor: _borderColor,
                color: _accentColor,
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
              onPressed: () => Navigator.of(context).pop(),
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
                      PhosphorIcons.shieldCheck(PhosphorIconsStyle.fill),
                      size: 18,
                      color: _textPrimary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Initialisation',
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
                const Text(
                  'Connexion au service SNCF',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_loadAttempts > 2)
            Container(
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await _extractCookies();
                  if (mounted && CookieManager().isInitialized) {
                    navigator.pop(true);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Continuer',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                      size: 16,
                      color: Colors.white,
                    ),
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
                      PhosphorIcons.globe(PhosphorIconsStyle.regular),
                      size: 14,
                      color: _textSecondary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Chargement de la page SNCF',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.robot(PhosphorIconsStyle.regular),
                      size: 12,
                      color: _textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Si un captcha apparait, resolvez-le pour continuer.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
