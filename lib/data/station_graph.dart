import 'dart:collection';
import 'tgvmax_routes.dart';

/// Graph of TGV Max routes for pathfinding
class StationGraph {
  static StationGraph? _instance;

  /// Adjacency list: station name -> set of connected station names
  final Map<String, Set<String>> _adjacencyList = {};

  /// All unique station names
  final Set<String> _allStations = {};

  StationGraph._() {
    _buildGraph();
  }

  static StationGraph get instance {
    _instance ??= StationGraph._();
    return _instance!;
  }

  /// Build the adjacency list from tgvMaxRoutes
  void _buildGraph() {
    for (final route in tgvMaxRoutes) {
      final station1 = route.$1;
      final station2 = route.$2;

      _allStations.add(station1);
      _allStations.add(station2);

      // Bidirectional graph
      _adjacencyList.putIfAbsent(station1, () => {}).add(station2);
      _adjacencyList.putIfAbsent(station2, () => {}).add(station1);
    }
  }

  /// Get all stations connected to a given station
  Set<String> getConnectedStations(String stationName) {
    return _adjacencyList[stationName] ?? {};
  }

  /// Check if two stations are directly connected
  bool areDirectlyConnected(String station1, String station2) {
    return _adjacencyList[station1]?.contains(station2) ?? false;
  }

  /// Find the best matching station name from user input
  /// Returns the station name as it appears in tgvMaxRoutes
  String? findStationByName(String searchName) {
    final normalized = _normalizeForSearch(searchName);

    // Exact match first
    for (final station in _allStations) {
      if (_normalizeForSearch(station) == normalized) {
        return station;
      }
    }

    // Contains match
    for (final station in _allStations) {
      final stationNorm = _normalizeForSearch(station);
      if (stationNorm.contains(normalized) || normalized.contains(stationNorm)) {
        return station;
      }
    }

    // Word-based match (e.g., "Lille Europe" -> "LILLE")
    final searchWords = normalized.split(' ').where((w) => w.length > 2).toList();
    for (final station in _allStations) {
      final stationNorm = _normalizeForSearch(station);
      for (final word in searchWords) {
        if (stationNorm.contains(word) || word.contains(stationNorm)) {
          return station;
        }
      }
    }

    return null;
  }

  /// Find all paths from origin to destination with max N connections
  /// Returns list of paths, each path is a list of station names
  List<List<String>> findPaths({
    required String originName,
    required String destinationName,
    required int maxConnections,
    int maxPaths = 15,
  }) {
    // Find matching stations in the graph
    final origin = findStationByName(originName);
    final destination = findStationByName(destinationName);

    if (origin == null || destination == null) {
      return [];
    }

    if (origin == destination) {
      return [];
    }

    final List<List<String>> validPaths = [];
    final Queue<List<String>> queue = Queue();

    queue.add([origin]);

    while (queue.isNotEmpty && validPaths.length < maxPaths) {
      final currentPath = queue.removeFirst();
      final currentStation = currentPath.last;

      // Get all connected stations
      final connected = getConnectedStations(currentStation);

      for (final nextStation in connected) {
        // Avoid cycles
        if (currentPath.contains(nextStation)) {
          continue;
        }

        final newPath = [...currentPath, nextStation];

        // Check if we reached destination
        if (nextStation == destination) {
          // Only add paths with at least 1 connection (2+ segments)
          if (newPath.length >= 3) {
            validPaths.add(newPath);
          }
          continue;
        }

        // Check depth limit (path length = stations, connections = stations - 1)
        // For maxConnections=2, we want paths with 3 stations max (A->B->C)
        // But we're looking for paths that END at destination, so we need to allow
        // one more station to potentially reach it
        if (newPath.length <= maxConnections + 1) {
          queue.add(newPath);
        }
      }
    }

    // Sort by path length (fewer connections first)
    validPaths.sort((a, b) => a.length.compareTo(b.length));

    return validPaths.take(maxPaths).toList();
  }

  /// Normalize station name for searching
  String _normalizeForSearch(String name) {
    return name
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Get all station names
  Set<String> get allStations => _allStations;

  /// Get number of stations
  int get stationCount => _allStations.length;

  /// Get number of routes
  int get routeCount => tgvMaxRoutes.length;
}
