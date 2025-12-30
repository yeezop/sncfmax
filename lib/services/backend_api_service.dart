import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/station.dart';
import '../models/train_proposal.dart';
import '../models/booking.dart';

class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  factory BackendApiService() => _instance;
  BackendApiService._internal();

  // VPS Server address
  static const String _baseUrl = 'http://51.210.111.11:3000';

  bool _isReady = false;
  bool get isReady => _isReady;

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
      final response = await http.post(
        Uri.parse('$_baseUrl/init'),
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
      final response = await http.get(
        Uri.parse('$_baseUrl/api/stations?label=${Uri.encodeComponent(label)}'),
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
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/trains?origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}&date=${Uri.encodeComponent(dateStr)}',
        ),
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
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/trains/month?origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}&year=${month.year}&month=${month.month}',
        ),
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

        _log('========================================');
        _log('Summary (${stopwatch.elapsed.inSeconds}s):');
        _log('  Days: ${summary['totalDays']}');
        _log('  With availability: ${summary['daysWithAvailability']}');
        _log('  Total trains: ${summary['totalTrains']}');
        _log('  Cache: $fromCache hits, $fetched fetched ($cacheHitRate% hit rate)');
        if ((summary['errors'] as int) > 0) {
          _log('  Errors: ${summary['errors']}');
        }
        _log('========================================');

        return results;
      } else {
        throw Exception('Error in monthly search: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      _log('Error: $e');
      rethrow;
    }
  }

  // =====================================
  // AUTHENTICATION & BOOKINGS (Mon Max)
  // =====================================

  Future<UserSession> getAuthStatus() async {
    _log('Checking auth status...');

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/status'),
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
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/check'),
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
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
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
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/logout'),
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

      final response = await http.get(
        Uri.parse(url),
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
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/store-session'),
        headers: {'Content-Type': 'application/json'},
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
      final response = await http.post(
        Uri.parse('$_baseUrl/api/bookings/refresh'),
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
