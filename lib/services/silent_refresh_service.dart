import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/booking.dart';

/// Service to refresh bookings silently using WebView cookies
class SilentRefreshService {
  static final SilentRefreshService _instance = SilentRefreshService._internal();
  factory SilentRefreshService() => _instance;
  SilentRefreshService._internal();

  Completer<String>? _jsCompleter;

  /// Refresh bookings using stored WebView cookies (no UI)
  Future<SilentRefreshResult> refreshBookings() async {
    final cardNumber = BookingsStore().cardNumber;
    if (cardNumber == null) {
      return SilentRefreshResult(success: false, error: 'No card number stored');
    }

    debugPrint('[SilentRefresh] Starting silent refresh for card: $cardNumber');

    try {
      final controller = await _createWebViewController();
      await _loadInitialPage(controller);

      // Fetch bookings
      debugPrint('[SilentRefresh] Fetching bookings...');
      final startDate = DateTime.now().subtract(const Duration(days: 90));
      final startDateStr = startDate.toIso8601String();

      final bookingsResult = await _runJsAsync(controller, '''
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
        if (resp.status === 401 || resp.status === 403) {
          FlutterChannel.postMessage(JSON.stringify({error: "auth_expired"}));
        } else {
          const data = await resp.json();
          FlutterChannel.postMessage(JSON.stringify(data));
        }
      ''');

      debugPrint('[SilentRefresh] Result length: ${bookingsResult.length}');

      final decoded = json.decode(bookingsResult);

      if (decoded is Map && decoded['error'] == 'auth_expired') {
        debugPrint('[SilentRefresh] Session expired');
        return SilentRefreshResult(success: false, needsReauth: true, error: 'Session expired');
      }

      final bookingsList = decoded is List ? decoded : [];
      final bookings = bookingsList
          .map((b) => Booking.fromJson(b as Map<String, dynamic>))
          .toList();

      debugPrint('[SilentRefresh] Got ${bookings.length} bookings');

      return SilentRefreshResult(
        success: true,
        bookings: bookings,
        bookingsRaw: bookingsList.cast<Map<String, dynamic>>(),
      );

    } catch (e) {
      debugPrint('[SilentRefresh] Error: $e');
      return SilentRefreshResult(success: false, error: e.toString());
    }
  }

  /// Cancel a booking
  Future<ActionResult> cancelBooking(Booking booking, String customerName) async {
    debugPrint('[SilentRefresh] Cancelling booking: ${booking.trainNumber}');

    try {
      final controller = await _createWebViewController();
      await _loadInitialPage(controller);

      // Note: marketingCarrierRef = dvNumber in booking data
      final result = await _runJsAsync(controller, '''
        const resp = await fetch("https://www.maxjeune-tgvinoui.sncf/api/public/reservation/cancel-reservation", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "x-client-app": "MAX_JEUNE",
            "x-distribution-channel": "OUI"
          },
          body: JSON.stringify({
            travelsInfo: [{
              marketingCarrierRef: "${booking.dvNumber}",
              orderId: "${booking.orderId}",
              customerName: "$customerName",
              trainNumber: "${booking.trainNumber}",
              departureDateTime: "${booking.departureDateTime}"
            }]
          })
        });
        if (resp.status === 401 || resp.status === 403) {
          FlutterChannel.postMessage(JSON.stringify({error: "auth_expired"}));
        } else {
          const data = await resp.json();
          FlutterChannel.postMessage(JSON.stringify(data));
        }
      ''');

      debugPrint('[SilentRefresh] Cancel result: $result');

      final decoded = json.decode(result);

      if (decoded is Map && decoded['error'] == 'auth_expired') {
        return ActionResult(success: false, needsReauth: true, error: 'Session expirée');
      }

      // Check if cancelled successfully
      if (decoded is Map && decoded['info'] is List) {
        final info = decoded['info'] as List;
        if (info.isNotEmpty && info[0]['cancelled'] == true) {
          return ActionResult(success: true);
        }
      }

      return ActionResult(success: false, error: 'Échec de l\'annulation');

    } catch (e) {
      debugPrint('[SilentRefresh] Cancel error: $e');
      return ActionResult(success: false, error: e.toString());
    }
  }

  /// Confirm a booking
  Future<ActionResult> confirmBooking(Booking booking) async {
    debugPrint('[SilentRefresh] Confirming booking: ${booking.trainNumber}');

    try {
      final controller = await _createWebViewController();
      await _loadInitialPage(controller);

      // Note: marketingCarrierRef = dvNumber in booking data
      final result = await _runJsAsync(controller, '''
        const resp = await fetch("https://www.maxjeune-tgvinoui.sncf/api/public/reservation/travel-confirm", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "x-client-app": "MAX_JEUNE",
            "x-distribution-channel": "OUI"
          },
          body: JSON.stringify({
            marketingCarrierRef: "${booking.dvNumber}",
            trainNumber: "${booking.trainNumber}",
            departureDateTime: "${booking.departureDateTime}"
          })
        });
        if (resp.status === 401 || resp.status === 403) {
          FlutterChannel.postMessage(JSON.stringify({error: "auth_expired"}));
        } else if (resp.status === 204) {
          FlutterChannel.postMessage(JSON.stringify({success: true}));
        } else {
          const data = await resp.text();
          FlutterChannel.postMessage(JSON.stringify({error: data || "Unknown error"}));
        }
      ''');

      debugPrint('[SilentRefresh] Confirm result: $result');

      final decoded = json.decode(result);

      if (decoded is Map && decoded['error'] == 'auth_expired') {
        return ActionResult(success: false, needsReauth: true, error: 'Session expirée');
      }

      if (decoded is Map && decoded['success'] == true) {
        return ActionResult(success: true);
      }

      return ActionResult(success: false, error: decoded['error']?.toString() ?? 'Échec de la confirmation');

    } catch (e) {
      debugPrint('[SilentRefresh] Confirm error: $e');
      return ActionResult(success: false, error: e.toString());
    }
  }

  Future<WebViewController> _createWebViewController() async {
    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('[SilentRefresh] JS received: ${message.message.substring(0, message.message.length > 100 ? 100 : message.message.length)}...');
          if (_jsCompleter != null && !_jsCompleter!.isCompleted) {
            _jsCompleter!.complete(message.message);
          }
        },
      );

    return controller;
  }

  Future<void> _loadInitialPage(WebViewController controller) async {
    final completer = Completer<void>();
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    await controller.loadRequest(Uri.parse('https://www.maxjeune-tgvinoui.sncf/recherche'));
    await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  Future<String> _runJsAsync(WebViewController controller, String jsCode) async {
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

    await controller.runJavaScript(wrappedJs);

    return _jsCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => '{"error": "Timeout"}',
    );
  }
}

class SilentRefreshResult {
  final bool success;
  final List<Booking>? bookings;
  final List<Map<String, dynamic>>? bookingsRaw;
  final bool needsReauth;
  final String? error;

  SilentRefreshResult({
    required this.success,
    this.bookings,
    this.bookingsRaw,
    this.needsReauth = false,
    this.error,
  });
}

class ActionResult {
  final bool success;
  final bool needsReauth;
  final String? error;

  ActionResult({
    required this.success,
    this.needsReauth = false,
    this.error,
  });
}
