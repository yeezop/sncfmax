/// Preferences for train search with connections
enum ConnectionMode {
  directOnly,       // 0 connections
  oneConnection,    // max 1 connection
  twoConnections,   // max 2 connections
  threeConnections, // max 3 connections
}

extension ConnectionModeExtension on ConnectionMode {
  int get maxConnections {
    switch (this) {
      case ConnectionMode.directOnly:
        return 0;
      case ConnectionMode.oneConnection:
        return 1;
      case ConnectionMode.twoConnections:
        return 2;
      case ConnectionMode.threeConnections:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case ConnectionMode.directOnly:
        return 'Direct uniquement';
      case ConnectionMode.oneConnection:
        return '1 correspondance max';
      case ConnectionMode.twoConnections:
        return '2 correspondances max';
      case ConnectionMode.threeConnections:
        return '3 correspondances max';
    }
  }
}

class SearchPreferences {
  final ConnectionMode connectionMode;
  final Duration minConnectionTime;

  const SearchPreferences({
    this.connectionMode = ConnectionMode.directOnly,
    this.minConnectionTime = const Duration(minutes: 30),
  });

  bool get allowsConnections => connectionMode != ConnectionMode.directOnly;

  SearchPreferences copyWith({
    ConnectionMode? connectionMode,
    Duration? minConnectionTime,
  }) {
    return SearchPreferences(
      connectionMode: connectionMode ?? this.connectionMode,
      minConnectionTime: minConnectionTime ?? this.minConnectionTime,
    );
  }

  static const List<Duration> availableConnectionTimes = [
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  static String formatDuration(Duration duration) {
    if (duration.inMinutes >= 60) {
      return '${duration.inHours}h';
    }
    return '${duration.inMinutes} min';
  }
}
