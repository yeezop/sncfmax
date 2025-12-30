import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/station.dart';
import '../models/train_proposal.dart';
import 'cookie_manager.dart';

class SncfApiService {
  static const String _baseUrl = 'https://www.maxjeune-tgvinoui.sncf/api/public/refdata';

  // Activer/désactiver les logs
  static bool enableLogs = true;

  static void _log(String message) {
    if (enableLogs) {
      debugPrint('[SNCF API] $message');
    }
  }

  static void _logRequest(String method, Uri uri) {
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('📤 REQUEST: $method ${uri.path}');
    _log('   URL: $uri');
    if (uri.queryParameters.isNotEmpty) {
      _log('   Params: ${uri.queryParameters}');
    }
  }

  static void _logResponse(http.Response response, Duration duration) {
    final statusEmoji = response.statusCode == 200 ? '✅' : '❌';
    _log('📥 RESPONSE: $statusEmoji ${response.statusCode} (${duration.inMilliseconds}ms)');

    if (response.statusCode == 200) {
      try {
        final data = json.decode(response.body);
        if (data is Map) {
          final keys = data.keys.toList();
          _log('   Keys: $keys');
          // Log du nombre d'éléments pour les listes
          for (final key in keys) {
            if (data[key] is List) {
              _log('   $key: ${(data[key] as List).length} éléments');
            }
          }
        }
      } catch (_) {
        _log('   Body length: ${response.body.length} chars');
      }
    } else {
      _log('   Error body: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  static void _logError(String operation, dynamic error) {
    _log('🚨 ERROR [$operation]: $error');
  }

  static Map<String, String> get _headers {
    final headers = {
      'Accept': 'application/json',
      'x-client-app': 'MAX_JEUNE',
      'x-client-app-version': '2.45.1',
      'x-distribution-channel': 'OUI',
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };

    final cookieManager = CookieManager();
    if (cookieManager.isInitialized) {
      headers['Cookie'] = cookieManager.getCookieHeader();
      _log('🍪 Using cookies: ${headers['Cookie']?.substring(0, 50)}...');
    }

    return headers;
  }

  Future<List<Station>> searchStations(String label) async {
    if (label.isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/freeplaces-stations').replace(
      queryParameters: {'label': label},
    );

    _logRequest('GET', uri);
    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.get(uri, headers: _headers);
      stopwatch.stop();
      _logResponse(response, stopwatch.elapsed);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final stations = (data['stations'] as List)
            .map((s) => Station.fromJson(s))
            .toList();
        _log('🚉 ${stations.length} gare(s) trouvée(s) pour "$label"');
        return stations;
      } else {
        throw Exception('Erreur lors de la recherche de gares: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      _logError('searchStations', e);
      rethrow;
    }
  }

  Future<DayProposals> searchTrains({
    required String origin,
    required String destination,
    required DateTime date,
  }) async {
    // Format: 2025-12-29T01:00:00.000Z
    final dateStr = DateTime.utc(date.year, date.month, date.day, 1).toIso8601String();

    final uri = Uri.parse('$_baseUrl/search-freeplaces-proposals').replace(
      queryParameters: {
        'origin': origin,
        'destination': destination,
        'departureDateTime': dateStr,
      },
    );

    _logRequest('GET', uri);
    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.get(uri, headers: _headers);
      stopwatch.stop();
      _logResponse(response, stopwatch.elapsed);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final proposals = (data['proposals'] as List)
            .map((p) => TrainProposal.fromJson(p))
            .toList();
        final ratio = (data['ratio'] as num).toDouble();

        final availableCount = proposals.where((p) => p.availableSeats > 0).length;
        _log('🚄 ${date.day}/${date.month}: ${proposals.length} train(s), $availableCount dispo(s), ratio: ${(ratio * 100).toStringAsFixed(0)}%');

        return DayProposals(
          date: date,
          proposals: proposals,
          ratio: ratio,
        );
      } else {
        throw Exception('Erreur lors de la recherche de trains: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      _logError('searchTrains [${date.day}/${date.month}]', e);
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

    final futures = <Future<void>>[];
    var errorCount = 0;

    _log('📅 ════════════════════════════════════════');
    _log('📅 RECHERCHE MENSUELLE: ${month.month}/${month.year}');
    _log('📅 Trajet: $origin → $destination');

    final stopwatch = Stopwatch()..start();

    for (var day = firstDay;
        day.isBefore(lastDay.add(const Duration(days: 1)));
        day = day.add(const Duration(days: 1))) {
      if (day.isBefore(DateTime(today.year, today.month, today.day))) {
        continue;
      }

      futures.add(
        searchTrains(origin: origin, destination: destination, date: day)
            .then((proposals) {
          results[DateTime(day.year, day.month, day.day)] = proposals;
        }).catchError((e) {
          errorCount++;
          results[DateTime(day.year, day.month, day.day)] = DayProposals(
            date: day,
            proposals: [],
            ratio: 0,
          );
        }),
      );
    }

    await Future.wait(futures);
    stopwatch.stop();

    // Résumé de la recherche mensuelle
    final totalDays = results.length;
    final daysWithAvailability = results.values.where((d) => d.ratio > 0).length;
    final totalTrains = results.values.fold<int>(0, (sum, d) => sum + d.proposals.length);
    final totalAvailable = results.values.fold<int>(
        0, (sum, d) => sum + d.proposals.where((p) => p.availableSeats > 0).length);

    _log('📅 ════════════════════════════════════════');
    _log('📊 RÉSUMÉ MENSUEL (${stopwatch.elapsed.inSeconds}s):');
    _log('   📆 Jours analysés: $totalDays');
    _log('   ✅ Jours avec dispo: $daysWithAvailability');
    _log('   🚄 Total trains: $totalTrains');
    _log('   🎫 Places dispo: $totalAvailable');
    if (errorCount > 0) {
      _log('   ⚠️ Erreurs: $errorCount');
    }
    _log('📅 ════════════════════════════════════════');

    return results;
  }
}
