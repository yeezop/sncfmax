import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/train_proposal.dart';
import '../models/station.dart';
import '../models/sncf_connect_session.dart';
import '../models/search_preferences.dart';
import '../models/connected_journey.dart';
import '../services/backend_api_service.dart';
import '../services/connection_finder_service.dart';
import '../widgets/station_picker.dart';
import '../widgets/connection_selector.dart';
import '../widgets/connected_journey_card.dart';
import 'alert_setup_screen.dart';
import 'booking_confirmation_screen.dart';
import 'sncf_booking_webview_screen.dart';
import 'connected_journey_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  final VoidCallback? onMapPressed;

  const CalendarScreen({super.key, this.onMapPressed});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final BackendApiService _apiService = BackendApiService();
  late ConnectionFinderService _connectionFinder;

  // SharedPreferences keys
  static const String _prefOriginCode = 'station_origin_code';
  static const String _prefOriginName = 'station_origin_name';
  static const String _prefDestinationCode = 'station_destination_code';
  static const String _prefDestinationName = 'station_destination_name';

  // Default values
  String _originCode = 'FRLRH';
  String _originName = 'La Rochelle Ville';
  String _destinationCode = 'FRPST';
  String _destinationName = 'Paris Est';

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<DateTime, DayProposals> _proposalsMap = {};
  bool _isLoading = false;
  bool _isInitializing = true;
  DayProposals? _selectedDayProposals;
  int _swapCount = 0;

  // Animation tracking - days that have been revealed with animation
  final Set<DateTime> _revealedDays = {};

  // Connection search state
  SearchPreferences _searchPreferences = const SearchPreferences();
  final Map<DateTime, List<ConnectedJourney>> _connectedJourneysMap = {};
  bool _isLoadingConnections = false;
  String? _connectionProgress;

  // Month-wide connection loading state
  final Map<DateTime, _DayConnectionSummary> _connectionSummaryMap = {};
  bool _isLoadingMonthConnections = false;
  int _connectionLoadingProgress = 0;
  int _connectionLoadingTotal = 0;
  bool _cancelMonthConnectionLoading = false;

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);

  // Muted availability colors
  static const Color _availabilityHigh = Color(0xFFBBF7D0);    // Green - many trains
  static const Color _availabilityMedium = Color(0xFFFEF08A);  // Yellow - some trains
  static const Color _availabilityLow = Color(0xFFFED7AA);     // Orange - few trains
  static const Color _availabilityNone = Color(0xFFFECACA);    // Red - no trains
  static const Color _noData = Color(0xFFF1F5F9);

  // TGV Max availability limit (J+30)
  static const int _maxBookingDays = 30;

  @override
  void initState() {
    super.initState();
    _connectionFinder = ConnectionFinderService(_apiService);
    _connectionFinder.onProgress = _onConnectionProgress;
    _initializeService();
  }

  void _onConnectionProgress(int current, int total) {
    if (mounted) {
      setState(() {
        _connectionProgress = 'Recherche $current/$total...';
      });
    }
  }

  Future<void> _loadSavedStations() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOriginCode = prefs.getString(_prefOriginCode);
    final savedOriginName = prefs.getString(_prefOriginName);
    final savedDestinationCode = prefs.getString(_prefDestinationCode);
    final savedDestinationName = prefs.getString(_prefDestinationName);

    if (savedOriginCode != null && savedOriginName != null) {
      _originCode = savedOriginCode;
      _originName = savedOriginName;
    }
    if (savedDestinationCode != null && savedDestinationName != null) {
      _destinationCode = savedDestinationCode;
      _destinationName = savedDestinationName;
    }
  }

  Future<void> _saveStations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefOriginCode, _originCode);
    await prefs.setString(_prefOriginName, _originName);
    await prefs.setString(_prefDestinationCode, _destinationCode);
    await prefs.setString(_prefDestinationName, _destinationName);
  }

  Future<void> _initializeService() async {
    try {
      // Load saved stations before initializing
      await _loadSavedStations();
      await _apiService.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        _loadMonthData(_focusedDay);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(PhosphorIcons.warningCircle(PhosphorIconsStyle.fill),
                    color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Erreur de connexion: $e')),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadMonthData(DateTime month, {bool preloadNext = true}) async {
    if (_isInitializing || !_apiService.isReady) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _apiService.searchTrainsForMonth(
        origin: _originCode,
        destination: _destinationCode,
        month: month,
      );

      if (mounted) {
        setState(() {
          _proposalsMap.addAll(results);
          _isLoading = false;
        });
      }

      // Preload next month in background (don't await)
      if (preloadNext) {
        final nextMonth = DateTime(month.year, month.month + 1, 1);
        final maxDate = DateTime.now().add(const Duration(days: 90));
        if (nextMonth.isBefore(maxDate)) {
          _preloadMonth(nextMonth);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  /// Preloads a month in the background without showing loading indicator
  Future<void> _preloadMonth(DateTime month) async {
    if (!_apiService.isReady) return;

    try {
      final results = await _apiService.searchTrainsForMonth(
        origin: _originCode,
        destination: _destinationCode,
        month: month,
      );

      if (mounted) {
        setState(() {
          _proposalsMap.addAll(results);
        });
      }
    } catch (e) {
      // Silently ignore preload errors
      debugPrint('Preload error for ${month.month}/${month.year}: $e');
    }
  }

  /// Checks if a date is beyond the TGV Max booking limit (J+30)
  bool _isDateBeyondMaxBooking(DateTime day) {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final difference = normalizedDay.difference(normalizedToday).inDays;
    return difference > _maxBookingDays;
  }

  /// Returns the date when trains for this day will become available
  DateTime _getAvailabilityDate(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return normalizedDay.subtract(const Duration(days: _maxBookingDays));
  }

  /// Formats the availability date message
  String _getAvailabilityMessage(DateTime day) {
    final availabilityDate = _getAvailabilityDate(day);
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final daysUntilAvailable = availabilityDate.difference(normalizedToday).inDays;

    if (daysUntilAvailable <= 0) {
      return "Revenez plus tard aujourd'hui";
    } else if (daysUntilAvailable == 1) {
      return 'Revenez demain';
    } else if (daysUntilAvailable == 2) {
      return 'Revenez apres-demain';
    } else {
      final formattedDate = DateFormat('d MMMM yyyy', 'fr_FR').format(availabilityDate);
      return 'Revenez le $formattedDate';
    }
  }

  Color _getDayColor(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);

    // Days beyond J+30 are shown in red (no TGV Max available)
    if (_isDateBeyondMaxBooking(day)) {
      return _availabilityNone;
    }

    final proposals = _proposalsMap[normalizedDay];
    final connectionSummary = _connectionSummaryMap[normalizedDay];

    // Count direct trains
    final directCount = proposals?.proposals.length ?? 0;

    // Count connections if mode is enabled
    final connectionCount = _searchPreferences.allowsConnections
        ? (connectionSummary?.count ?? 0)
        : 0;

    // Total count for color logic
    final totalCount = directCount + connectionCount;

    // No data yet (direct trains not loaded)
    if (proposals == null) return _noData;

    // No availability at all (direct or connection)
    if (totalCount == 0) return _availabilityNone;

    // Color based on total count
    if (totalCount >= 6) return _availabilityHigh;
    if (totalCount >= 3) return _availabilityMedium;
    return _availabilityLow;  // 1-2 trains = orange
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final normalizedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

    setState(() {
      _selectedDay = normalizedDay;
      _focusedDay = focusedDay;
      _selectedDayProposals = _proposalsMap[normalizedDay];
    });

    // Don't load connections for dates beyond J+30
    if (_isDateBeyondMaxBooking(normalizedDay)) {
      return;
    }

    // Load connections if enabled
    if (_searchPreferences.allowsConnections) {
      _loadConnectionsForDay(normalizedDay);
    }
  }

  void _swapStations() {
    setState(() {
      final tempCode = _originCode;
      final tempName = _originName;
      _originCode = _destinationCode;
      _originName = _destinationName;
      _destinationCode = tempCode;
      _destinationName = tempName;
      _proposalsMap.clear();
      _connectedJourneysMap.clear();
      _connectionSummaryMap.clear();
      _revealedDays.clear();
      _selectedDayProposals = null;
      _swapCount++;
    });
    _cancelMonthConnections();
    _saveStations();
    _connectionFinder.clearCache();
    _loadMonthData(_focusedDay);
    if (_searchPreferences.allowsConnections) {
      _loadConnectionsForMonth(_focusedDay);
    }
  }

  Future<void> _selectOriginStation() async {
    final station = await StationPicker.show(
      context: context,
      title: 'Gare de départ',
      currentStation: Station(codeStation: _originCode, station: _originName),
    );

    if (station != null && mounted) {
      setState(() {
        _originCode = station.codeStation;
        _originName = station.station;
        _proposalsMap.clear();
        _connectedJourneysMap.clear();
        _connectionSummaryMap.clear();
        _revealedDays.clear();
        _selectedDayProposals = null;
      });
      _cancelMonthConnections();
      _saveStations();
      _connectionFinder.clearCache();
      _loadMonthData(_focusedDay);
      if (_searchPreferences.allowsConnections) {
        _loadConnectionsForMonth(_focusedDay);
      }
    }
  }

  Future<void> _selectDestinationStation() async {
    final station = await StationPicker.show(
      context: context,
      title: "Gare d'arrivée",
      currentStation: Station(codeStation: _destinationCode, station: _destinationName),
    );

    if (station != null && mounted) {
      setState(() {
        _destinationCode = station.codeStation;
        _destinationName = station.station;
        _proposalsMap.clear();
        _connectedJourneysMap.clear();
        _connectionSummaryMap.clear();
        _revealedDays.clear();
        _selectedDayProposals = null;
      });
      _cancelMonthConnections();
      _saveStations();
      _connectionFinder.clearCache();
      _loadMonthData(_focusedDay);
      if (_searchPreferences.allowsConnections) {
        _loadConnectionsForMonth(_focusedDay);
      }
    }
  }

  Future<void> _refreshData() async {
    _cancelMonthConnections();
    _proposalsMap.clear();
    _connectedJourneysMap.clear();
    _connectionSummaryMap.clear();
    _revealedDays.clear();
    _connectionFinder.clearCache();
    await _loadMonthData(_focusedDay);
    if (_selectedDay != null) {
      final normalizedDay = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      setState(() {
        _selectedDayProposals = _proposalsMap[normalizedDay];
      });
    }
    // Load connections for the whole month if enabled
    if (_searchPreferences.allowsConnections) {
      _loadConnectionsForMonth(_focusedDay);
    }
  }

  void _onPreferencesChanged(SearchPreferences newPreferences) {
    // Cancel any ongoing month loading if disabling connections
    if (!newPreferences.allowsConnections) {
      _cancelMonthConnections();
    }

    setState(() {
      _searchPreferences = newPreferences;
      _connectedJourneysMap.clear();
      _connectionSummaryMap.clear();
    });
    _connectionFinder.clearCache();

    // Start month-wide connection loading if enabled
    if (newPreferences.allowsConnections) {
      _loadConnectionsForMonth(_focusedDay);
    }
  }

  Future<void> _loadConnectionsForDay(DateTime day) async {
    if (!_searchPreferences.allowsConnections) return;

    final normalizedDay = DateTime(day.year, day.month, day.day);

    // Don't load connections for dates beyond J+30
    if (_isDateBeyondMaxBooking(normalizedDay)) return;

    // Check cache first
    if (_connectedJourneysMap.containsKey(normalizedDay)) {
      return;
    }

    setState(() {
      _isLoadingConnections = true;
      _connectionProgress = 'Recherche des correspondances...';
    });

    try {
      final journeys = await _connectionFinder.findConnections(
        originCode: _originCode,
        originName: _originName,
        destinationCode: _destinationCode,
        destinationName: _destinationName,
        date: normalizedDay,
        preferences: _searchPreferences,
      );

      if (mounted) {
        setState(() {
          _connectedJourneysMap[normalizedDay] = journeys;
          _isLoadingConnections = false;
          _connectionProgress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingConnections = false;
          _connectionProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur correspondances: $e')),
        );
      }
    }
  }

  /// Load connections for all days in the month (background progressive loading)
  Future<void> _loadConnectionsForMonth(DateTime month) async {
    if (_isLoadingMonthConnections) return;

    // Cancel any previous loading
    _cancelMonthConnectionLoading = false;

    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final maxDate = normalizedToday.add(const Duration(days: _maxBookingDays));

    // Generate list of days to load (only days within J+30 window)
    final daysToLoad = <DateTime>[];
    var day = DateTime(month.year, month.month, 1);
    while (day.month == month.month) {
      final normalizedDay = DateTime(day.year, day.month, day.day);
      if (!normalizedDay.isBefore(normalizedToday) && !normalizedDay.isAfter(maxDate)) {
        // Skip if already loaded
        if (!_connectionSummaryMap.containsKey(normalizedDay)) {
          daysToLoad.add(normalizedDay);
        }
      }
      day = day.add(const Duration(days: 1));
    }

    if (daysToLoad.isEmpty) return;

    setState(() {
      _isLoadingMonthConnections = true;
      _connectionLoadingProgress = 0;
      _connectionLoadingTotal = daysToLoad.length;
    });

    for (int i = 0; i < daysToLoad.length; i++) {
      if (!mounted || _cancelMonthConnectionLoading) {
        break;
      }

      final currentDay = daysToLoad[i];

      setState(() {
        _connectionLoadingProgress = i + 1;
      });

      try {
        final journeys = await _connectionFinder.findConnections(
          originCode: _originCode,
          originName: _originName,
          destinationCode: _destinationCode,
          destinationName: _destinationName,
          date: currentDay,
          preferences: _searchPreferences,
        );

        if (mounted && !_cancelMonthConnectionLoading) {
          setState(() {
            // Store summary for calendar display
            if (journeys.isNotEmpty) {
              _connectionSummaryMap[currentDay] = _DayConnectionSummary(
                count: journeys.length,
                bestTime: journeys.first.totalDuration, // Already sorted by duration
              );
            } else {
              _connectionSummaryMap[currentDay] = const _DayConnectionSummary(count: 0);
            }
            // Also cache the journeys for instant display when day is selected
            _connectedJourneysMap[currentDay] = journeys;
          });
        }
      } catch (e) {
        debugPrint('Error loading connections for $currentDay: $e');
        // Continue with next day even if one fails
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingMonthConnections = false;
        _connectionLoadingProgress = 0;
        _connectionLoadingTotal = 0;
      });
    }
  }

  /// Cancel ongoing month connection loading
  void _cancelMonthConnections() {
    _cancelMonthConnectionLoading = true;
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _borderColor),
                ),
                child: Icon(
                  PhosphorIcons.train(PhosphorIconsStyle.duotone),
                  size: 48,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Connexion au serveur...',
                style: TextStyle(
                  fontSize: 15,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildRouteSelector(),
            _buildConnectionSelector(),
            if (_isLoading || _isLoadingConnections || _isLoadingMonthConnections)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    backgroundColor: _borderColor,
                    color: _isLoadingMonthConnections ? const Color(0xFF3B82F6) : _textSecondary,
                    minHeight: 2,
                    value: _isLoadingMonthConnections && _connectionLoadingTotal > 0
                        ? _connectionLoadingProgress / _connectionLoadingTotal
                        : null,
                  ),
                  if (_isLoadingMonthConnections && _connectionLoadingTotal > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Correspondances: $_connectionLoadingProgress/$_connectionLoadingTotal jours',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                color: _textSecondary,
                backgroundColor: _surfaceColor,
                displacement: 20,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildCalendar()),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    const SliverToBoxAdapter(child: Divider(height: 1)),
                    _buildTrainListSliver(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    PhosphorIcons.train(PhosphorIconsStyle.fill),
                    size: 24,
                    color: _textPrimary,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'TGV Max',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Trouvez vos billets gratuits',
                style: TextStyle(
                  fontSize: 14,
                  color: _textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          if (widget.onMapPressed != null)
            GestureDetector(
              onTap: widget.onMapPressed,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor),
                ),
                child: Icon(
                  PhosphorIcons.mapTrifold(PhosphorIconsStyle.regular),
                  size: 22,
                  color: _textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _selectOriginStation,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.mapPinLine(PhosphorIconsStyle.fill),
                        size: 14,
                        color: _textMuted,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'DEPART',
                        style: TextStyle(
                          fontSize: 11,
                          color: _textMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.5, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        _originName,
                        key: ValueKey('origin-$_swapCount-$_originName'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: _swapStations,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('swap-$_swapCount'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value * 3.14159,
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Icon(
                    PhosphorIcons.arrowsLeftRight(PhosphorIconsStyle.regular),
                    size: 18,
                    color: _textSecondary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _selectDestinationStation,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'ARRIVEE',
                        style: TextStyle(
                          fontSize: 11,
                          color: _textMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
                        size: 14,
                        color: _textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(-0.5, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        _destinationName,
                        key: ValueKey('dest-$_swapCount-$_destinationName'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _textPrimary,
                        ),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ConnectionSelector(
        preferences: _searchPreferences,
        onPreferencesChanged: _onPreferencesChanged,
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: TableCalendar(
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 90)),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: _onDaySelected,
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay;
          // Check if we already have data for this month
          final hasDataForMonth = _proposalsMap.keys.any((date) =>
              date.year == focusedDay.year && date.month == focusedDay.month);
          if (!hasDataForMonth) {
            _loadMonthData(focusedDay, preloadNext: true);
          }
          // Load connections for the month if enabled
          if (_searchPreferences.allowsConnections) {
            _loadConnectionsForMonth(focusedDay);
          }
        },
        locale: 'fr_FR',
        startingDayOfWeek: StartingDayOfWeek.monday,
        calendarFormat: CalendarFormat.month,
        availableGestures: AvailableGestures.none,
        rowHeight: 52,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
          leftChevronIcon: Icon(
            PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
            color: _textSecondary,
            size: 20,
          ),
          rightChevronIcon: Icon(
            PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
            color: _textSecondary,
            size: 20,
          ),
          headerPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textMuted,
          ),
          weekendStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textMuted,
          ),
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, focusedDay) {
            return _buildDayCell(day, false);
          },
          todayBuilder: (context, day, focusedDay) {
            return _buildDayCell(day, false, isToday: true);
          },
          selectedBuilder: (context, day, focusedDay) {
            return _buildDayCell(day, true);
          },
          outsideBuilder: (context, day, focusedDay) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime day, bool isSelected, {bool isToday = false}) {
    final color = _getDayColor(day);
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final proposals = _proposalsMap[normalizedDay];
    final connectionSummary = _connectionSummaryMap[normalizedDay];

    // Calculate counts
    final directCount = proposals?.proposals.length ?? 0;
    final connectionCount = _searchPreferences.allowsConnections
        ? (connectionSummary?.count ?? 0)
        : 0;
    final totalCount = directCount + connectionCount;

    // Calculate best time (minimum between direct and connections)
    Duration? bestTime;
    if (_searchPreferences.allowsConnections) {
      // Best direct train duration (if any)
      final bestDirect = proposals?.proposals.isNotEmpty == true
          ? proposals!.proposals.first.duration
          : null;
      // Best connection duration (if any)
      final bestConnection = connectionSummary?.bestTime;

      if (bestDirect != null && bestConnection != null) {
        bestTime = bestDirect < bestConnection ? bestDirect : bestConnection;
      } else {
        bestTime = bestDirect ?? bestConnection;
      }
    }

    // Determine if we have data for this day
    final hasData = proposals != null || _isDateBeyondMaxBooking(day);

    // Should animate only if we have data and haven't revealed this day yet
    final shouldAnimate = hasData && !_revealedDays.contains(normalizedDay);

    if (shouldAnimate) {
      _revealedDays.add(normalizedDay);
    }

    return _ShimmerDayCell(
      key: ValueKey('day_${normalizedDay.millisecondsSinceEpoch}_$shouldAnimate'),
      day: day,
      targetColor: color,
      trainCount: totalCount,
      bestTime: bestTime,
      showBestTime: _searchPreferences.allowsConnections,
      isSelected: isSelected,
      isToday: isToday,
      shouldAnimate: shouldAnimate,
      hasData: hasData,
    );
  }

  Widget _buildTrainListSliver() {
    if (_selectedDay == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.calendarBlank(PhosphorIconsStyle.duotone),
              size: 48,
              color: _textMuted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Selectionnez un jour',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'pour voir les trains disponibles',
              style: TextStyle(
                fontSize: 14,
                color: _textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Check if date is beyond J+30 (TGV Max not available yet)
    if (_isDateBeyondMaxBooking(_selectedDay!)) {
      final availabilityMessage = _getAvailabilityMessage(_selectedDay!);
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _availabilityNone.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  PhosphorIcons.calendarX(PhosphorIconsStyle.duotone),
                  size: 48,
                  color: const Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Places TGV Max non disponibles',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Les billets TGV Max sont ouverts a la reservation 30 jours avant le depart.',
                style: const TextStyle(
                  fontSize: 14,
                  color: _textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.clock(PhosphorIconsStyle.fill),
                      size: 18,
                      color: const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      availabilityMessage,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedDayProposals == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _textSecondary,
            ),
          ),
        ),
      );
    }

    // Check if we have connections for this day
    final connectedJourneys = _connectedJourneysMap[_selectedDay] ?? [];
    final hasConnections = connectedJourneys.isNotEmpty;

    // Don't show "no availability" if:
    // - Connections are still loading
    // - Or we found connections
    if (!_selectedDayProposals!.hasAvailability && !hasConnections && !_isLoadingConnections) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    PhosphorIcons.prohibit(PhosphorIconsStyle.regular),
                    size: 20,
                    color: _textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aucune place pour le ${DateFormat('d MMMM', 'fr_FR').format(_selectedDay!)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _navigateToAlertSetup,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Creer une alerte',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final directTrains = _selectedDayProposals!.proposals;

    return SliverPadding(
      padding: const EdgeInsets.all(20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // First show direct trains
            if (index < directTrains.length) {
              final train = directTrains[index];
              return TweenAnimationBuilder<double>(
                key: ValueKey('direct_${_selectedDay}_$index'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 300 + (index * 50)),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: _buildTrainCard(train),
              );
            }

            // Section header for connections
            final connectionIndex = index - directTrains.length;
            if (connectionIndex == 0 && hasConnections) {
              return _buildConnectionsSectionHeader();
            }

            // Show connected journeys (offset by 1 for header)
            final journeyIndex = connectionIndex - 1;
            if (journeyIndex >= 0 && journeyIndex < connectedJourneys.length) {
              final journey = connectedJourneys[journeyIndex];
              return TweenAnimationBuilder<double>(
                key: ValueKey('connected_${_selectedDay}_$journeyIndex'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 300 + (journeyIndex * 50)),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: ConnectedJourneyCard(
                  journey: journey,
                  onTap: () => _onConnectedJourneyTap(journey),
                ),
              );
            }

            // Loading indicator for connections
            if (_isLoadingConnections && connectionIndex == 0) {
              return _buildConnectionsLoadingIndicator();
            }

            return const SizedBox.shrink();
          },
          childCount: directTrains.length +
              (hasConnections ? connectedJourneys.length + 1 : 0) +
              (_isLoadingConnections && !hasConnections ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildConnectionsSectionHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.path(PhosphorIconsStyle.fill),
            size: 16,
            color: const Color(0xFF3B82F6),
          ),
          const SizedBox(width: 8),
          const Text(
            'Avec correspondances',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3B82F6),
            ),
          ),
          const Spacer(),
          if (_connectionProgress != null)
            Text(
              _connectionProgress!,
              style: const TextStyle(
                fontSize: 12,
                color: _textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionsLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _connectionProgress ?? 'Recherche des correspondances...',
            style: const TextStyle(
              fontSize: 13,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainCard(TrainProposal train) {
    Color seatColor;
    Color seatBgColor;
    if (train.availableSeats > 20) {
      seatColor = const Color(0xFF166534);
      seatBgColor = _availabilityHigh;
    } else if (train.availableSeats > 5) {
      seatColor = const Color(0xFF854D0E);
      seatBgColor = _availabilityMedium;
    } else {
      seatColor = const Color(0xFF991B1B);
      seatBgColor = _availabilityLow;
    }

    return GestureDetector(
      onTap: () => _onTrainTap(train),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
        children: [
          // Train info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.train(PhosphorIconsStyle.fill),
                      size: 12,
                      color: _textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      train.trainType,
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                train.trainNumber,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: _textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Times
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      train.formattedDeparture,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                        size: 14,
                        color: _textMuted,
                      ),
                    ),
                    Text(
                      train.formattedArrival,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.timer(PhosphorIconsStyle.regular),
                      size: 12,
                      color: _textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      train.formattedDuration,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.path(PhosphorIconsStyle.regular),
                      size: 12,
                      color: _textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${train.origin} - ${train.destination}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Seats
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: seatBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  PhosphorIcons.armchair(PhosphorIconsStyle.fill),
                  size: 16,
                  color: seatColor,
                ),
                const SizedBox(height: 2),
                Text(
                  '${train.availableSeats}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: seatColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildAlertButton() {
    return GestureDetector(
      onTap: _navigateToAlertSetup,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            const Text(
              'Creer une alerte',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAlertSetup() {
    if (_selectedDay == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AlertSetupScreen(
          originCode: _originCode,
          originName: _originName,
          destinationCode: _destinationCode,
          destinationName: _destinationName,
          date: _selectedDay!,
        ),
      ),
    );
  }

  void _onConnectedJourneyTap(ConnectedJourney journey) {
    if (_selectedDay == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConnectedJourneyDetailScreen(
          journey: journey,
          date: _selectedDay!,
        ),
      ),
    );
  }

  Future<void> _onTrainTap(TrainProposal train) async {
    if (_selectedDay == null) return;

    // Check if user is authenticated with SNCF Connect
    await SncfConnectStore().loadSession();
    final isAuthenticated = SncfConnectStore().isAuthenticated;

    if (isAuthenticated) {
      // User is connected - show confirmation screen for direct booking
      if (mounted) {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => BookingConfirmationScreen(
              train: train,
              originCode: _originCode,
              originName: _originName,
              destinationCode: _destinationCode,
              destinationName: _destinationName,
              date: _selectedDay!,
            ),
          ),
        );

        // Show success message if booking was completed
        if (result == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                      color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Reservation effectuee avec succes!'),
                ],
              ),
              backgroundColor: const Color(0xFF22C55E),
            ),
          );
        }
      }
    } else {
      // User not connected - open WebView to login and book
      if (mounted) {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => SncfBookingWebviewScreen(
              train: train,
              originCode: _originCode,
              originName: _originName,
              destinationCode: _destinationCode,
              destinationName: _destinationName,
              date: _selectedDay!,
            ),
          ),
        );

        // Reload session after WebView (user might have logged in)
        await SncfConnectStore().loadSession();

        // Show success message if booking was completed
        if (result == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                      color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Reservation effectuee avec succes!'),
                ],
              ),
              backgroundColor: const Color(0xFF22C55E),
            ),
          );
        }
      }
    }
  }
}

/// Animated day cell with shimmer effect for calendar
class _ShimmerDayCell extends StatefulWidget {
  final DateTime day;
  final Color targetColor;
  final int trainCount;
  final Duration? bestTime;
  final bool showBestTime;
  final bool isSelected;
  final bool isToday;
  final bool shouldAnimate;
  final bool hasData;

  const _ShimmerDayCell({
    super.key,
    required this.day,
    required this.targetColor,
    required this.trainCount,
    this.bestTime,
    this.showBestTime = false,
    required this.isSelected,
    required this.isToday,
    required this.shouldAnimate,
    required this.hasData,
  });

  @override
  State<_ShimmerDayCell> createState() => _ShimmerDayCellState();
}

class _ShimmerDayCellState extends State<_ShimmerDayCell>
    with TickerProviderStateMixin {
  // Shimmer loop controller (for loading state)
  late AnimationController _shimmerController;
  late Animation<double> _shimmerLoop;

  // Reveal controller (for when data arrives)
  late AnimationController _revealController;
  late Animation<double> _colorReveal;
  late Animation<double> _countScale;

  // Colors from parent
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _noData = Color(0xFFF1F5F9);

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  String _formatDurationCompact(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h${m}';
  }

  @override
  void initState() {
    super.initState();

    // Shimmer loop animation (continuous while loading)
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _shimmerLoop = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut,
      ),
    );

    // Reveal animation (plays once when data arrives)
    _revealController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Color reveals from 0.0 to 0.6
    _colorReveal = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Count pops in from 0.4 to 1.0
    _countScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: const Interval(0.4, 1.0, curve: Curves.elasticOut),
      ),
    );

    _initializeAnimation();
  }

  void _initializeAnimation() {
    if (!widget.hasData) {
      // No data yet - loop shimmer continuously
      _shimmerController.repeat();
    } else if (widget.shouldAnimate) {
      // Data just arrived - play reveal animation with stagger
      final delay = (widget.day.day % 7) * 30 + (widget.day.day ~/ 7) * 20;
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) {
          _shimmerController.forward().then((_) {
            if (mounted) {
              _shimmerController.stop();
              _revealController.forward();
            }
          });
        }
      });
    } else {
      // Already revealed, show final state immediately
      _shimmerController.value = 1.0;
      _revealController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _ShimmerDayCell oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Data just arrived - transition from shimmer loop to reveal
    if (!oldWidget.hasData && widget.hasData) {
      _shimmerController.stop();
      final delay = (widget.day.day % 7) * 30 + (widget.day.day ~/ 7) * 20;
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) {
          _revealController.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_shimmerController, _revealController]),
      builder: (context, child) {
        // Show shimmer while loading OR during reveal transition
        final isRevealing = _revealController.value > 0 && _revealController.value < 1;
        final showShimmer = !widget.hasData || isRevealing;

        return Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: widget.isSelected
                ? Border.all(color: _textPrimary, width: 2)
                : widget.isToday
                    ? Border.all(color: _textSecondary, width: 1)
                    : null,
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: _textPrimary.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isSelected ? 10 : 12),
            child: Stack(
              children: [
                // Base color (gray when loading, target color when revealed)
                Positioned.fill(
                  child: Container(
                    color: Color.lerp(
                      _noData,
                      widget.targetColor,
                      widget.hasData ? _colorReveal.value : 0.0,
                    ),
                  ),
                ),

                // Shimmer overlay (fades out during reveal)
                if (showShimmer)
                  Positioned.fill(
                    child: Opacity(
                      opacity: widget.hasData ? (1.0 - _colorReveal.value) : 1.0,
                      child: _buildShimmer(),
                    ),
                  ),

                // Content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.day.day}',
                        style: TextStyle(
                          fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                          color: _textPrimary,
                        ),
                      ),
                      if (widget.trainCount > 0 && _colorReveal.value > 0.3)
                        Transform.scale(
                          scale: _countScale.value.clamp(0.0, 1.0),
                          child: Opacity(
                            opacity: _countScale.value.clamp(0.0, 1.0),
                            child: Text(
                              // Show count and best time on same line if available
                              widget.showBestTime && widget.bestTime != null
                                  ? '${widget.trainCount}·${_formatDurationCompact(widget.bestTime!)}'
                                  : '${widget.trainCount}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: _textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmer() {
    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0x00FFFFFF),
            Color(0x30FFFFFF),
            Color(0x60FFFFFF),
            Color(0x30FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [
            (_shimmerLoop.value - 0.4).clamp(0.0, 1.0),
            (_shimmerLoop.value - 0.2).clamp(0.0, 1.0),
            _shimmerLoop.value.clamp(0.0, 1.0),
            (_shimmerLoop.value + 0.2).clamp(0.0, 1.0),
            (_shimmerLoop.value + 0.4).clamp(0.0, 1.0),
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcATop,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey.shade300,
              Colors.grey.shade200,
              Colors.grey.shade300,
            ],
          ),
        ),
      ),
    );
  }
}

/// Summary of connections for a single day
class _DayConnectionSummary {
  final int count;
  final Duration? bestTime;

  const _DayConnectionSummary({required this.count, this.bestTime});
}
