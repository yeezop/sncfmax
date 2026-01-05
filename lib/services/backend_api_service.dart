import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';
import '../models/train_proposal.dart';
import '../models/booking.dart';

class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  factory BackendApiService() => _instance;
  BackendApiService._internal();

  // VPS Server address
  static const String _baseUrl = 'http://51.210.111.11:3000';

  // API Key for authentication (should match backend's API_KEY)
  static const String? _apiKey = String.fromEnvironment('API_KEY', defaultValue: '');

  // Unique user ID for multi-user session support
  String? _userId;

  bool _isReady = false;
  bool get isReady => _isReady;

  /// Get or create a unique user ID for this device
  Future<String> _getUserId() async {
    if (_userId != null) return _userId!;

    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');

    if (_userId == null) {
      _userId = const Uuid().v4();
      await prefs.setString('user_id', _userId!);
    }

    return _userId!;
  }

  /// Get headers for API requests
  Future<Map<String, String>> _getHeaders({bool withContentType = false}) async {
    final userId = await _getUserId();
    final headers = <String, String>{
      'x-user-id': userId,
    };

    if (_apiKey != null && _apiKey!.isNotEmpty) {
      headers['x-api-key'] = _apiKey!;
    }

    if (withContentType) {
      headers['Content-Type'] = 'application/json';
    }

    return headers;
  }

  void _log(String message) {
    debugPrint('[BackendAPI] $message');
  }

  Future<void> initialize() async {
    _log('Checking backend server...');

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _isReady = data['ready'] == true;
        final cacheSize = data['cacheSize'] ?? 0;
        _log('Backend status: ${_isReady ? "ready" : "not ready"} | Cache: $cacheSize entries');

        if (!_isReady) {
          // Try to initialize
          await _initBackend();
        }
      }
    } catch (e) {
      _log('Backend not available: $e');
      _isReady = false;
      rethrow;
    }
  }

  Future<void> _initBackend() async {
    _log('Initializing backend session...');

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/init'),
        headers: headers,
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        _isReady = true;
        _log('Backend initialized successfully');
      } else {
        throw Exception('Failed to initialize backend: ${response.statusCode}');
      }
    } catch (e) {
      _log('Failed to initialize backend: $e');
      rethrow;
    }
  }

  Future<List<Station>> searchStations(String label) async {
    if (label.isEmpty) return [];

    _log('Searching stations: $label');

    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/stations?label=${Uri.encodeComponent(label)}'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final stations = (data['stations'] as List)
            .map((s) => Station.fromJson(s))
            .toList();
        _log('Found ${stations.length} stations');
        return stations;
      } else {
        throw Exception('Error searching stations: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error: $e');
      rethrow;
    }
  }

  Future<DayProposals> searchTrainsForDay({
    required String origin,
    required String destination,
    required DateTime date,
  }) async {
    final dateStr = DateTime.utc(date.year, date.month, date.day, 1).toIso8601String();

    _log('Searching trains for ${date.day}/${date.month}/${date.year}');

    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/trains?origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}&date=${Uri.encodeComponent(dateStr)}',
        ),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final proposals = (data['proposals'] as List)
            .map((p) => TrainProposal.fromJson(p as Map<String, dynamic>))
            .toList();
        final ratio = (data['ratio'] as num).toDouble();
        final fromCache = data['_cached'] == true;
        final cachedAt = data['_cachedAt'] as String?;

        final cacheInfo = fromCache ? '(cache${cachedAt != null ? " @ $cachedAt" : ""})' : '(fresh)';
        _log('${date.day}/${date.month}: ${proposals.length} trains, ratio: ${(ratio * 100).toStringAsFixed(0)}% $cacheInfo');

        return DayProposals(
          date: date,
          proposals: proposals,
          ratio: ratio,
        );
      } else {
        throw Exception('Error searching trains: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error: $e');
      rethrow;
    }
  }

  Future<Map<DateTime, DayProposals>> searchTrainsForMonth({
    required String origin,
    required String destination,
    required DateTime month,
  }) async {
    _log('========================================');
    _log('Monthly search: ${month.month}/${month.year}');
    _log('Route: $origin -> $destination');

    final stopwatch = Stopwatch()..start();

    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/trains/month?origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}&year=${month.year}&month=${month.month}',
        ),
        headers: headers,
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final resultsJson = data['results'] as Map<String, dynamic>;
        final summary = data['summary'] as Map<String, dynamic>;

        final results = <DateTime, DayProposals>{};

        for (final entry in resultsJson.entries) {
          final dateParts = entry.key.split('-');
          final date = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          );

          final dayData = entry.value as Map<String, dynamic>;
          final proposals = (dayData['proposals'] as List? ?? [])
              .map((p) => TrainProposal.fromJson(p as Map<String, dynamic>))
              .toList();
          final ratio = (dayData['ratio'] as num?)?.toDouble() ?? 0.0;

          results[date] = DayProposals(
            date: date,
            proposals: proposals,
            ratio: ratio,
          );
        }

        stopwatch.stop();

        final cacheInfo = data['cacheInfo'] as Map<String, dynamic>?;
        final fromCache = cacheInfo?['fromCache'] ?? 0;
        final fetched = cacheInfo?['fetched'] ?? 0;
        final cacheHitRate = cacheInfo?['cacheHitRate'] ?? 0;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        final elapsedStr = elapsedMs < 1000
            ? '${elapsedMs}ms'
            : '${(elapsedMs / 1000).toStringAsFixed(2)}s';

        _log('========================================');
        _log('⏱️ Search completed in $elapsedStr');
        _log('📊 Days: ${summary['totalDays']} | Available: ${summary['daysWithAvailability']} | Trains: ${summary['totalTrains']}');
        _log('💾 Cache: $fromCache hits, $fetched fetched ($cacheHitRate% hit rate)');
        if ((summary['errors'] as int) > 0) {
          _log('⚠️ Errors: ${summary['errors']}');
        }
        _log('========================================');

        return results;
      } else {
        throw Exception('Error in monthly search: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      _log('❌ Error after ${stopwatch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  // =====================================
  // AUTHENTICATION & BOOKINGS (Mon Max)
  // =====================================

  Future<UserSession> getAuthStatus() async {
    _log('Checking auth status...');

    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/status'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final session = UserSession.fromJson(data);
        _log('Auth status: ${session.isAuthenticated ? "authenticated" : "not authenticated"}');
        return session;
      } else {
        throw Exception('Failed to get auth status: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error getting auth status: $e');
      rethrow;
    }
  }

  Future<UserSession> checkAuth() async {
    _log('Checking authentication...');

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/check'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final session = UserSession.fromJson(data);
        _log('Auth check: ${session.isAuthenticated ? "authenticated as ${session.displayName}" : "not authenticated"}');
        return session;
      } else {
        throw Exception('Failed to check auth: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error checking auth: $e');
      rethrow;
    }
  }

  Future<void> prepareLogin() async {
    _log('Preparing login...');

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: headers,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        _log('Login page ready');
      } else {
        throw Exception('Failed to prepare login: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error preparing login: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    _log('Logging out...');

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/logout'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _log('Logged out successfully');
      } else {
        throw Exception('Failed to logout: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error logging out: $e');
      rethrow;
    }
  }

  Future<List<Booking>> getBookings({DateTime? startDate}) async {
    _log('Fetching bookings...');

    try {
      String url = '$_baseUrl/api/bookings';
      if (startDate != null) {
        url += '?startDate=${Uri.encodeComponent(startDate.toIso8601String())}';
      }

      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bookingsJson = data['bookings'] as List;
        final bookings = bookingsJson
            .map((b) => Booking.fromJson(b as Map<String, dynamic>))
            .toList();

        // Sort by departure date (upcoming first)
        bookings.sort((a, b) => a.departure.compareTo(b.departure));

        _log('Found ${bookings.length} bookings');
        return bookings;
      } else if (response.statusCode == 401) {
        throw Exception('Non authentifié');
      } else {
        throw Exception('Failed to get bookings: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error fetching bookings: $e');
      rethrow;
    }
  }

  /// Store session data on backend for persistent auth
  Future<void> storeSession({
    required String cardNumber,
    required String firstName,
    required String lastName,
    String? email,
    required List<Map<String, dynamic>> bookings,
  }) async {
    _log('Storing session on backend...');

    try {
      final headers = await _getHeaders(withContentType: true);
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/store-session'),
        headers: headers,
        body: json.encode({
          'user': {
            'cardNumber': cardNumber,
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
          },
          'bookings': bookings,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('Session stored: ${data['bookingsCount']} bookings');
      } else {
        throw Exception('Failed to store session: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error storing session: $e');
      rethrow;
    }
  }

  /// Refresh bookings from backend (uses stored session cookies)
  Future<RefreshResult> refreshBookings() async {
    _log('Refreshing bookings from backend...');

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/api/bookings/refresh'),
        headers: headers,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bookingsJson = data['bookings'] as List;
        final bookings = bookingsJson
            .map((b) => Booking.fromJson(b as Map<String, dynamic>))
            .toList();

        // Sort by departure date (upcoming first)
        bookings.sort((a, b) => a.departure.compareTo(b.departure));

        final user = data['user'] as Map<String, dynamic>?;
        _log('Refreshed ${bookings.length} bookings');

        return RefreshResult(
          success: true,
          bookings: bookings,
          firstName: user?['firstName'],
          lastName: user?['lastName'],
          cardNumber: user?['cardNumber'],
        );
      } else if (response.statusCode == 401) {
        final data = json.decode(response.body);
        final needsReauth = data['needsReauth'] == true;
        _log('Refresh failed: ${needsReauth ? "session expired" : "not authenticated"}');
        return RefreshResult(
          success: false,
          needsReauth: needsReauth,
          error: data['message'] ?? 'Non authentifié',
        );
      } else {
        throw Exception('Failed to refresh bookings: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error refreshing bookings: $e');
      return RefreshResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  String get loginUrl => 'https://www.maxjeune-tgvinoui.sncf/sncf-connect/mes-voyages';

  // =====================================
  // PUPPETEER AUTH (Backend Auto-Confirm)
  // Alternative to WebView auth for automatic confirmations
  // =====================================

  /// Login via Puppeteer backend (enables auto-confirm)
  Future<PuppeteerLoginResult> puppeteerLogin({
    required String email,
    required String password,
  }) async {
    _log('[Puppeteer] Login attempt...');

    try {
      final headers = await _getHeaders(withContentType: true);
      final response = await http.post(
        Uri.parse('$_baseUrl/api/puppeteer/login'),
        headers: headers,
        body: json.encode({
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 120));

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _log('[Puppeteer] Login successful');
        return PuppeteerLoginResult(
          success: true,
          session: UserSession.fromJson({'isAuthenticated': true, 'user': data['session']}),
          bookingsCount: data['bookingsCount'] ?? 0,
        );
      } else if (data['needs2FA'] == true) {
        _log('[Puppeteer] 2FA required');
        return PuppeteerLoginResult(
          success: false,
          needs2FA: true,
          message: data['message'],
        );
      } else {
        _log('[Puppeteer] Login failed: ${data['error']}');
        return PuppeteerLoginResult(
          success: false,
          error: data['error'] ?? 'Échec de la connexion',
        );
      }
    } catch (e) {
      _log('[Puppeteer] Login error: $e');
      return PuppeteerLoginResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Submit 2FA code for Puppeteer login
  Future<PuppeteerLoginResult> puppeteerSubmit2FA(String code) async {
    _log('[Puppeteer] Submitting 2FA code...');

    try {
      final headers = await _getHeaders(withContentType: true);
      final response = await http.post(
        Uri.parse('$_baseUrl/api/puppeteer/2fa'),
        headers: headers,
        body: json.encode({'code': code}),
      ).timeout(const Duration(seconds: 60));

      final data = json.decode(response.body);

      if (data['success'] == true) {
        _log('[Puppeteer] 2FA successful');
        return PuppeteerLoginResult(
          success: true,
          session: UserSession.fromJson({'isAuthenticated': true, 'user': data['session']}),
          bookingsCount: data['bookingsCount'] ?? 0,
        );
      } else {
        return PuppeteerLoginResult(
          success: false,
          error: data['error'] ?? 'Code invalide',
        );
      }
    } catch (e) {
      _log('[Puppeteer] 2FA error: $e');
      return PuppeteerLoginResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Get Puppeteer auth status
  Future<PuppeteerStatus> getPuppeteerStatus() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/puppeteer/status'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      return PuppeteerStatus.fromJson(data);
    } catch (e) {
      _log('[Puppeteer] Status error: $e');
      return PuppeteerStatus(isAuthenticated: false);
    }
  }

  /// Refresh bookings via Puppeteer (fresh data from SNCF)
  Future<RefreshResult> puppeteerRefreshBookings() async {
    _log('[Puppeteer] Refreshing bookings...');

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/api/puppeteer/bookings/refresh'),
        headers: headers,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bookingsJson = data['bookings'] as List? ?? [];
        final bookings = bookingsJson
            .map((b) => Booking.fromJson(b as Map<String, dynamic>))
            .toList();

        bookings.sort((a, b) => a.departure.compareTo(b.departure));

        final session = data['session'] as Map<String, dynamic>?;
        _log('[Puppeteer] Refreshed ${bookings.length} bookings');

        return RefreshResult(
          success: true,
          bookings: bookings,
          firstName: session?['firstName'],
          lastName: session?['lastName'],
          cardNumber: session?['cardNumber'],
        );
      } else if (response.statusCode == 401) {
        return RefreshResult(
          success: false,
          needsReauth: true,
          error: 'Session expirée',
        );
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      _log('[Puppeteer] Refresh error: $e');
      return RefreshResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Confirm a booking via Puppeteer
  Future<ActionResult> puppeteerConfirmBooking(Booking booking) async {
    _log('[Puppeteer] Confirming booking: ${booking.trainNumber}');

    try {
      final headers = await _getHeaders(withContentType: true);
      final response = await http.post(
        Uri.parse('$_baseUrl/api/puppeteer/confirm'),
        headers: headers,
        body: json.encode({'booking': booking.toJson()}),
      ).timeout(const Duration(seconds: 30));

      final data = json.decode(response.body);

      if (data['success'] == true) {
        _log('[Puppeteer] Booking confirmed');
        return ActionResult(success: true);
      } else if (response.statusCode == 401) {
        return ActionResult(success: false, needsReauth: true, error: 'Session expirée');
      } else {
        return ActionResult(success: false, error: data['error'] ?? 'Échec');
      }
    } catch (e) {
      _log('[Puppeteer] Confirm error: $e');
      return ActionResult(success: false, error: e.toString());
    }
  }

  /// Logout from Puppeteer session
  Future<void> puppeteerLogout() async {
    _log('[Puppeteer] Logging out...');

    try {
      final headers = await _getHeaders();
      await http.post(
        Uri.parse('$_baseUrl/api/puppeteer/logout'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      _log('[Puppeteer] Logout error: $e');
    }
  }

  // =====================================
  // AUTO-CONFIRM API
  // =====================================

  /// Schedule auto-confirmation for a booking
  Future<bool> scheduleAutoConfirm(Booking booking) async {
    _log('[AutoConfirm] Scheduling: ${booking.trainNumber}');

    try {
      final headers = await _getHeaders(withContentType: true);
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auto-confirm/schedule'),
        headers: headers,
        body: json.encode({'booking': booking.toJson()}),
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      if (data['success'] == true) {
        _log('[AutoConfirm] Scheduled successfully');
        return true;
      } else {
        _log('[AutoConfirm] Failed: ${data['error']}');
        return false;
      }
    } catch (e) {
      _log('[AutoConfirm] Error: $e');
      return false;
    }
  }

  /// Cancel scheduled auto-confirmation
  Future<bool> cancelAutoConfirm(String bookingKey) async {
    _log('[AutoConfirm] Cancelling: $bookingKey');

    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/auto-confirm/${Uri.encodeComponent(bookingKey)}'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      return data['success'] == true;
    } catch (e) {
      _log('[AutoConfirm] Cancel error: $e');
      return false;
    }
  }

  /// Get all scheduled auto-confirmations
  Future<List<AutoConfirmSchedule>> getAutoConfirmSchedule() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auto-confirm'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      final scheduleList = data['schedule'] as List? ?? [];

      return scheduleList
          .map((s) => AutoConfirmSchedule.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log('[AutoConfirm] Get schedule error: $e');
      return [];
    }
  }
}

/// Result of Puppeteer login attempt
class PuppeteerLoginResult {
  final bool success;
  final UserSession? session;
  final int bookingsCount;
  final bool needs2FA;
  final String? message;
  final String? error;

  PuppeteerLoginResult({
    required this.success,
    this.session,
    this.bookingsCount = 0,
    this.needs2FA = false,
    this.message,
    this.error,
  });
}

/// Puppeteer session status
class PuppeteerStatus {
  final bool isAuthenticated;
  final bool pending2FA;
  final UserSession? session;
  final int bookingsCount;
  final DateTime? lastActivity;

  PuppeteerStatus({
    required this.isAuthenticated,
    this.pending2FA = false,
    this.session,
    this.bookingsCount = 0,
    this.lastActivity,
  });

  factory PuppeteerStatus.fromJson(Map<String, dynamic> json) {
    return PuppeteerStatus(
      isAuthenticated: json['isAuthenticated'] ?? false,
      pending2FA: json['pending2FA'] ?? false,
      session: json['session'] != null
          ? UserSession.fromJson({'isAuthenticated': true, 'user': json['session']})
          : null,
      bookingsCount: json['bookingsCount'] ?? 0,
      lastActivity: json['lastActivity'] != null
          ? DateTime.tryParse(json['lastActivity'].toString())
          : null,
    );
  }
}

/// Action result (confirm, cancel, etc.)
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

/// Auto-confirm schedule entry
class AutoConfirmSchedule {
  final String key;
  final String trainNumber;
  final String departure;
  final String? origin;
  final String? destination;
  final String status;
  final DateTime scheduledAt;

  AutoConfirmSchedule({
    required this.key,
    required this.trainNumber,
    required this.departure,
    this.origin,
    this.destination,
    required this.status,
    required this.scheduledAt,
  });

  factory AutoConfirmSchedule.fromJson(Map<String, dynamic> json) {
    return AutoConfirmSchedule(
      key: json['key'] ?? '',
      trainNumber: json['trainNumber'] ?? '',
      departure: json['departure'] ?? '',
      origin: json['origin'],
      destination: json['destination'],
      status: json['status'] ?? 'pending',
      scheduledAt: DateTime.tryParse(json['scheduledAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'En attente';
      case 'confirming':
        return 'Confirmation en cours...';
      case 'confirmed':
        return 'Confirmé';
      case 'failed':
        return 'Échec';
      case 'needs_reauth':
        return 'Reconnexion requise';
      default:
        return status;
    }
  }
}

/// Result of a booking refresh attempt
class RefreshResult {
  final bool success;
  final List<Booking>? bookings;
  final String? firstName;
  final String? lastName;
  final String? cardNumber;
  final bool needsReauth;
  final String? error;

  RefreshResult({
    required this.success,
    this.bookings,
    this.firstName,
    this.lastName,
    this.cardNumber,
    this.needsReauth = false,
    this.error,
  });
}
