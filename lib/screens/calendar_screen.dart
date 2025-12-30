import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/train_proposal.dart';
import '../models/station.dart';
import '../models/sncf_connect_session.dart';
import '../services/backend_api_service.dart';
import '../widgets/station_picker.dart';
import 'alert_setup_screen.dart';
import 'booking_confirmation_screen.dart';
import 'sncf_booking_webview_screen.dart';

class CalendarScreen extends StatefulWidget {
  final VoidCallback? onMapPressed;

  const CalendarScreen({super.key, this.onMapPressed});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final BackendApiService _apiService = BackendApiService();

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

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);

  // Muted availability colors
  static const Color _availabilityHigh = Color(0xFFBBF7D0);
  static const Color _availabilityMedium = Color(0xFFFEF08A);
  static const Color _availabilityLow = Color(0xFFFECACA);
  static const Color _noData = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
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

  Future<void> _loadMonthData(DateTime month) async {
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

  Color _getDayColor(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final proposals = _proposalsMap[normalizedDay];

    if (proposals == null) return _noData;
    if (!proposals.hasAvailability) return _availabilityLow;

    final totalSeats = proposals.totalSeats;
    if (totalSeats > 50) return _availabilityHigh;
    if (totalSeats > 20) return _availabilityMedium;
    return _availabilityLow;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final normalizedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

    setState(() {
      _selectedDay = normalizedDay;
      _focusedDay = focusedDay;
      _selectedDayProposals = _proposalsMap[normalizedDay];
    });
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
      _selectedDayProposals = null;
      _swapCount++;
    });
    _loadMonthData(_focusedDay);
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
        _selectedDayProposals = null;
      });
      _loadMonthData(_focusedDay);
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
        _selectedDayProposals = null;
      });
      _loadMonthData(_focusedDay);
    }
  }

  Future<void> _refreshData() async {
    _proposalsMap.clear();
    await _loadMonthData(_focusedDay);
    if (_selectedDay != null) {
      final normalizedDay = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      setState(() {
        _selectedDayProposals = _proposalsMap[normalizedDay];
      });
    }
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
            if (_isLoading)
              const LinearProgressIndicator(
                backgroundColor: _borderColor,
                color: _textSecondary,
                minHeight: 2,
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
          _loadMonthData(focusedDay);
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
    final trainCount = proposals?.proposals.length ?? 0;

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: _textPrimary, width: 2)
            : isToday
                ? Border.all(color: _textSecondary, width: 1)
                : null,
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: _textPrimary.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
                color: _textPrimary,
              ),
            ),
            if (trainCount > 0)
              Text(
                '$trainCount',
                style: const TextStyle(
                  fontSize: 10,
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
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

    if (!_selectedDayProposals!.hasAvailability) {
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

    return SliverPadding(
      padding: const EdgeInsets.all(20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final train = _selectedDayProposals!.proposals[index];
            return TweenAnimationBuilder<double>(
              key: ValueKey('${_selectedDay}_$index'),
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
          },
          childCount: _selectedDayProposals!.proposals.length,
        ),
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
