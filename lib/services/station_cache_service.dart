import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';
import 'backend_api_service.dart';

class StationCacheService {
  static final StationCacheService _instance = StationCacheService._internal();
  factory StationCacheService() => _instance;
  StationCacheService._internal();

  static const String _cacheKey = 'cached_stations';
  static const String _recentKey = 'recent_stations';
  static const int _maxRecent = 10;
  static const int _maxCache = 100;

  List<Station> _cachedStations = [];
  List<Station> _recentStations = [];
  bool _isLoaded = false;

  void _log(String message) {
    debugPrint('[StationCache] $message');
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;

    final prefs = await SharedPreferences.getInstance();

    // Load cached stations
    final cacheJson = prefs.getString(_cacheKey);
    if (cacheJson != null) {
      try {
        final List<dynamic> decoded = json.decode(cacheJson);
        _cachedStations = decoded
            .map((s) => Station.fromJson(s as Map<String, dynamic>))
            .toList();
        _log('Loaded ${_cachedStations.length} cached stations');
      } catch (e) {
        _log('Error loading cache: $e');
        _cachedStations = [];
      }
    }

    // Load recent stations
    final recentJson = prefs.getString(_recentKey);
    if (recentJson != null) {
      try {
        final List<dynamic> decoded = json.decode(recentJson);
        _recentStations = decoded
            .map((s) => Station.fromJson(s as Map<String, dynamic>))
            .toList();
        _log('Loaded ${_recentStations.length} recent stations');
      } catch (e) {
        _log('Error loading recent: $e');
        _recentStations = [];
      }
    }

    _isLoaded = true;
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson = json.encode(_cachedStations.map((s) => s.toJson()).toList());
    await prefs.setString(_cacheKey, cacheJson);
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final recentJson = json.encode(_recentStations.map((s) => s.toJson()).toList());
    await prefs.setString(_recentKey, recentJson);
  }

  Future<void> addStation(Station station) async {
    await _ensureLoaded();

    // Add to recent (at the beginning, remove duplicates)
    _recentStations.removeWhere((s) => s.codeStation == station.codeStation);
    _recentStations.insert(0, station);
    if (_recentStations.length > _maxRecent) {
      _recentStations = _recentStations.sublist(0, _maxRecent);
    }

    // Add to cache if not already present
    if (!_cachedStations.any((s) => s.codeStation == station.codeStation)) {
      _cachedStations.add(station);
      if (_cachedStations.length > _maxCache) {
        _cachedStations.removeAt(0);
      }
    }

    await Future.wait([_saveCache(), _saveRecent()]);
    _log('Added station: ${station.station}');
  }

  Future<List<Station>> getRecentStations() async {
    await _ensureLoaded();
    return List.unmodifiable(_recentStations);
  }

  Future<List<Station>> searchStations(
    String query,
    BackendApiService apiService,
  ) async {
    await _ensureLoaded();

    // If query is empty, return recent stations
    if (query.trim().isEmpty) {
      return _recentStations;
    }

    final normalizedQuery = query.toLowerCase().trim();

    // Search in cache first
    final cacheResults = _cachedStations.where((s) {
      return s.station.toLowerCase().contains(normalizedQuery) ||
          s.codeStation.toLowerCase().contains(normalizedQuery);
    }).toList();

    _log('Cache results for "$query": ${cacheResults.length}');

    // If we have enough results from cache, return them
    if (cacheResults.length >= 5) {
      return cacheResults.take(10).toList();
    }

    // Otherwise, fetch from API
    try {
      final apiResults = await apiService.searchStations(query);
      _log('API results for "$query": ${apiResults.length}');

      // Add new stations to cache
      for (final station in apiResults) {
        if (!_cachedStations.any((s) => s.codeStation == station.codeStation)) {
          _cachedStations.add(station);
        }
      }

      // Trim cache if needed
      if (_cachedStations.length > _maxCache) {
        _cachedStations = _cachedStations.sublist(_cachedStations.length - _maxCache);
      }

      await _saveCache();

      // Merge results: cache first, then API (no duplicates)
      final mergedResults = <Station>[];
      final seenCodes = <String>{};

      for (final station in cacheResults) {
        if (!seenCodes.contains(station.codeStation)) {
          mergedResults.add(station);
          seenCodes.add(station.codeStation);
        }
      }

      for (final station in apiResults) {
        if (!seenCodes.contains(station.codeStation)) {
          mergedResults.add(station);
          seenCodes.add(station.codeStation);
        }
      }

      return mergedResults.take(15).toList();
    } catch (e) {
      _log('API error: $e');
      // Return cache results even if API fails
      return cacheResults;
    }
  }
}
