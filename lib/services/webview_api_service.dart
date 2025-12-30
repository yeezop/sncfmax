import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/train_proposal.dart';

class WebViewApiService {
  static final WebViewApiService _instance = WebViewApiService._internal();
  factory WebViewApiService() => _instance;
  WebViewApiService._internal();

  WebViewController? _controller;
  bool _isReady = false;
  final _readyCompleter = Completer<void>();

  // For receiving async results from JavaScript
  final Map<String, Completer<String>> _pendingRequests = {};
  int _requestCounter = 0;

  bool get isReady => _isReady;
  Future<void> get ready => _readyCompleter.future;
  WebViewController? get controller => _controller;

  static const String _baseUrl = 'https://www.maxjeune-tgvinoui.sncf';

  void _log(String message) {
    debugPrint('[WebViewAPI] $message');
  }

  Future<void> initialize() async {
    if (_isReady) return;

    _log('Initializing WebView...');

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
        onMessageReceived: (message) {
          _handleJsMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _log('Page loaded: $url');
            if (url.contains('maxjeune-tgvinoui.sncf') && !_isReady) {
              _isReady = true;
              if (!_readyCompleter.isCompleted) {
                _readyCompleter.complete();
              }
              _log('WebView ready!');
            }
          },
        ),
      );

    await _controller!.loadRequest(Uri.parse('$_baseUrl/recherche'));
  }

  void _handleJsMessage(String message) {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final requestId = data['requestId'] as String?;
      final result = data['result'] as String?;

      if (requestId != null && _pendingRequests.containsKey(requestId)) {
        _pendingRequests[requestId]!.complete(result ?? '');
        _pendingRequests.remove(requestId);
      }
    } catch (e) {
      _log('Error handling JS message: $e');
    }
  }

  Future<String> _executeAsyncJs(String jsCode) async {
    final requestId = 'req_${_requestCounter++}';
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;

    final wrappedJs = '''
      (async function() {
        try {
          const result = await (async function() { $jsCode })();
          FlutterChannel.postMessage(JSON.stringify({
            requestId: '$requestId',
            result: result
          }));
        } catch (e) {
          FlutterChannel.postMessage(JSON.stringify({
            requestId: '$requestId',
            result: JSON.stringify({success: false, error: e.toString()})
          }));
        }
      })();
    ''';

    await _controller!.runJavaScript(wrappedJs);

    // Timeout after 30 seconds
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw TimeoutException('JavaScript execution timed out');
      },
    );
  }

  Future<DayProposals> searchTrainsForDay({
    required String origin,
    required String destination,
    required DateTime date,
  }) async {
    if (!_isReady || _controller == null) {
      throw Exception('WebView not ready');
    }

    final dateStr = DateTime.utc(date.year, date.month, date.day, 1).toIso8601String();
    final url = '$_baseUrl/api/public/refdata/search-freeplaces-proposals?origin=$origin&destination=$destination&departureDateTime=${Uri.encodeComponent(dateStr)}';

    _log('Fetching: ${date.day}/${date.month}/${date.year}');

    final jsCode = '''
      const response = await fetch('$url', {
        method: 'GET',
        credentials: 'include',
        headers: {
          'Accept': 'application/json',
          'Accept-Language': 'fr-FR,fr;q=0.9',
          'x-client-app': 'MAX_JEUNE',
          'x-client-app-version': '2.45.1',
          'x-distribution-channel': 'OUI',
          'Referer': 'https://www.maxjeune-tgvinoui.sncf/recherche',
          'Origin': 'https://www.maxjeune-tgvinoui.sncf'
        }
      });
      if (response.status === 403) {
        const text = await response.text();
        return JSON.stringify({success: false, error: 'Blocked by captcha', status: 403, body: text.substring(0, 200)});
      }
      const data = await response.json();
      return JSON.stringify({success: true, data: data, status: response.status});
    ''';

    final resultStr = await _executeAsyncJs(jsCode);

    try {
      final parsed = json.decode(resultStr) as Map<String, dynamic>;

      if (parsed['success'] == true) {
        final data = parsed['data'] as Map<String, dynamic>;
        final proposals = (data['proposals'] as List)
            .map((p) => TrainProposal.fromJson(p as Map<String, dynamic>))
            .toList();
        final ratio = (data['ratio'] as num).toDouble();

        _log('${date.day}/${date.month}: ${proposals.length} trains, ratio: ${(ratio * 100).toStringAsFixed(0)}%');

        return DayProposals(
          date: date,
          proposals: proposals,
          ratio: ratio,
        );
      } else {
        throw Exception(parsed['error'] ?? 'Unknown error');
      }
    } catch (e) {
      _log('Error parsing response: $e');
      _log('Raw result: $resultStr');
      rethrow;
    }
  }

  Future<Map<DateTime, DayProposals>> searchTrainsForMonth({
    required String origin,
    required String destination,
    required DateTime month,
  }) async {
    final results = <DateTime, DayProposals>{};
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final today = DateTime.now();

    _log('========================================');
    _log('Monthly search: ${month.month}/${month.year}');
    _log('Route: $origin -> $destination');

    final stopwatch = Stopwatch()..start();
    var errorCount = 0;

    // Process sequentially with small delays to avoid detection
    for (var day = firstDay;
        day.isBefore(lastDay.add(const Duration(days: 1)));
        day = day.add(const Duration(days: 1))) {

      if (day.isBefore(DateTime(today.year, today.month, today.day))) {
        continue;
      }

      try {
        final proposals = await searchTrainsForDay(
          origin: origin,
          destination: destination,
          date: day,
        );
        results[DateTime(day.year, day.month, day.day)] = proposals;

        // Small delay between requests
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        errorCount++;
        _log('Error for ${day.day}/${day.month}: $e');
        results[DateTime(day.year, day.month, day.day)] = DayProposals(
          date: day,
          proposals: [],
          ratio: 0,
        );
      }
    }

    stopwatch.stop();

    final totalDays = results.length;
    final daysWithAvailability = results.values.where((d) => d.ratio > 0).length;
    final totalTrains = results.values.fold<int>(0, (sum, d) => sum + d.proposals.length);

    _log('========================================');
    _log('Summary (${stopwatch.elapsed.inSeconds}s):');
    _log('  Days: $totalDays');
    _log('  With availability: $daysWithAvailability');
    _log('  Total trains: $totalTrains');
    if (errorCount > 0) {
      _log('  Errors: $errorCount');
    }
    _log('========================================');

    return results;
  }

  void dispose() {
    _controller = null;
    _isReady = false;
    _pendingRequests.clear();
  }
}
