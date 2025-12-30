import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/station.dart';
import '../services/station_cache_service.dart';
import '../services/backend_api_service.dart';

class StationPicker extends StatefulWidget {
  final String title;
  final Station? currentStation;
  final Function(Station) onStationSelected;

  const StationPicker({
    super.key,
    required this.title,
    this.currentStation,
    required this.onStationSelected,
  });

  static Future<Station?> show({
    required BuildContext context,
    required String title,
    Station? currentStation,
  }) async {
    return showModalBottomSheet<Station>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StationPicker(
        title: title,
        currentStation: currentStation,
        onStationSelected: (station) {
          Navigator.of(context).pop(station);
        },
      ),
    );
  }

  @override
  State<StationPicker> createState() => _StationPickerState();
}

class _StationPickerState extends State<StationPicker> {
  final TextEditingController _searchController = TextEditingController();
  final StationCacheService _cacheService = StationCacheService();
  final BackendApiService _apiService = BackendApiService();

  List<Station> _stations = [];
  bool _isLoading = false;
  Timer? _debounceTimer;

  // Muted color palette (same as CalendarScreen)
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _loadRecentStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentStations() async {
    setState(() => _isLoading = true);

    try {
      final recent = await _cacheService.getRecentStations();
      if (mounted) {
        setState(() {
          _stations = recent;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchStations(query);
    });
  }

  Future<void> _searchStations(String query) async {
    setState(() => _isLoading = true);

    try {
      final results = await _cacheService.searchStations(query, _apiService);
      if (mounted) {
        setState(() {
          _stations = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectStation(Station station) async {
    await _cacheService.addStation(station);
    widget.onStationSelected(station);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(),
          _buildSearchField(),
          if (_isLoading) _buildLoadingIndicator(),
          Expanded(child: _buildStationList()),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: _borderColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.mapPinLine(PhosphorIconsStyle.fill),
            size: 24,
            color: _textPrimary,
          ),
          const SizedBox(width: 12),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                PhosphorIcons.x(PhosphorIconsStyle.bold),
                size: 18,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        autofocus: true,
        style: const TextStyle(
          fontSize: 16,
          color: _textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Rechercher une gare...',
          hintStyle: const TextStyle(
            color: _textMuted,
            fontSize: 16,
          ),
          prefixIcon: Icon(
            PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
            color: _textMuted,
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _loadRecentStations();
                  },
                  child: Icon(
                    PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                    color: _textMuted,
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const LinearProgressIndicator(
      backgroundColor: _borderColor,
      color: _textSecondary,
      minHeight: 2,
    );
  }

  Widget _buildStationList() {
    if (_stations.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.trainSimple(PhosphorIconsStyle.duotone),
              size: 48,
              color: _textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'Aucune gare récente'
                  : 'Aucune gare trouvée',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Commencez à taper pour rechercher',
              style: TextStyle(
                fontSize: 14,
                color: _textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _stations.length,
      itemBuilder: (context, index) {
        final station = _stations[index];
        final isSelected =
            widget.currentStation?.codeStation == station.codeStation;

        return _buildStationTile(station, isSelected);
      },
    );
  }

  Widget _buildStationTile(Station station, bool isSelected) {
    return GestureDetector(
      onTap: () => _selectStation(station),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _backgroundColor : _surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _textSecondary : _borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _backgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                PhosphorIcons.train(PhosphorIconsStyle.fill),
                size: 18,
                color: _textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.station,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    station.codeStation,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                size: 22,
                color: _textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
