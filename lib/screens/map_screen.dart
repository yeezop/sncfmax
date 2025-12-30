import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../data/tgvmax_routes.dart';
import '../services/backend_api_service.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback onBackPressed;

  const MapScreen({super.key, required this.onBackPressed});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF475569);
  static const Color _routeColor = Color(0xFFEF4444);
  static const Color _originColor = Color(0xFF22C55E);
  static const Color _destinationColor = Color(0xFFEF4444);

  final MapController _mapController = MapController();
  String? _selectedStation;
  AnimationController? _zoomAnimationController;

  // Route finding mode
  bool _routeMode = false;
  String? _originStation;
  String? _destinationStation;
  List<List<String>> _foundPaths = [];
  int _selectedPathIndex = 0;
  Map<String, List<String>> _graph = {};

  // Pathfinding mode: 'distance' or 'availability'
  String _pathfindingMode = 'distance';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  bool _isLoadingAvailability = false;
  final Map<String, double> _segmentAvailability = {}; // "PARIS|LILLE" -> ratio (0.0-1.0)
  final Map<List<String>, double> _pathScores = {}; // path -> availability score
  final BackendApiService _api = BackendApiService();

  // Center of France
  static const LatLng _franceCenter = LatLng(46.603354, 2.5);

  @override
  void initState() {
    super.initState();
    _buildGraph();
  }

  void _buildGraph() {
    _graph = {};
    // Utiliser les routes TGV Max réelles pour le pathfinding
    for (final route in tgvMaxRoutes) {
      final origin = route.$1;
      final dest = route.$2;
      _graph.putIfAbsent(origin, () => []);
      _graph.putIfAbsent(dest, () => []);
      if (!_graph[origin]!.contains(dest)) _graph[origin]!.add(dest);
      if (!_graph[dest]!.contains(origin)) _graph[dest]!.add(origin);
    }
  }

  // Distance euclidienne simple pour le pathfinding
  double _simpleDistance(LatLng a, LatLng b) {
    final dx = (b.longitude - a.longitude) * 85; // ~85km par degré de longitude en France
    final dy = (b.latitude - a.latitude) * 111;  // ~111km par degré de latitude
    return dx * dx + dy * dy; // Distance au carré (pas besoin de sqrt pour comparer)
  }

  // Calcule la distance totale d'un chemin
  double _pathDistance(List<String> path) {
    double total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      final from = _stationCoordinates[path[i]];
      final to = _stationCoordinates[path[i + 1]];
      if (from != null && to != null) {
        total += _simpleDistance(from, to);
      }
    }
    return total;
  }

  // Clé unique pour un segment (ordre alphabétique pour bidirectionnel)
  String _segmentKey(String a, String b) {
    return a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  }

  // Charge la disponibilité d'un segment depuis l'API
  Future<double> _loadSegmentAvailability(String origin, String dest) async {
    final key = _segmentKey(origin, dest);
    if (_segmentAvailability.containsKey(key)) {
      return _segmentAvailability[key]!;
    }

    try {
      final result = await _api.searchTrainsForDay(
        origin: origin,
        destination: dest,
        date: _selectedDate,
      );
      final ratio = result.ratio;
      _segmentAvailability[key] = ratio;
      return ratio;
    } catch (e) {
      debugPrint('Error loading availability for $origin -> $dest: $e');
      // En cas d'erreur, retourner 0 (pas de disponibilité connue)
      _segmentAvailability[key] = 0.0;
      return 0.0;
    }
  }

  // Charge la disponibilité de tous les segments d'un chemin
  Future<double> _loadPathAvailability(List<String> path) async {
    if (path.length < 2) return 0.0;

    double minRatio = 1.0; // Le goulot d'étranglement
    double totalRatio = 0.0;
    int segments = 0;

    for (int i = 0; i < path.length - 1; i++) {
      final ratio = await _loadSegmentAvailability(path[i], path[i + 1]);
      minRatio = ratio < minRatio ? ratio : minRatio;
      totalRatio += ratio;
      segments++;
    }

    // Score combiné : privilégie le min (goulot) mais prend en compte la moyenne
    // Un chemin avec tous les segments à 80% est meilleur qu'un avec 100% et 20%
    final avgRatio = segments > 0 ? totalRatio / segments : 0.0;
    return minRatio * 0.7 + avgRatio * 0.3;
  }

  // Charge et trie les chemins par disponibilité
  Future<void> _loadAndSortPathsByAvailability() async {
    if (_foundPaths.isEmpty) return;

    setState(() => _isLoadingAvailability = true);
    _pathScores.clear();

    try {
      // Charger la disponibilité pour chaque chemin
      for (final path in _foundPaths) {
        final score = await _loadPathAvailability(path);
        _pathScores[path] = score;
      }

      // Trier par score de disponibilité (décroissant)
      setState(() {
        _foundPaths.sort((a, b) {
          final scoreA = _pathScores[a] ?? 0.0;
          final scoreB = _pathScores[b] ?? 0.0;
          return scoreB.compareTo(scoreA); // Décroissant
        });
        _selectedPathIndex = 0;
        _isLoadingAvailability = false;
      });
    } catch (e) {
      debugPrint('Error loading path availability: $e');
      setState(() => _isLoadingAvailability = false);
    }
  }

  List<List<String>> _findAllPaths(String start, String end, {int maxDepth = 5}) {
    final paths = <List<String>>[];
    final endCoord = _stationCoordinates[end];
    final startCoord = _stationCoordinates[start];

    if (endCoord == null || startCoord == null) return paths;

    // Vérifier connexion directe d'abord
    if (_graph[start]?.contains(end) == true) {
      paths.add([start, end]);
    }

    // A* : priority queue basée sur distance parcourue + heuristique
    // (distance, path)
    final queue = <(double, List<String>)>[(0.0, [start])];
    int explored = 0;
    const maxExplored = 1000;
    final visited = <String, double>{}; // Station -> meilleure distance pour y arriver

    while (queue.isNotEmpty && explored < maxExplored && paths.length < 5) {
      // Trier par score (distance parcourue + heuristique vers destination)
      queue.sort((a, b) => a.$1.compareTo(b.$1));

      final (currentScore, path) = queue.removeAt(0);
      final node = path.last;
      explored++;

      if (path.length > maxDepth) continue;

      // Calculer la distance parcourue jusqu'ici
      final distSoFar = _pathDistance(path);

      // Skip si on a déjà trouvé un meilleur chemin vers ce noeud
      if (visited.containsKey(node) && visited[node]! < distSoFar * 0.8) continue;
      visited[node] = distSoFar;

      final neighbors = _graph[node] ?? [];

      // Trier les voisins par distance vers la destination (heuristique)
      final sortedNeighbors = neighbors.where((n) => !path.contains(n)).toList();
      sortedNeighbors.sort((a, b) {
        final coordA = _stationCoordinates[a];
        final coordB = _stationCoordinates[b];
        if (coordA == null || coordB == null) return 0;
        final distA = _simpleDistance(coordA, endCoord);
        final distB = _simpleDistance(coordB, endCoord);
        return distA.compareTo(distB);
      });

      for (final neighbor in sortedNeighbors) {
        final neighborCoord = _stationCoordinates[neighbor];
        if (neighborCoord == null) continue;

        final newPath = [...path, neighbor];
        final newDist = _pathDistance(newPath);
        final heuristic = _simpleDistance(neighborCoord, endCoord);
        final score = newDist + heuristic * 0.5; // Pondérer l'heuristique

        if (neighbor == end) {
          // Éviter les doublons
          if (!paths.any((p) => p.join(',') == newPath.join(','))) {
            paths.add(newPath);
            if (paths.length >= 5) break;
          }
        } else if (newPath.length < maxDepth) {
          queue.add((score, newPath));
        }
      }
    }

    // Trier par distance totale (pas juste le nombre d'étapes)
    paths.sort((a, b) {
      final distA = _pathDistance(a);
      final distB = _pathDistance(b);
      return distA.compareTo(distB);
    });

    return paths.take(5).toList();
  }

  void _onStationTapInRouteMode(String station) {
    if (_originStation == null) {
      setState(() {
        _originStation = station;
        _destinationStation = null;
        _foundPaths = [];
        _pathScores.clear();
      });
    } else if (_destinationStation == null && station != _originStation) {
      setState(() {
        _destinationStation = station;
        _foundPaths = _findAllPaths(_originStation!, _destinationStation!);
        _selectedPathIndex = 0;
        _pathScores.clear();
      });
      // Si mode disponibilité, charger les scores
      if (_pathfindingMode == 'availability') {
        _loadAndSortPathsByAvailability();
      }
    } else {
      // Reset et recommencer
      setState(() {
        _originStation = station;
        _destinationStation = null;
        _foundPaths = [];
        _pathScores.clear();
      });
    }
  }

  void _clearRoute() {
    setState(() {
      _originStation = null;
      _destinationStation = null;
      _foundPaths = [];
      _selectedPathIndex = 0;
      _pathScores.clear();
      _segmentAvailability.clear();
    });
  }

  void _togglePathfindingMode() {
    setState(() {
      // Cycle: distance -> stops -> availability -> distance
      if (_pathfindingMode == 'distance') {
        _pathfindingMode = 'stops';
      } else if (_pathfindingMode == 'stops') {
        _pathfindingMode = 'availability';
      } else {
        _pathfindingMode = 'distance';
      }
      _pathScores.clear();
      _segmentAvailability.clear();
    });
    _sortPathsByCurrentMode();
  }

  void _sortPathsByCurrentMode() {
    if (_foundPaths.isEmpty) return;

    if (_pathfindingMode == 'availability') {
      _loadAndSortPathsByAvailability();
    } else if (_pathfindingMode == 'stops') {
      // Trier par nombre d'étapes (moins de correspondances = mieux)
      setState(() {
        _foundPaths.sort((a, b) => a.length.compareTo(b.length));
        _selectedPathIndex = 0;
      });
    } else {
      // Mode distance : trier par distance géographique
      setState(() {
        _foundPaths.sort((a, b) {
          final distA = _pathDistance(a);
          final distB = _pathDistance(b);
          return distA.compareTo(distB);
        });
        _selectedPathIndex = 0;
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFEF4444),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _segmentAvailability.clear();
        _pathScores.clear();
      });
      // Recharger la disponibilité si on a des chemins
      if (_pathfindingMode == 'availability' && _foundPaths.isNotEmpty) {
        _loadAndSortPathsByAvailability();
      }
    }
  }

  void _toggleRouteMode() {
    setState(() {
      _routeMode = !_routeMode;
      if (!_routeMode) {
        _clearRoute();
      }
      _selectedStation = null;
    });
  }

  Set<(String, String)> _getSelectedPathSegments() {
    if (_foundPaths.isEmpty || _selectedPathIndex >= _foundPaths.length) {
      return {};
    }
    final path = _foundPaths[_selectedPathIndex];
    final segments = <(String, String)>{};
    for (int i = 0; i < path.length - 1; i++) {
      segments.add((path[i], path[i + 1]));
      segments.add((path[i + 1], path[i])); // Bidirectionnel
    }
    return segments;
  }

  @override
  void dispose() {
    _zoomAnimationController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _animatedZoom(double targetZoom) {
    _zoomAnimationController?.dispose();

    final startZoom = _mapController.camera.zoom;
    final center = _mapController.camera.center;

    _zoomAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    final zoomTween = Tween<double>(begin: startZoom, end: targetZoom);
    final animation = CurvedAnimation(
      parent: _zoomAnimationController!,
      curve: Curves.easeOutCubic,
    );

    animation.addListener(() {
      _mapController.move(center, zoomTween.evaluate(animation));
    });

    _zoomAnimationController!.forward();
  }

  void _resetView() {
    _animatedZoom(5.5);
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < 12) {
      _animatedZoom(currentZoom + 1);
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom > 4) {
      _animatedZoom(currentZoom - 1);
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
            Expanded(child: _buildMap()),
            if (_routeMode) _buildRouteInfo(),
            if (_selectedStation != null && !_routeMode) _buildStationInfo(),
            _routeMode ? _buildRouteLegend() : _buildLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBackPressed,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                size: 20,
                color: _textSecondary,
              ),
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
                      PhosphorIcons.mapTrifold(PhosphorIconsStyle.fill),
                      size: 22,
                      color: _textPrimary,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Reseau TGV',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Segments de trains TGV Max',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _toggleRouteMode,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _routeMode ? _routeColor.withValues(alpha: 0.1) : _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _routeMode ? _routeColor : _borderColor),
              ),
              child: Icon(
                PhosphorIcons.path(PhosphorIconsStyle.regular),
                size: 20,
                color: _routeMode ? _routeColor : _textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _resetView,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                PhosphorIcons.arrowsOut(PhosphorIconsStyle.regular),
                size: 20,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _franceCenter,
          initialZoom: 5.5,
          minZoom: 4,
          maxZoom: 12,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.sncfmax.app',
            tileBuilder: _lightTileBuilder,
          ),
          PolylineLayer(
            polylines: _buildTrainSegments(),
          ),
          MarkerLayer(
            markers: _buildStationMarkers(),
          ),
        ],
      ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _zoomIn,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      size: 20,
                      color: _textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _zoomOut,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      PhosphorIcons.minus(PhosphorIconsStyle.bold),
                      size: 20,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Custom tile builder for lighter map style
  Widget _lightTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.95, 0, 0, 0, 10,
        0, 0.95, 0, 0, 10,
        0, 0, 0.95, 0, 10,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }

  List<Polyline> _buildTrainSegments() {
    final polylines = <Polyline>[];
    final pathSegments = _getSelectedPathSegments();
    final hasPath = pathSegments.isNotEmpty;

    for (final segment in _trainSegments) {
      final origin = _stationCoordinates[segment.$1];
      final destination = _stationCoordinates[segment.$2];

      if (origin == null || destination == null) continue;

      final isOnPath = pathSegments.contains((segment.$1, segment.$2));

      Color color;
      double strokeWidth;

      if (hasPath && isOnPath) {
        // Segment fait partie du chemin sélectionné
        color = _routeColor;
        strokeWidth = 6;
      } else if (hasPath) {
        // Autres segments en mode route (grisés)
        color = const Color(0xFFE2E8F0);
        strokeWidth = 2;
      } else {
        // Mode normal
        switch (segment.$3) {
          case 'lgv':
            color = const Color(0xFF3B82F6);
            strokeWidth = 4;
            break;
          case 'main':
            color = const Color(0xFF10B981);
            strokeWidth = 3;
            break;
          default:
            color = const Color(0xFF94A3B8);
            strokeWidth = 2;
        }
      }

      polylines.add(
        Polyline(
          points: [origin, destination],
          color: color.withValues(alpha: hasPath && !isOnPath ? 0.3 : 0.8),
          strokeWidth: strokeWidth,
          strokeCap: StrokeCap.round,
        ),
      );
    }

    // Ajouter le chemin en surbrillance à la fin pour qu'il soit au-dessus
    if (hasPath) {
      final path = _foundPaths[_selectedPathIndex];
      for (int i = 0; i < path.length - 1; i++) {
        final origin = _stationCoordinates[path[i]];
        final destination = _stationCoordinates[path[i + 1]];
        if (origin != null && destination != null) {
          polylines.add(
            Polyline(
              points: [origin, destination],
              color: _routeColor,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
            ),
          );
        }
      }
    }

    return polylines;
  }

  List<Marker> _buildStationMarkers() {
    final markers = <Marker>[];
    final pathStations = _foundPaths.isNotEmpty && _selectedPathIndex < _foundPaths.length
        ? _foundPaths[_selectedPathIndex].toSet()
        : <String>{};

    for (final entry in _stationCoordinates.entries) {
      final stationName = entry.key;
      final importance = _getStationImportance(stationName);
      final isSelected = stationName == _selectedStation;
      final isOrigin = stationName == _originStation;
      final isDestination = stationName == _destinationStation;
      final isOnPath = pathStations.contains(stationName);

      double size;
      Color markerColor;

      if (isOrigin) {
        size = 28;
        markerColor = _originColor;
      } else if (isDestination) {
        size = 28;
        markerColor = _destinationColor;
      } else if (isOnPath) {
        size = 20;
        markerColor = _routeColor;
      } else if (isSelected) {
        size = 28;
        markerColor = _accentColor;
      } else if (importance == 'major') {
        size = 20;
        markerColor = _routeMode && _foundPaths.isNotEmpty ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
      } else if (importance == 'medium') {
        size = 14;
        markerColor = _routeMode && _foundPaths.isNotEmpty ? const Color(0xFFE2E8F0) : const Color(0xFF64748B);
      } else {
        size = 10;
        markerColor = _routeMode && _foundPaths.isNotEmpty ? const Color(0xFFF1F5F9) : const Color(0xFF94A3B8);
      }

      markers.add(
        Marker(
          point: entry.value,
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () {
              if (_routeMode) {
                _onStationTapInRouteMode(stationName);
              } else {
                setState(() {
                  _selectedStation = stationName == _selectedStation ? null : stationName;
                });
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: markerColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: (isOrigin || isDestination || isSelected) ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  String _getStationImportance(String station) {
    const majorStations = [
      'PARIS', 'LYON', 'MARSEILLE ST CHARLES', 'LILLE', 'BORDEAUX ST JEAN',
      'TOULOUSE MATABIAU', 'NANTES', 'STRASBOURG', 'RENNES', 'NICE VILLE',
    ];

    const mediumStations = [
      'MONTPELLIER SAINT ROCH', 'AVIGNON TGV', 'AIX EN PROVENCE TGV',
      'DIJON VILLE', 'METZ VILLE', 'NANCY', 'MULHOUSE VILLE', 'BREST',
      'TOULON', 'ANGERS SAINT LAUD', 'LE MANS', 'POITIERS', 'TOURS',
      'CLERMONT FERRAND', 'LIMOGES BENEDICTINS', 'PERPIGNAN', 'BAYONNE',
      'LA ROCHELLE VILLE', 'GRENOBLE', 'NIMES CENTRE',
    ];

    if (majorStations.contains(station)) return 'major';
    if (mediumStations.contains(station)) return 'medium';
    return 'minor';
  }

  Widget _buildStationInfo() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              PhosphorIcons.train(PhosphorIconsStyle.fill),
              size: 20,
              color: _accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatStationName(_selectedStation!),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getStationConnections(_selectedStation!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _selectedStation = null),
            child: Icon(
              PhosphorIcons.x(PhosphorIconsStyle.regular),
              size: 20,
              color: _textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _formatStationName(String station) {
    return station
        .replaceAll(' ST CHARLES', ' St-Charles')
        .replaceAll(' ST JEAN', ' St-Jean')
        .replaceAll(' MATABIAU', '')
        .replaceAll(' SAINT LAUD', ' St-Laud')
        .replaceAll(' BENEDICTINS', '')
        .replaceAll(' SAINT ROCH', ' St-Roch')
        .replaceAll(' VILLE', '')
        .replaceAll(' (intramuros)', '')
        .replaceAll('AEROPORT ROISSY CDG 2 TGV', 'Roissy CDG TGV')
        .replaceAll('MARNE LA VALLEE CHESSY', 'Marne-la-Vallee')
        .replaceAll('VALENCE TGV AUVERGNE RHONE ALPES', 'Valence TGV');
  }

  String _getStationConnections(String station) {
    int count = 0;
    for (final segment in _trainSegments) {
      if (segment.$1 == station || segment.$2 == station) count++;
    }
    return '$count connexions directes';
  }

  Widget _buildLegend() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(const Color(0xFF3B82F6), 'LGV'),
          _buildLegendItem(const Color(0xFF10B981), 'Principales'),
          _buildLegendItem(const Color(0xFF94A3B8), 'Secondaires'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: _textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRouteInfo() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instructions ou état actuel
          if (_originStation == null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _originColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
                    size: 18,
                    color: _originColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Selectionnez une gare de depart',
                    style: TextStyle(
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_destinationStation == null) ...[
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _originColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatStationName(_originStation!),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _destinationColor.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                            border: Border.all(color: _destinationColor, width: 2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Selectionnez la destination...',
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearRoute,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _textMuted.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      PhosphorIcons.x(PhosphorIconsStyle.regular),
                      size: 18,
                      color: _textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Affichage des chemins trouvés
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _originColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatStationName(_originStation!),
                          style: const TextStyle(
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
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _destinationColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatStationName(_destinationStation!),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearRoute,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _textMuted.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      PhosphorIcons.x(PhosphorIconsStyle.regular),
                      size: 18,
                      color: _textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mode selector et date picker
            Row(
              children: [
                // Toggle distance / stops / disponibilité
                GestureDetector(
                  onTap: _togglePathfindingMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _pathfindingMode == 'distance'
                          ? _accentColor.withValues(alpha: 0.1)
                          : _pathfindingMode == 'stops'
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.1)
                              : _originColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _pathfindingMode == 'distance'
                            ? _accentColor
                            : _pathfindingMode == 'stops'
                                ? const Color(0xFF3B82F6)
                                : _originColor,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _pathfindingMode == 'distance'
                              ? PhosphorIcons.mapTrifold(PhosphorIconsStyle.fill)
                              : _pathfindingMode == 'stops'
                                  ? PhosphorIcons.trainSimple(PhosphorIconsStyle.fill)
                                  : PhosphorIcons.ticket(PhosphorIconsStyle.fill),
                          size: 14,
                          color: _pathfindingMode == 'distance'
                              ? _accentColor
                              : _pathfindingMode == 'stops'
                                  ? const Color(0xFF3B82F6)
                                  : _originColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _pathfindingMode == 'distance'
                              ? 'Distance'
                              : _pathfindingMode == 'stops'
                                  ? 'Direct'
                                  : 'Dispos',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _pathfindingMode == 'distance'
                                ? _accentColor
                                : _pathfindingMode == 'stops'
                                    ? const Color(0xFF3B82F6)
                                    : _originColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Date picker (visible seulement en mode disponibilité)
                if (_pathfindingMode == 'availability') ...[
                  GestureDetector(
                    onTap: _selectDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.calendar(PhosphorIconsStyle.fill),
                            size: 14,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_selectedDate.day}/${_selectedDate.month}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Indicateur de chargement
                if (_isLoadingAvailability) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _originColor,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Liste des chemins
            if (_foundPaths.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIcons.warning(PhosphorIconsStyle.fill),
                      size: 18,
                      color: _routeColor,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Aucun itineraire trouve',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                '${_foundPaths.length} itineraire${_foundPaths.length > 1 ? 's' : ''} trouve${_foundPaths.length > 1 ? 's' : ''}'
                '${_pathfindingMode == 'availability' ? ' (par dispo)' : _pathfindingMode == 'stops' ? ' (moins de gares)' : ' (par distance)'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 95,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _foundPaths.length,
                  itemBuilder: (context, index) {
                    final path = _foundPaths[index];
                    final isSelected = index == _selectedPathIndex;
                    final score = _pathScores[path];
                    final hasScore = score != null && _pathfindingMode == 'availability';

                    // Couleur basée sur le score de disponibilité
                    Color scoreColor = _textMuted;
                    if (hasScore) {
                      if (score > 0.5) {
                        scoreColor = _originColor;
                      } else if (score > 0.2) {
                        scoreColor = const Color(0xFFF59E0B); // Orange
                      } else {
                        scoreColor = _routeColor;
                      }
                    }

                    return GestureDetector(
                      onTap: () => setState(() => _selectedPathIndex = index),
                      child: Container(
                        margin: EdgeInsets.only(right: index < _foundPaths.length - 1 ? 8 : 0),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected ? _routeColor.withValues(alpha: 0.1) : _backgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? _routeColor : _borderColor,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Route ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? _routeColor : _textSecondary,
                                  ),
                                ),
                                if (hasScore) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: scoreColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${(score * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: scoreColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${path.length - 1} etape${path.length > 2 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected ? _routeColor : _textMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: 120,
                              child: Text(
                                path.map((s) => _formatStationName(s).split(' ').first).join(' > '),
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: _textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRouteLegend() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRouteLegendItem(_originColor, 'Depart'),
          _buildRouteLegendItem(_destinationColor, 'Arrivee'),
          _buildRouteLegendItem(_routeColor, 'Itineraire'),
        ],
      ),
    );
  }

  Widget _buildRouteLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: _textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// Station coordinates (LatLng)
final Map<String, LatLng> _stationCoordinates = {
  // Ile-de-France
  'PARIS': const LatLng(48.8566, 2.3522),
  'MARNE LA VALLEE CHESSY': const LatLng(48.8722, 2.7833),
  'AEROPORT ROISSY CDG 2 TGV': const LatLng(49.0047, 2.5714),
  'MASSY TGV': const LatLng(48.7253, 2.2608),
  'MASSY PALAISEAU': const LatLng(48.7253, 2.2573),
  'VERSAILLES CHANTIERS': const LatLng(48.7958, 2.1344),
  'MANTES LA JOLIE': const LatLng(48.9908, 1.7119),

  // Nord / Hauts-de-France
  'LILLE': const LatLng(50.6292, 3.0573),
  'TGV HAUTE PICARDIE': const LatLng(49.8589, 2.8306),
  'ARRAS': const LatLng(50.2871, 2.7803),
  'LENS': const LatLng(50.4289, 2.8281),
  'DOUAI': const LatLng(50.3717, 3.0900),
  'VALENCIENNES': const LatLng(50.3656, 3.5331),
  'BETHUNE': const LatLng(50.5297, 2.6408),
  'CALAIS VILLE': const LatLng(50.9517, 1.8581),
  'CALAIS FRETHUN': const LatLng(50.9022, 1.8117),
  'BOULOGNE VILLE': const LatLng(50.7264, 1.6139),
  'DUNKERQUE': const LatLng(51.0344, 2.3769),
  'ETAPLES   LE TOUQUET': const LatLng(50.5172, 1.6453),
  'RANG DU FLIERS VERTON BERCK': const LatLng(50.4081, 1.6178),
  'HAZEBROUCK': const LatLng(50.7264, 2.5383),
  'CROIX WASQUEHAL': const LatLng(50.6789, 3.1478),
  'ROUBAIX': const LatLng(50.6942, 3.1747),
  'TOURCOING': const LatLng(50.7239, 3.1608),

  // Normandie
  'ROUEN RIVE DROITE': const LatLng(49.4489, 1.0936),
  'LE HAVRE': const LatLng(49.4944, 0.1253),

  // Champagne-Ardenne
  'REIMS': const LatLng(49.2583, 4.0242),
  'CHAMPAGNE ARDENNE TGV': const LatLng(49.2150, 4.0319),
  'CHALONS EN CHAMPAGNE': const LatLng(48.9567, 4.3631),
  'CHARLEVILLE MEZIERES': const LatLng(49.7628, 4.7167),
  'RETHEL': const LatLng(49.5092, 4.3678),
  'SEDAN': const LatLng(49.7019, 4.9403),
  'VITRY LE FRANCOIS': const LatLng(48.7250, 4.5847),

  // Lorraine
  'METZ VILLE': const LatLng(49.1097, 6.1764),
  'NANCY': const LatLng(48.6921, 6.1844),
  'MEUSE TGV': const LatLng(48.9747, 5.2714),
  'LORRAINE TGV': const LatLng(48.9522, 6.1681),
  'THIONVILLE': const LatLng(49.3572, 6.1681),
  'EPINAL': const LatLng(48.1728, 6.4531),
  'REMIREMONT': const LatLng(48.0169, 6.5914),
  'BAR LE DUC': const LatLng(48.7736, 5.1597),
  'LUNEVILLE': const LatLng(48.5933, 6.4917),
  'ST DIE': const LatLng(48.2872, 6.9500),

  // Alsace
  'STRASBOURG': const LatLng(48.5734, 7.7521),
  'MULHOUSE VILLE': const LatLng(47.7421, 7.3421),
  'COLMAR': const LatLng(48.0778, 7.3539),
  'SELESTAT': const LatLng(48.2606, 7.4536),
  'SAVERNE': const LatLng(48.7417, 7.3644),
  'SARREBOURG': const LatLng(48.7344, 7.0531),

  // Franche-Comté
  'BELFORT MONTBELIARD TGV': const LatLng(47.5861, 6.8536),
  'BESANCON FRANCHE COMTE TGV': const LatLng(47.3067, 5.9533),
  'BESANCON VIOTTE': const LatLng(47.2467, 6.0219),
  'DOLE VILLE': const LatLng(47.0950, 5.4903),
  'FRASNE': const LatLng(46.8564, 6.1581),
  'MOUCHARD': const LatLng(46.9756, 5.7958),

  // Bourgogne
  'DIJON VILLE': const LatLng(47.3236, 5.0275),
  'MACON VILLE': const LatLng(46.3064, 4.8283),
  'MACON LOCHE TGV': const LatLng(46.2733, 4.7892),
  'CHALON SUR SAONE': const LatLng(46.7806, 4.8536),
  'BEAUNE': const LatLng(47.0261, 4.8400),
  'LE CREUSOT MONTCEAU MONTCHANIN': const LatLng(46.7667, 4.4333),
  'MONTBARD': const LatLng(47.6228, 4.3394),

  // Rhône-Alpes
  'LYON': const LatLng(45.7578, 4.8320),
  'LYON ST EXUPERY TGV': const LatLng(45.7206, 5.0778),
  'VALENCE TGV AUVERGNE RHONE ALPES': const LatLng(44.9833, 4.9697),
  'VALENCE VILLE': const LatLng(44.9258, 4.8928),
  'GRENOBLE': const LatLng(45.1885, 5.7245),
  'SAINT ETIENNE CHATEAUCREUX': const LatLng(45.4433, 4.3997),
  'BOURG EN BRESSE': const LatLng(46.2003, 5.2128),
  'NURIEUX GARE': const LatLng(46.1539, 5.5500),

  // Savoie / Haute-Savoie
  'CHAMBERY CHALLES LES EAUX': const LatLng(45.5710, 5.9175),
  'ANNECY': const LatLng(45.9009, 6.1296),
  'AIX LES BAINS LE REVARD': const LatLng(45.6889, 5.9092),
  'ALBERTVILLE': const LatLng(45.6756, 6.3928),
  'MOUTIERS SALINS BRIDES LES BAINS': const LatLng(45.4856, 6.5286),
  'AIME LA PLAGNE': const LatLng(45.5553, 6.6511),
  'BOURG SAINT MAURICE': const LatLng(45.6183, 6.7697),
  'LANDRY': const LatLng(45.5697, 6.7322),
  'MODANE': const LatLng(45.1947, 6.6583),
  'ST JEAN DE MAURIENNE ARVAN': const LatLng(45.2750, 6.3472),
  'SAINT AVRE LA CHAMBRE': const LatLng(45.3069, 6.2961),
  'ST MICHEL VALLOIRE': const LatLng(45.2222, 6.4697),
  'ANNEMASSE': const LatLng(46.1933, 6.2356),
  'THONON LES BAINS': const LatLng(46.3708, 6.4794),
  'EVIAN LES BAINS': const LatLng(46.4006, 6.5881),
  'CLUSES (HAUTE SAVOIE)': const LatLng(46.0606, 6.5792),
  'SALLANCHES COMBLOUX MEGEVE': const LatLng(45.9361, 6.6311),
  'ST GERVAIS LES BAINS LE FAYET': const LatLng(45.9075, 6.7100),
  'BELLEGARDE SUR VALSERINE GARE': const LatLng(46.1089, 5.8267),

  // Alpes du Sud
  'BRIANCON': const LatLng(44.8958, 6.6344),
  'GAP': const LatLng(44.5594, 6.0764),
  'EMBRUN': const LatLng(44.5639, 6.4958),
  'MONTDAUPHIN GUILLESTRE': const LatLng(44.6656, 6.6044),
  'CHORGES': const LatLng(44.5478, 6.2783),
  'L\'ARGENTIERE LES ECRINS': const LatLng(44.7903, 6.5597),
  'VEYNES DEVOLUY': const LatLng(44.5333, 5.8167),
  'DIE': const LatLng(44.7522, 5.3711),
  'CREST': const LatLng(44.7286, 5.0231),

  // PACA
  'MARSEILLE ST CHARLES': const LatLng(43.3026, 5.3806),
  'MARSEILLE BLANCARDE': const LatLng(43.2964, 5.4042),
  'AIX EN PROVENCE TGV': const LatLng(43.4553, 5.3175),
  'AVIGNON TGV': const LatLng(43.9217, 4.7861),
  'AVIGNON CENTRE': const LatLng(43.9419, 4.8058),
  'NIMES CENTRE': const LatLng(43.8328, 4.3600),
  'NIMES PONT DU GARD': const LatLng(43.8883, 4.5372),
  'ARLES': const LatLng(43.6828, 4.6306),
  'MIRAMAS': const LatLng(43.5836, 5.0011),
  'ORANGE': const LatLng(44.1378, 4.8106),
  'MONTELIMAR GARE SNCF': const LatLng(44.5583, 4.7500),
  'TOULON': const LatLng(43.1258, 5.9308),
  'HYERES': const LatLng(43.1167, 6.1261),
  'NICE VILLE': const LatLng(43.7044, 7.2619),
  'CANNES': const LatLng(43.5513, 7.0128),
  'ANTIBES': const LatLng(43.5808, 7.1239),
  'ST RAPHAEL VALESCURE': const LatLng(43.4253, 6.7678),
  'LES ARCS DRAGUIGNAN': const LatLng(43.4647, 6.4758),

  // Languedoc
  'MONTPELLIER SAINT ROCH': const LatLng(43.6047, 3.8794),
  'MONTPELLIER SUD DE FRANCE': const LatLng(43.5722, 3.9247),
  'BEZIERS': const LatLng(43.3442, 3.2158),
  'NARBONNE': const LatLng(43.1833, 3.0042),
  'CARCASSONNE': const LatLng(43.2130, 2.3491),
  'SETE': const LatLng(43.4075, 3.6967),
  'AGDE': const LatLng(43.3108, 3.4758),

  // Catalogne / Pyrénées-Orientales
  'PERPIGNAN': const LatLng(42.6986, 2.8954),
  'ARGELES SUR MER': const LatLng(42.5458, 3.0239),
  'COLLIOURE': const LatLng(42.5256, 3.0831),
  'PORT VENDRES VILLE': const LatLng(42.5178, 3.1053),
  'BANYULS SUR MER': const LatLng(42.4806, 3.1286),
  'CERBERE': const LatLng(42.4428, 3.1656),
  'ELNE': const LatLng(42.6000, 2.9711),

  // Midi-Pyrénées / Occitanie
  'TOULOUSE MATABIAU': const LatLng(43.6111, 1.4536),
  'MONTAUBAN VILLE BOURBON': const LatLng(44.0175, 1.3547),
  'CAUSSADE(TARN ET GARONNE)': const LatLng(44.1611, 1.5386),

  // Aquitaine / Nouvelle-Aquitaine
  'BORDEAUX ST JEAN': const LatLng(44.8258, -0.5558),
  'AGEN': const LatLng(44.2033, 0.6206),
  'MARMANDE': const LatLng(44.5000, 0.1653),
  'LIBOURNE': const LatLng(44.9136, -0.2406),
  'ARCACHON': const LatLng(44.6617, -1.1681),
  'LA TESTE': const LatLng(44.6331, -1.1419),
  'BIGANOS FACTURE': const LatLng(44.6369, -0.9747),
  'BAYONNE': const LatLng(43.4929, -1.4748),
  'BIARRITZ': const LatLng(43.4689, -1.5547),
  'ST JEAN DE LUZ CIBOURE': const LatLng(43.3847, -1.6594),
  'HENDAYE': const LatLng(43.3581, -1.7744),
  'DAX': const LatLng(43.7106, -1.0536),
  'ST VINCENT DE TYROSSE': const LatLng(43.6658, -1.2117),
  'PAU': const LatLng(43.2951, -0.3708),
  'TARBES': const LatLng(43.2328, 0.0781),
  'LOURDES': const LatLng(43.0950, -0.0464),
  'ORTHEZ': const LatLng(43.4906, -0.7694),

  // Limousin / Auvergne
  'LIMOGES BENEDICTINS': const LatLng(45.8361, 1.2644),
  'BRIVE LA GAILLARDE': const LatLng(45.1589, 1.5333),
  'UZERCHE': const LatLng(45.4250, 1.5625),
  'AURILLAC': const LatLng(44.9306, 2.4400),
  'BRETENOUX BIARS': const LatLng(44.9133, 1.8386),
  'LAROQUEBROU BATIMENT VOYAGEURS': const LatLng(44.9667, 2.1903),
  'ST DENIS PRES MARTEL': const LatLng(44.9333, 1.6667),

  // Centre-Ouest
  'LA ROCHELLE VILLE': const LatLng(46.1528, -1.1428),
  'SURGERES': const LatLng(46.1067, -0.7533),
  'NIORT': const LatLng(46.3217, -0.4639),
  'POITIERS': const LatLng(46.5833, 0.3333),
  'FUTUROSCOPE': const LatLng(46.6697, 0.3683),
  'CHATELLERAULT': const LatLng(46.8172, 0.5456),
  'ANGOULEME': const LatLng(45.6500, 0.1500),
  'CAHORS': const LatLng(44.4492, 1.4403),
  'SOUILLAC': const LatLng(44.8964, 1.4789),
  'GOURDON': const LatLng(44.7361, 1.3833),

  // Centre / Val de Loire
  'TOURS': const LatLng(47.3900, 0.6889),
  'ST PIERRE DES CORPS': const LatLng(47.3847, 0.7267),
  'VENDOME VILLIERS SUR LOIR': const LatLng(47.8167, 1.0167),
  'LES AUBRAIS ORLEANS': const LatLng(47.9286, 1.9069),
  'VIERZON': const LatLng(47.2228, 2.0686),
  'CHATEAUROUX': const LatLng(46.8103, 1.6911),
  'ISSOUDUN': const LatLng(46.9489, 1.9936),
  'ARGENTON SUR CREUSE': const LatLng(46.5897, 1.5208),
  'LA SOUTERRAINE': const LatLng(46.2369, 1.4869),
  'ST MAIXENT (DEUX SEVRES)': const LatLng(46.4133, -0.2083),
  'SABLE SUR SARTHE': const LatLng(47.8397, -0.3347),
  'SAINCAIZE': const LatLng(46.9333, 3.0667),

  // Auvergne
  'CLERMONT FERRAND': const LatLng(45.7772, 3.0870),
  'NEVERS': const LatLng(46.9893, 3.1600),
  'MOULINS SUR ALLIER': const LatLng(46.5639, 3.3333),
  'VICHY': const LatLng(46.1263, 3.4254),
  'RIOM CHATEL GUYON': const LatLng(45.8939, 3.1139),
  'SAINT GERMAIN DES FOSSES': const LatLng(46.2086, 3.4317),

  // Bretagne
  'RENNES': const LatLng(48.1036, -1.6722),
  'ST BRIEUC': const LatLng(48.5136, -2.7606),
  'GUINGAMP': const LatLng(48.5617, -3.1508),
  'PLOUARET TREGOR': const LatLng(48.6167, -3.4667),
  'LANNION': const LatLng(48.7333, -3.4597),
  'MORLAIX': const LatLng(48.5781, -3.8278),
  'LANDERNEAU': const LatLng(48.4500, -4.2500),
  'BREST': const LatLng(48.3878, -4.4861),
  'QUIMPER': const LatLng(47.9964, -4.0972),
  'ROSPORDEN': const LatLng(47.9681, -3.8317),
  'QUIMPERLE': const LatLng(47.8739, -3.5486),
  'LORIENT': const LatLng(47.7461, -3.3617),
  'VANNES': const LatLng(47.6558, -2.7600),
  'AURAY': const LatLng(47.6669, -2.9828),
  'REDON': const LatLng(47.6500, -2.0833),
  'DOL DE BRETAGNE': const LatLng(48.5500, -1.7500),
  'ST MALO': const LatLng(48.6500, -2.0000),
  'LAMBALLE': const LatLng(48.4694, -2.5167),
  'VITRE': const LatLng(48.1206, -1.2103),

  // Pays de la Loire
  'NANTES': const LatLng(47.2173, -1.5534),
  'ST NAZAIRE': const LatLng(47.2833, -2.2000),
  'LA BAULE ESCOUBLAC': const LatLng(47.2833, -2.3833),
  'LE CROISIC': const LatLng(47.2917, -2.5083),
  'LE POULIGUEN': const LatLng(47.2742, -2.4292),
  'PORNICHET': const LatLng(47.2644, -2.3381),
  'ANGERS SAINT LAUD': const LatLng(47.4642, -0.5567),
  'ANCENIS': const LatLng(47.3667, -1.1833),
  'LE MANS': const LatLng(48.0061, 0.1928),
  'LAVAL': const LatLng(48.0747, -0.7706),
  'SAUMUR': const LatLng(47.2600, -0.0767),
  'LA ROCHE SUR YON': const LatLng(46.6706, -1.4269),
  'LES SABLES D\'OLONNE': const LatLng(46.4972, -1.7856),

  // International
  'BRUXELLES MIDI': const LatLng(50.8358, 4.3367),
  'LUXEMBOURG': const LatLng(49.6000, 6.1333),
  'FREIBURG (BREISGAU) HBF': const LatLng(47.9972, 7.8414),
  'OFFENBURG': const LatLng(48.4728, 7.9444),
  'LAHR SCHWARZW': const LatLng(48.3381, 7.8722),
  'RINGSHEIM EUROPA PARK': const LatLng(48.2597, 7.7108),
};

// Train segments (origin, destination, type: 'lgv', 'main', 'secondary')
final List<(String, String, String)> _trainSegments = [
  // ============ LGV NORD ============
  ('PARIS', 'LILLE', 'lgv'),
  ('PARIS', 'TGV HAUTE PICARDIE', 'lgv'),
  ('TGV HAUTE PICARDIE', 'LILLE', 'lgv'),
  ('LILLE', 'BRUXELLES MIDI', 'lgv'),

  // Nord - Lignes classiques
  ('LILLE', 'ARRAS', 'main'),
  ('ARRAS', 'LENS', 'secondary'),
  ('LENS', 'BETHUNE', 'secondary'),
  ('LILLE', 'DOUAI', 'main'),
  ('DOUAI', 'VALENCIENNES', 'main'),
  ('LILLE', 'ROUBAIX', 'secondary'),
  ('ROUBAIX', 'TOURCOING', 'secondary'),
  ('LILLE', 'CROIX WASQUEHAL', 'secondary'),
  ('LILLE', 'HAZEBROUCK', 'main'),
  ('HAZEBROUCK', 'DUNKERQUE', 'main'),
  ('HAZEBROUCK', 'CALAIS VILLE', 'main'),
  ('CALAIS VILLE', 'CALAIS FRETHUN', 'secondary'),
  ('CALAIS VILLE', 'BOULOGNE VILLE', 'main'),
  ('BOULOGNE VILLE', 'ETAPLES   LE TOUQUET', 'secondary'),
  ('ETAPLES   LE TOUQUET', 'RANG DU FLIERS VERTON BERCK', 'secondary'),

  // ============ NORMANDIE ============
  ('PARIS', 'MANTES LA JOLIE', 'main'),
  ('MANTES LA JOLIE', 'ROUEN RIVE DROITE', 'main'),
  ('ROUEN RIVE DROITE', 'LE HAVRE', 'main'),

  // ============ LGV EST ============
  ('PARIS', 'CHAMPAGNE ARDENNE TGV', 'lgv'),
  ('CHAMPAGNE ARDENNE TGV', 'MEUSE TGV', 'lgv'),
  ('MEUSE TGV', 'LORRAINE TGV', 'lgv'),
  ('LORRAINE TGV', 'STRASBOURG', 'lgv'),

  // Champagne-Ardenne classique
  ('CHAMPAGNE ARDENNE TGV', 'REIMS', 'main'),
  ('REIMS', 'RETHEL', 'secondary'),
  ('RETHEL', 'CHARLEVILLE MEZIERES', 'secondary'),
  ('CHARLEVILLE MEZIERES', 'SEDAN', 'secondary'),
  ('REIMS', 'CHALONS EN CHAMPAGNE', 'main'),
  ('CHALONS EN CHAMPAGNE', 'VITRY LE FRANCOIS', 'secondary'),
  ('MEUSE TGV', 'BAR LE DUC', 'secondary'),

  // Lorraine classique
  ('LORRAINE TGV', 'METZ VILLE', 'main'),
  ('METZ VILLE', 'NANCY', 'main'),
  ('METZ VILLE', 'THIONVILLE', 'main'),
  ('THIONVILLE', 'LUXEMBOURG', 'main'),
  ('NANCY', 'LUNEVILLE', 'secondary'),
  ('LUNEVILLE', 'ST DIE', 'secondary'),
  ('NANCY', 'EPINAL', 'main'),
  ('EPINAL', 'REMIREMONT', 'secondary'),

  // Alsace
  ('STRASBOURG', 'SAVERNE', 'main'),
  ('SAVERNE', 'SARREBOURG', 'main'),
  ('STRASBOURG', 'SELESTAT', 'main'),
  ('SELESTAT', 'COLMAR', 'main'),
  ('COLMAR', 'MULHOUSE VILLE', 'main'),
  ('MULHOUSE VILLE', 'BELFORT MONTBELIARD TGV', 'main'),
  ('BELFORT MONTBELIARD TGV', 'BESANCON FRANCHE COMTE TGV', 'lgv'),
  ('BESANCON FRANCHE COMTE TGV', 'DIJON VILLE', 'lgv'),

  // Allemagne (via Strasbourg)
  ('STRASBOURG', 'OFFENBURG', 'main'),
  ('OFFENBURG', 'LAHR SCHWARZW', 'secondary'),
  ('LAHR SCHWARZW', 'RINGSHEIM EUROPA PARK', 'secondary'),
  ('RINGSHEIM EUROPA PARK', 'FREIBURG (BREISGAU) HBF', 'secondary'),

  // ============ FRANCHE-COMTE ============
  ('BESANCON FRANCHE COMTE TGV', 'BESANCON VIOTTE', 'secondary'),
  ('BESANCON VIOTTE', 'MOUCHARD', 'secondary'),
  ('MOUCHARD', 'DOLE VILLE', 'secondary'),
  ('DOLE VILLE', 'DIJON VILLE', 'main'),
  ('MOUCHARD', 'FRASNE', 'secondary'),

  // ============ LGV SUD-EST ============
  ('PARIS', 'MASSY TGV', 'lgv'),
  ('PARIS', 'LYON', 'lgv'),
  ('MASSY TGV', 'LYON', 'lgv'),
  ('LYON', 'LYON ST EXUPERY TGV', 'lgv'),

  // ============ BOURGOGNE ============
  ('PARIS', 'DIJON VILLE', 'main'),
  ('PARIS', 'MONTBARD', 'main'),
  ('MONTBARD', 'DIJON VILLE', 'main'),
  ('DIJON VILLE', 'BEAUNE', 'main'),
  ('BEAUNE', 'CHALON SUR SAONE', 'main'),
  ('CHALON SUR SAONE', 'LE CREUSOT MONTCEAU MONTCHANIN', 'secondary'),
  ('CHALON SUR SAONE', 'MACON VILLE', 'main'),
  ('MACON VILLE', 'LYON', 'main'),
  ('MACON LOCHE TGV', 'LYON', 'lgv'),
  ('MACON LOCHE TGV', 'MACON VILLE', 'secondary'),

  // ============ RHONE-ALPES ============
  ('LYON', 'VALENCE TGV AUVERGNE RHONE ALPES', 'lgv'),
  ('VALENCE TGV AUVERGNE RHONE ALPES', 'VALENCE VILLE', 'secondary'),
  ('LYON', 'SAINT ETIENNE CHATEAUCREUX', 'main'),
  ('LYON', 'BOURG EN BRESSE', 'main'),
  ('BOURG EN BRESSE', 'NURIEUX GARE', 'secondary'),
  ('LYON', 'GRENOBLE', 'main'),
  ('LYON', 'CHAMBERY CHALLES LES EAUX', 'main'),

  // Savoie - Ligne de la Tarentaise
  ('CHAMBERY CHALLES LES EAUX', 'AIX LES BAINS LE REVARD', 'main'),
  ('AIX LES BAINS LE REVARD', 'ANNECY', 'main'),
  ('CHAMBERY CHALLES LES EAUX', 'ALBERTVILLE', 'main'),
  ('ALBERTVILLE', 'MOUTIERS SALINS BRIDES LES BAINS', 'main'),
  ('MOUTIERS SALINS BRIDES LES BAINS', 'AIME LA PLAGNE', 'secondary'),
  ('AIME LA PLAGNE', 'LANDRY', 'secondary'),
  ('LANDRY', 'BOURG SAINT MAURICE', 'secondary'),

  // Savoie - Ligne de la Maurienne
  ('CHAMBERY CHALLES LES EAUX', 'SAINT AVRE LA CHAMBRE', 'main'),
  ('SAINT AVRE LA CHAMBRE', 'ST JEAN DE MAURIENNE ARVAN', 'main'),
  ('ST JEAN DE MAURIENNE ARVAN', 'ST MICHEL VALLOIRE', 'secondary'),
  ('ST MICHEL VALLOIRE', 'MODANE', 'main'),

  // Haute-Savoie
  ('ANNECY', 'ANNEMASSE', 'main'),
  ('ANNEMASSE', 'THONON LES BAINS', 'main'),
  ('THONON LES BAINS', 'EVIAN LES BAINS', 'secondary'),
  ('ANNEMASSE', 'CLUSES (HAUTE SAVOIE)', 'main'),
  ('CLUSES (HAUTE SAVOIE)', 'SALLANCHES COMBLOUX MEGEVE', 'secondary'),
  ('SALLANCHES COMBLOUX MEGEVE', 'ST GERVAIS LES BAINS LE FAYET', 'secondary'),
  ('LYON', 'BELLEGARDE SUR VALSERINE GARE', 'main'),
  ('BELLEGARDE SUR VALSERINE GARE', 'ANNEMASSE', 'main'),

  // ============ ALPES DU SUD ============
  ('GRENOBLE', 'VEYNES DEVOLUY', 'secondary'),
  ('VEYNES DEVOLUY', 'GAP', 'secondary'),
  ('GAP', 'CHORGES', 'secondary'),
  ('CHORGES', 'EMBRUN', 'secondary'),
  ('EMBRUN', 'MONTDAUPHIN GUILLESTRE', 'secondary'),
  ('MONTDAUPHIN GUILLESTRE', 'L\'ARGENTIERE LES ECRINS', 'secondary'),
  ('L\'ARGENTIERE LES ECRINS', 'BRIANCON', 'secondary'),
  ('VALENCE VILLE', 'CREST', 'secondary'),
  ('CREST', 'DIE', 'secondary'),
  ('DIE', 'VEYNES DEVOLUY', 'secondary'),

  // ============ LGV MEDITERRANEE ============
  ('VALENCE TGV AUVERGNE RHONE ALPES', 'AVIGNON TGV', 'lgv'),
  ('AVIGNON TGV', 'AIX EN PROVENCE TGV', 'lgv'),
  ('AIX EN PROVENCE TGV', 'MARSEILLE ST CHARLES', 'lgv'),
  ('AVIGNON TGV', 'NIMES PONT DU GARD', 'lgv'),
  ('NIMES PONT DU GARD', 'MONTPELLIER SUD DE FRANCE', 'lgv'),

  // PACA classique
  ('AVIGNON TGV', 'AVIGNON CENTRE', 'secondary'),
  ('AVIGNON CENTRE', 'NIMES CENTRE', 'main'),
  ('AVIGNON CENTRE', 'ORANGE', 'main'),
  ('ORANGE', 'MONTELIMAR GARE SNCF', 'main'),
  ('MONTELIMAR GARE SNCF', 'VALENCE VILLE', 'main'),
  ('AVIGNON CENTRE', 'ARLES', 'main'),
  ('ARLES', 'MIRAMAS', 'secondary'),
  ('MIRAMAS', 'MARSEILLE ST CHARLES', 'secondary'),
  ('MARSEILLE ST CHARLES', 'MARSEILLE BLANCARDE', 'secondary'),
  ('MARSEILLE ST CHARLES', 'TOULON', 'main'),
  ('TOULON', 'HYERES', 'secondary'),
  ('TOULON', 'LES ARCS DRAGUIGNAN', 'main'),
  ('LES ARCS DRAGUIGNAN', 'ST RAPHAEL VALESCURE', 'main'),
  ('ST RAPHAEL VALESCURE', 'CANNES', 'main'),
  ('CANNES', 'ANTIBES', 'main'),
  ('ANTIBES', 'NICE VILLE', 'main'),
  ('NIMES CENTRE', 'MONTPELLIER SAINT ROCH', 'main'),
  ('MONTPELLIER SAINT ROCH', 'MONTPELLIER SUD DE FRANCE', 'secondary'),

  // ============ LANGUEDOC ============
  ('MONTPELLIER SAINT ROCH', 'SETE', 'main'),
  ('SETE', 'AGDE', 'main'),
  ('AGDE', 'BEZIERS', 'main'),
  ('BEZIERS', 'NARBONNE', 'main'),
  ('NARBONNE', 'PERPIGNAN', 'main'),
  ('NARBONNE', 'CARCASSONNE', 'main'),
  ('CARCASSONNE', 'TOULOUSE MATABIAU', 'main'),

  // Catalogne / Côte Vermeille
  ('PERPIGNAN', 'ELNE', 'secondary'),
  ('ELNE', 'ARGELES SUR MER', 'secondary'),
  ('ARGELES SUR MER', 'COLLIOURE', 'secondary'),
  ('COLLIOURE', 'PORT VENDRES VILLE', 'secondary'),
  ('PORT VENDRES VILLE', 'BANYULS SUR MER', 'secondary'),
  ('BANYULS SUR MER', 'CERBERE', 'secondary'),

  // ============ LGV ATLANTIQUE ============
  ('PARIS', 'LE MANS', 'lgv'),
  ('LE MANS', 'RENNES', 'lgv'),
  ('LE MANS', 'NANTES', 'lgv'),
  ('LE MANS', 'ANGERS SAINT LAUD', 'lgv'),
  ('ANGERS SAINT LAUD', 'NANTES', 'lgv'),
  ('PARIS', 'ST PIERRE DES CORPS', 'lgv'),
  ('PARIS', 'VENDOME VILLIERS SUR LOIR', 'lgv'),
  ('VENDOME VILLIERS SUR LOIR', 'ST PIERRE DES CORPS', 'lgv'),
  ('ST PIERRE DES CORPS', 'TOURS', 'secondary'),
  ('ST PIERRE DES CORPS', 'POITIERS', 'lgv'),
  ('POITIERS', 'ANGOULEME', 'lgv'),
  ('ANGOULEME', 'BORDEAUX ST JEAN', 'lgv'),

  // ============ BRETAGNE ============
  ('RENNES', 'ST BRIEUC', 'main'),
  ('ST BRIEUC', 'LAMBALLE', 'secondary'),
  ('LAMBALLE', 'RENNES', 'secondary'),
  ('ST BRIEUC', 'GUINGAMP', 'main'),
  ('GUINGAMP', 'PLOUARET TREGOR', 'secondary'),
  ('PLOUARET TREGOR', 'LANNION', 'secondary'),
  ('GUINGAMP', 'MORLAIX', 'main'),
  ('MORLAIX', 'LANDERNEAU', 'main'),
  ('LANDERNEAU', 'BREST', 'main'),
  ('RENNES', 'VANNES', 'main'),
  ('VANNES', 'AURAY', 'main'),
  ('AURAY', 'LORIENT', 'main'),
  ('LORIENT', 'QUIMPERLE', 'main'),
  ('QUIMPERLE', 'ROSPORDEN', 'main'),
  ('ROSPORDEN', 'QUIMPER', 'main'),
  ('RENNES', 'VITRE', 'main'),
  ('VITRE', 'LAVAL', 'main'),
  ('LAVAL', 'LE MANS', 'main'),
  ('RENNES', 'DOL DE BRETAGNE', 'main'),
  ('DOL DE BRETAGNE', 'ST MALO', 'main'),
  ('VANNES', 'REDON', 'main'),
  ('REDON', 'RENNES', 'main'),
  ('REDON', 'NANTES', 'main'),

  // ============ PAYS DE LA LOIRE ============
  ('NANTES', 'ST NAZAIRE', 'main'),
  ('ST NAZAIRE', 'PORNICHET', 'secondary'),
  ('PORNICHET', 'LA BAULE ESCOUBLAC', 'secondary'),
  ('LA BAULE ESCOUBLAC', 'LE POULIGUEN', 'secondary'),
  ('LE POULIGUEN', 'LE CROISIC', 'secondary'),
  ('NANTES', 'ANCENIS', 'main'),
  ('ANCENIS', 'ANGERS SAINT LAUD', 'main'),
  ('LE MANS', 'SABLE SUR SARTHE', 'secondary'),
  ('SABLE SUR SARTHE', 'ANGERS SAINT LAUD', 'secondary'),
  ('ANGERS SAINT LAUD', 'SAUMUR', 'main'),
  ('NANTES', 'LA ROCHE SUR YON', 'main'),
  ('LA ROCHE SUR YON', 'LES SABLES D\'OLONNE', 'secondary'),
  ('NANTES', 'LA ROCHELLE VILLE', 'main'),

  // ============ CENTRE-OUEST ============
  ('LA ROCHELLE VILLE', 'SURGERES', 'secondary'),
  ('SURGERES', 'NIORT', 'secondary'),
  ('NIORT', 'ST MAIXENT (DEUX SEVRES)', 'secondary'),
  ('ST MAIXENT (DEUX SEVRES)', 'POITIERS', 'secondary'),
  ('POITIERS', 'FUTUROSCOPE', 'secondary'),
  ('FUTUROSCOPE', 'CHATELLERAULT', 'secondary'),
  ('CHATELLERAULT', 'TOURS', 'main'),

  // ============ CENTRE / AUVERGNE ============
  ('PARIS', 'LES AUBRAIS ORLEANS', 'main'),
  ('LES AUBRAIS ORLEANS', 'VIERZON', 'main'),
  ('VIERZON', 'ISSOUDUN', 'secondary'),
  ('ISSOUDUN', 'CHATEAUROUX', 'secondary'),
  ('VIERZON', 'CHATEAUROUX', 'main'),
  ('CHATEAUROUX', 'ARGENTON SUR CREUSE', 'main'),
  ('ARGENTON SUR CREUSE', 'LA SOUTERRAINE', 'main'),
  ('LA SOUTERRAINE', 'LIMOGES BENEDICTINS', 'main'),
  ('VIERZON', 'NEVERS', 'main'),
  ('NEVERS', 'SAINCAIZE', 'secondary'),
  ('SAINCAIZE', 'MOULINS SUR ALLIER', 'secondary'),
  ('NEVERS', 'MOULINS SUR ALLIER', 'main'),
  ('MOULINS SUR ALLIER', 'VICHY', 'secondary'),
  ('MOULINS SUR ALLIER', 'SAINT GERMAIN DES FOSSES', 'secondary'),
  ('SAINT GERMAIN DES FOSSES', 'RIOM CHATEL GUYON', 'secondary'),
  ('RIOM CHATEL GUYON', 'CLERMONT FERRAND', 'main'),
  ('VICHY', 'CLERMONT FERRAND', 'secondary'),
  ('CLERMONT FERRAND', 'LYON', 'main'),

  // ============ LIMOUSIN ============
  ('LIMOGES BENEDICTINS', 'UZERCHE', 'main'),
  ('UZERCHE', 'BRIVE LA GAILLARDE', 'main'),
  ('BRIVE LA GAILLARDE', 'ST DENIS PRES MARTEL', 'secondary'),
  ('ST DENIS PRES MARTEL', 'SOUILLAC', 'secondary'),
  ('BRIVE LA GAILLARDE', 'SOUILLAC', 'main'),
  ('SOUILLAC', 'GOURDON', 'main'),
  ('GOURDON', 'CAHORS', 'main'),
  ('CAHORS', 'MONTAUBAN VILLE BOURBON', 'main'),
  ('BRIVE LA GAILLARDE', 'BRETENOUX BIARS', 'secondary'),
  ('BRETENOUX BIARS', 'LAROQUEBROU BATIMENT VOYAGEURS', 'secondary'),
  ('LAROQUEBROU BATIMENT VOYAGEURS', 'AURILLAC', 'secondary'),

  // ============ MIDI-PYRENEES ============
  ('TOULOUSE MATABIAU', 'MONTAUBAN VILLE BOURBON', 'main'),
  ('MONTAUBAN VILLE BOURBON', 'CAUSSADE(TARN ET GARONNE)', 'secondary'),
  ('CAUSSADE(TARN ET GARONNE)', 'CAHORS', 'secondary'),
  ('MONTAUBAN VILLE BOURBON', 'AGEN', 'main'),
  ('AGEN', 'MARMANDE', 'main'),
  ('MARMANDE', 'BORDEAUX ST JEAN', 'main'),

  // ============ AQUITAINE ============
  ('BORDEAUX ST JEAN', 'LIBOURNE', 'main'),
  ('BORDEAUX ST JEAN', 'ARCACHON', 'main'),
  ('BORDEAUX ST JEAN', 'BIGANOS FACTURE', 'secondary'),
  ('BIGANOS FACTURE', 'LA TESTE', 'secondary'),
  ('LA TESTE', 'ARCACHON', 'secondary'),
  ('BORDEAUX ST JEAN', 'DAX', 'main'),
  ('DAX', 'ST VINCENT DE TYROSSE', 'secondary'),
  ('ST VINCENT DE TYROSSE', 'BAYONNE', 'secondary'),
  ('DAX', 'BAYONNE', 'main'),
  ('BAYONNE', 'BIARRITZ', 'main'),
  ('BIARRITZ', 'ST JEAN DE LUZ CIBOURE', 'main'),
  ('ST JEAN DE LUZ CIBOURE', 'HENDAYE', 'main'),
  ('DAX', 'ORTHEZ', 'secondary'),
  ('ORTHEZ', 'PAU', 'secondary'),
  ('DAX', 'PAU', 'main'),
  ('PAU', 'TARBES', 'main'),
  ('TARBES', 'LOURDES', 'secondary'),

  // ============ INTERCONNEXIONS PARIS ============
  ('PARIS', 'AEROPORT ROISSY CDG 2 TGV', 'lgv'),
  ('PARIS', 'MARNE LA VALLEE CHESSY', 'lgv'),
  ('PARIS', 'VERSAILLES CHANTIERS', 'main'),
  ('PARIS', 'MASSY PALAISEAU', 'main'),
  ('MASSY PALAISEAU', 'MASSY TGV', 'secondary'),
  ('AEROPORT ROISSY CDG 2 TGV', 'MARNE LA VALLEE CHESSY', 'lgv'),
  ('MARNE LA VALLEE CHESSY', 'LYON', 'lgv'),
  ('AEROPORT ROISSY CDG 2 TGV', 'LILLE', 'lgv'),
  ('AEROPORT ROISSY CDG 2 TGV', 'STRASBOURG', 'lgv'),
];
