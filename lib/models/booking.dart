import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Booking {
  final String arrivalDateTime;
  final String departureDateTime;
  final StationInfo origin;
  final StationInfo destination;
  final String trainNumber;
  final String coachNumber;
  final String seatNumber;
  final String dvNumber;
  final String orderId;
  final String serviceItemId;
  final String travelClass;
  final String travelStatus;
  final String travelConfirmed;
  final String reservationDate;
  final bool avantage;
  final String marketingCarrierRef;

  Booking({
    required this.arrivalDateTime,
    required this.departureDateTime,
    required this.origin,
    required this.destination,
    required this.trainNumber,
    required this.coachNumber,
    required this.seatNumber,
    required this.dvNumber,
    required this.orderId,
    required this.serviceItemId,
    required this.travelClass,
    required this.travelStatus,
    required this.travelConfirmed,
    required this.reservationDate,
    required this.avantage,
    required this.marketingCarrierRef,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      arrivalDateTime: json['arrivalDateTime'] ?? '',
      departureDateTime: json['departureDateTime'] ?? '',
      origin: StationInfo.fromJson(json['origin'] ?? {}),
      destination: StationInfo.fromJson(json['destination'] ?? {}),
      trainNumber: json['trainNumber'] ?? '',
      coachNumber: json['coachNumber'] ?? '',
      seatNumber: json['seatNumber'] ?? '',
      dvNumber: json['dvNumber'] ?? '',
      orderId: json['orderId'] ?? '',
      serviceItemId: json['serviceItemId'] ?? '',
      travelClass: json['travelClass'] ?? '2',
      travelStatus: json['travelStatus'] ?? '',
      travelConfirmed: json['travelConfirmed'] ?? '',
      reservationDate: json['reservationDate'] ?? '',
      avantage: json['avantage'] ?? false,
      marketingCarrierRef: json['marketingCarrierRef'] ?? '',
    );
  }

  DateTime get departure => DateTime.parse(departureDateTime).toLocal();
  DateTime get arrival => DateTime.parse(arrivalDateTime).toLocal();

  String get formattedDeparture {
    final dt = departure;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedArrival {
    final dt = arrival;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    final dt = departure;
    final months = ['jan', 'fév', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
    final days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}';
  }

  Duration get duration => arrival.difference(departure);

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h${minutes.toString().padLeft(2, '0')}';
    }
    return '${minutes}min';
  }

  bool get isUpcoming => departure.isAfter(DateTime.now());
  bool get isPast => departure.isBefore(DateTime.now());
  bool get isToday {
    final now = DateTime.now();
    return departure.year == now.year &&
           departure.month == now.month &&
           departure.day == now.day;
  }

  String get confirmationStatus {
    switch (travelConfirmed) {
      case 'CONFIRMED':
        return 'Confirmé';
      case 'TO_BE_CONFIRMED':
        return 'À confirmer';
      case 'TOO_EARLY_TO_CONFIRM':
        return 'Trop tôt';
      case 'TOO_LATE_TO_CONFIRM':
        return 'Passé';
      default:
        return travelConfirmed;
    }
  }

  bool get needsConfirmation => travelConfirmed == 'TO_BE_CONFIRMED';
  bool get isConfirmed => travelConfirmed == 'CONFIRMED';
  bool get isTooEarly => travelConfirmed == 'TOO_EARLY_TO_CONFIRM';

  /// Date when confirmation becomes available (48h before departure)
  DateTime get confirmationAvailableAt => departure.subtract(const Duration(hours: 48));

  /// Formatted date for when confirmation is available
  String get confirmationAvailableFormatted {
    final dt = confirmationAvailableAt;
    final months = ['jan', 'fév', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
    final days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Check if confirmation window is now open
  bool get canConfirmNow => DateTime.now().isAfter(confirmationAvailableAt) && isUpcoming;

  Map<String, dynamic> toJson() => {
    'arrivalDateTime': arrivalDateTime,
    'departureDateTime': departureDateTime,
    'origin': origin.toJson(),
    'destination': destination.toJson(),
    'trainNumber': trainNumber,
    'coachNumber': coachNumber,
    'seatNumber': seatNumber,
    'dvNumber': dvNumber,
    'orderId': orderId,
    'serviceItemId': serviceItemId,
    'travelClass': travelClass,
    'travelStatus': travelStatus,
    'travelConfirmed': travelConfirmed,
    'reservationDate': reservationDate,
    'avantage': avantage,
    'marketingCarrierRef': marketingCarrierRef,
  };
}

class StationInfo {
  final String label;
  final String rrCode;

  StationInfo({
    required this.label,
    required this.rrCode,
  });

  factory StationInfo.fromJson(Map<String, dynamic> json) {
    return StationInfo(
      label: json['label'] ?? '',
      rrCode: json['rrCode'] ?? '',
    );
  }

  String get shortName {
    // Simplify station names
    String name = label
        .replaceAll('PARIS MONTPARNASSE 1 ET 2', 'Paris Montparnasse')
        .replaceAll('PARIS GARE DE LYON', 'Paris Gare de Lyon')
        .replaceAll('PARIS NORD', 'Paris Nord')
        .replaceAll('PARIS EST', 'Paris Est')
        .replaceAll('LILLE FLANDRES', 'Lille Flandres')
        .replaceAll('LILLE EUROPE', 'Lille Europe')
        .replaceAll(' VILLE', '');

    // Title case
    return name.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'rrCode': rrCode,
  };
}

class UserSession {
  final bool isAuthenticated;
  final String? cardNumber;
  final String? lastName;
  final String? firstName;
  final String? email;

  UserSession({
    required this.isAuthenticated,
    this.cardNumber,
    this.lastName,
    this.firstName,
    this.email,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return UserSession(
      isAuthenticated: json['isAuthenticated'] ?? false,
      cardNumber: user?['cardNumber'],
      lastName: user?['lastName'],
      firstName: user?['firstName'],
      email: user?['email'],
    );
  }

  Map<String, dynamic> toJson() => {
    'isAuthenticated': isAuthenticated,
    'cardNumber': cardNumber,
    'lastName': lastName,
    'firstName': firstName,
    'email': email,
  };

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? 'Utilisateur';
  }
}

// Local storage for bookings (singleton with persistence)
class BookingsStore {
  static final BookingsStore _instance = BookingsStore._internal();
  factory BookingsStore() => _instance;
  BookingsStore._internal();

  static const String _sessionKey = 'mon_max_session';
  static const String _bookingsKey = 'mon_max_bookings';
  static const String _lastUpdatedKey = 'mon_max_last_updated';

  UserSession? _userSession;
  List<Booking> _bookings = [];
  DateTime? _lastUpdated;
  bool _initialized = false;

  bool get isAuthenticated => _userSession?.isAuthenticated ?? false;
  UserSession? get userSession => _userSession;
  List<Booking> get bookings => _bookings;
  String? get cardNumber => _userSession?.cardNumber;
  DateTime? get lastUpdated => _lastUpdated;

  /// Check if data is stale (older than 24h)
  bool get isDataStale {
    if (_lastUpdated == null) return true;
    return DateTime.now().difference(_lastUpdated!).inHours > 24;
  }

  /// Formatted last updated string
  String get lastUpdatedFormatted {
    if (_lastUpdated == null) return 'Jamais';
    final now = DateTime.now();
    final diff = now.difference(_lastUpdated!);

    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} jours';

    final months = ['jan', 'fév', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
    return '${_lastUpdated!.day} ${months[_lastUpdated!.month - 1]}';
  }

  /// Initialize store from SharedPreferences (call on app start)
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load session
      final sessionJson = prefs.getString(_sessionKey);
      if (sessionJson != null) {
        final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
        _userSession = UserSession(
          isAuthenticated: sessionData['isAuthenticated'] ?? false,
          cardNumber: sessionData['cardNumber'],
          lastName: sessionData['lastName'],
          firstName: sessionData['firstName'],
          email: sessionData['email'],
        );
      }

      // Load bookings
      final bookingsJson = prefs.getString(_bookingsKey);
      if (bookingsJson != null) {
        final bookingsList = jsonDecode(bookingsJson) as List;
        _bookings = bookingsList
            .map((b) => Booking.fromJson(b as Map<String, dynamic>))
            .toList();
      }

      // Load last updated timestamp
      final lastUpdatedMs = prefs.getInt(_lastUpdatedKey);
      if (lastUpdatedMs != null) {
        _lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastUpdatedMs);
      }

      _initialized = true;
    } catch (e) {
      // Ignore errors, start fresh
      _initialized = true;
    }
  }

  Future<void> storeSession(UserSession session, List<Booking> bookings) async {
    _userSession = session;
    _bookings = bookings;
    _lastUpdated = DateTime.now();
    await _persist();
  }

  Future<void> updateBookings(List<Booking> bookings) async {
    _bookings = bookings;
    _lastUpdated = DateTime.now();
    await _persist();
  }

  Future<void> clear() async {
    _userSession = null;
    _bookings = [];
    _lastUpdated = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      await prefs.remove(_bookingsKey);
      await prefs.remove(_lastUpdatedKey);
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_userSession != null) {
        await prefs.setString(_sessionKey, jsonEncode(_userSession!.toJson()));
      }

      final bookingsData = _bookings.map((b) => b.toJson()).toList();
      await prefs.setString(_bookingsKey, jsonEncode(bookingsData));

      if (_lastUpdated != null) {
        await prefs.setInt(_lastUpdatedKey, _lastUpdated!.millisecondsSinceEpoch);
      }
    } catch (e) {
      // Ignore persistence errors
    }
  }
}
