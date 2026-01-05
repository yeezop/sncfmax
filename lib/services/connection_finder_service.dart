import 'package:flutter/foundation.dart';
import '../data/station_graph.dart';
import '../models/train_proposal.dart';
import '../models/connected_journey.dart';
import '../models/search_preferences.dart';
import 'backend_api_service.dart';

/// Service for finding train connections using the real TGV Max route graph
class ConnectionFinderService {
  final BackendApiService _apiService;
  final StationGraph _graph = StationGraph.instance;

  // Cache for segment results: "originCode_destCode_dateKey" -> proposals
  final Map<String, List<TrainProposal>> _segmentCache = {};

  // Cache for station code to name mapping (built from API responses)
  final Map<String, String> _codeToName = {};
  final Map<String, String> _nameToCode = {};

  // Callback for progress updates
  void Function(int current, int total)? onProgress;

  ConnectionFinderService(this._apiService);

  void _log(String message) {
    debugPrint('[ConnectionFinder] $message');
  }

  /// Register a station code/name mapping (call this when user selects stations)
  void registerStation(String code, String name) {
    _codeToName[code] = name;
    _nameToCode[name.toUpperCase()] = code;

    // Also try to match with graph station
    final graphName = _graph.findStationByName(name);
    if (graphName != null) {
      _nameToCode[graphName] = code;
    }
  }

  /// Find all connected journeys from origin to destination
  Future<List<ConnectedJourney>> findConnections({
    required String originCode,
    required String originName,
    required String destinationCode,
    required String destinationName,
    required DateTime date,
    required SearchPreferences preferences,
  }) async {
    if (!preferences.allowsConnections) {
      return [];
    }

    // Register the stations
    registerStation(originCode, originName);
    registerStation(destinationCode, destinationName);

    _log('Finding connections: $originName -> $destinationName');
    _log('Max connections: ${preferences.connectionMode.maxConnections}');
    _log('Graph has ${_graph.stationCount} stations and ${_graph.routeCount} routes');

    // Find all valid paths using the route graph
    final paths = _graph.findPaths(
      originName: originName,
      destinationName: destinationName,
      maxConnections: preferences.connectionMode.maxConnections,
      maxPaths: 10,
    );

    _log('Found ${paths.length} possible paths through the network');

    if (paths.isEmpty) {
      _log('No paths found. Origin match: ${_graph.findStationByName(originName)}, Dest match: ${_graph.findStationByName(destinationName)}');
      return [];
    }

    final List<ConnectedJourney> results = [];
    int current = 0;
    final total = paths.length;

    // For each path, fetch train data and build journeys
    for (final path in paths) {
      current++;
      onProgress?.call(current, total);

      _log('Processing path $current/$total: ${path.join(" -> ")}');

      try {
        final journeys = await _buildJourneysForPath(
          path: path,
          originCode: originCode,
          destinationCode: destinationCode,
          date: date,
          minConnectionTime: preferences.minConnectionTime,
        );
        results.addAll(journeys);
        _log('  Found ${journeys.length} valid combinations');
      } catch (e) {
        _log('  Error processing path: $e');
      }
    }

    // Filter out direct trains (0 connections) - they're already shown in the main list
    final withConnections = results.where((j) => j.connectionCount >= 1).toList();

    // Sort by total duration, then by available seats
    withConnections.sort((a, b) {
      final durationCompare = a.totalDuration.compareTo(b.totalDuration);
      if (durationCompare != 0) return durationCompare;
      return b.availableSeats.compareTo(a.availableSeats);
    });

    // Limit to avoid overwhelming the UI
    final limitedResults = withConnections.take(30).toList();

    _log('Total: ${results.length} journeys found, ${withConnections.length} with connections (showing ${limitedResults.length})');
    return limitedResults;
  }

  /// Build all valid journey combinations for a given path
  Future<List<ConnectedJourney>> _buildJourneysForPath({
    required List<String> path,
    required String originCode,
    required String destinationCode,
    required DateTime date,
    required Duration minConnectionTime,
  }) async {
    if (path.length < 3) return []; // Need at least 1 connection

    // Fetch proposals for each segment
    final List<_SegmentData> segments = [];

    for (int i = 0; i < path.length - 1; i++) {
      final fromName = path[i];
      final toName = path[i + 1];

      // Determine codes: use known codes for origin/destination, search for intermediates
      String fromCode;
      String toCode;

      if (i == 0) {
        fromCode = originCode;
      } else {
        fromCode = await _findStationCode(fromName);
        if (fromCode.isEmpty) {
          _log('  Could not find code for: $fromName');
          return [];
        }
      }

      if (i == path.length - 2) {
        toCode = destinationCode;
      } else {
        toCode = await _findStationCode(toName);
        if (toCode.isEmpty) {
          _log('  Could not find code for: $toName');
          return [];
        }
      }

      final proposals = await _fetchSegmentProposals(
        originCode: fromCode,
        destinationCode: toCode,
        date: date,
      );

      if (proposals.isEmpty) {
        _log('  No trains for segment: $fromName -> $toName');
        return [];
      }

      segments.add(_SegmentData(
        fromCode: fromCode,
        fromName: fromName,
        toCode: toCode,
        toName: toName,
        proposals: proposals,
      ));
    }

    // Build all valid combinations respecting connection times
    return _combineSegments(
      segments: segments,
      minConnectionTime: minConnectionTime,
      date: date,
    );
  }

  /// Find station code by searching the API
  Future<String> _findStationCode(String stationName) async {
    // Check cache first
    final cached = _nameToCode[stationName];
    if (cached != null) return cached;

    // Try normalized name
    final normalized = stationName.toUpperCase();
    final cachedNorm = _nameToCode[normalized];
    if (cachedNorm != null) return cachedNorm;

    // Search via API
    try {
      final searchTerm = stationName
          .replaceAll('ST ', 'SAINT ')
          .replaceAll(' TGV', '')
          .split(' ')
          .first;

      final stations = await _apiService.searchStations(searchTerm);

      for (final station in stations) {
        // Register all found stations
        registerStation(station.codeStation, station.station);

        // Check if this matches
        if (_matchesStationName(station.station, stationName)) {
          return station.codeStation;
        }
      }

      // If exact match not found, return first result if it seems relevant
      if (stations.isNotEmpty) {
        final first = stations.first;
        if (_matchesStationName(first.station, stationName)) {
          return first.codeStation;
        }
      }
    } catch (e) {
      _log('Error searching station $stationName: $e');
    }

    return '';
  }

  /// Check if two station names match
  bool _matchesStationName(String apiName, String graphName) {
    final apiNorm = apiName.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final graphNorm = graphName.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // Exact match
    if (apiNorm == graphNorm) return true;

    // One contains the other
    if (apiNorm.contains(graphNorm) || graphNorm.contains(apiNorm)) return true;

    // Key word match
    final apiWords = apiNorm.split(RegExp(r'\d+')).where((w) => w.length > 3);
    final graphWords = graphNorm.split(RegExp(r'\d+')).where((w) => w.length > 3);

    for (final word in graphWords) {
      if (apiWords.any((w) => w.contains(word) || word.contains(w))) {
        return true;
      }
    }

    return false;
  }

  /// Fetch train proposals for a single segment (with caching)
  Future<List<TrainProposal>> _fetchSegmentProposals({
    required String originCode,
    required String destinationCode,
    required DateTime date,
  }) async {
    final dateKey = '${date.year}-${date.month}-${date.day}';
    final cacheKey = '${originCode}_${destinationCode}_$dateKey';

    if (_segmentCache.containsKey(cacheKey)) {
      return _segmentCache[cacheKey]!;
    }

    try {
      final result = await _apiService.searchTrainsForDay(
        origin: originCode,
        destination: destinationCode,
        date: date,
      );

      _segmentCache[cacheKey] = result.proposals;
      return result.proposals;
    } catch (e) {
      _log('Error fetching $originCode -> $destinationCode: $e');
      return [];
    }
  }

  /// Combine segment proposals into valid journeys
  List<ConnectedJourney> _combineSegments({
    required List<_SegmentData> segments,
    required Duration minConnectionTime,
    required DateTime date,
  }) {
    final List<ConnectedJourney> journeys = [];

    // Limit combinations per segment to avoid explosion
    const maxPerSegment = 8;
    final limitedSegments = segments
        .map((s) => _SegmentData(
              fromCode: s.fromCode,
              fromName: s.fromName,
              toCode: s.toCode,
              toName: s.toName,
              proposals: s.proposals.take(maxPerSegment).toList(),
            ))
        .toList();

    // Recursive combination builder
    void buildCombinations(
      int segmentIndex,
      DateTime earliestDeparture,
      List<JourneySegment> currentSegments,
    ) {
      // Limit total combinations
      if (journeys.length >= 15) return;

      if (segmentIndex >= limitedSegments.length) {
        // Complete journey
        if (currentSegments.isNotEmpty) {
          journeys.add(ConnectedJourney(segments: List.from(currentSegments)));
        }
        return;
      }

      final segmentData = limitedSegments[segmentIndex];

      for (final train in segmentData.proposals) {
        // Check if this train departs after minimum connection time
        if (train.departure.isBefore(earliestDeparture)) {
          continue;
        }

        // Skip trains arriving too late (next day issue)
        if (train.arrival.day != date.day &&
            train.arrival.difference(train.departure).inHours > 10) {
          continue;
        }

        final segment = JourneySegment(
          train: train,
          originCode: segmentData.fromCode,
          originName: segmentData.fromName,
          destinationCode: segmentData.toCode,
          destinationName: segmentData.toName,
        );

        currentSegments.add(segment);

        // Calculate earliest next departure (arrival + min connection time)
        final nextEarliest = train.arrival.add(minConnectionTime);

        buildCombinations(
          segmentIndex + 1,
          nextEarliest,
          currentSegments,
        );

        currentSegments.removeLast();
      }
    }

    // Start combinations from beginning of day
    final startOfDay = DateTime(date.year, date.month, date.day, 5, 0);
    buildCombinations(0, startOfDay, []);

    return journeys;
  }

  /// Clear the segment cache
  void clearCache() {
    _segmentCache.clear();
    _log('Cache cleared');
  }

  /// Clear cache for a specific date
  void clearCacheForDate(DateTime date) {
    final dateKey = '${date.year}-${date.month}-${date.day}';
    _segmentCache.removeWhere((key, _) => key.endsWith(dateKey));
    _log('Cache cleared for $dateKey');
  }
}

/// Internal class to hold segment data
class _SegmentData {
  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;
  final List<TrainProposal> proposals;

  _SegmentData({
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
    required this.proposals,
  });
}
