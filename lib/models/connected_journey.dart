import 'dart:math';
import 'train_proposal.dart';

/// Represents a single segment of a journey (one train)
class JourneySegment {
  final TrainProposal train;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;

  JourneySegment({
    required this.train,
    required this.originCode,
    required this.originName,
    required this.destinationCode,
    required this.destinationName,
  });

  DateTime get departure => train.departure;
  DateTime get arrival => train.arrival;
  int get availableSeats => train.availableSeats;
  String get trainType => train.trainType;
  String get trainNumber => train.trainNumber;

  String get formattedDeparture => train.formattedDeparture;
  String get formattedArrival => train.formattedArrival;
  Duration get duration => train.duration;
}

/// Information about a connection between two segments
class ConnectionInfo {
  final String stationCode;
  final String stationName;
  final DateTime arrivalTime;
  final DateTime departureTime;

  ConnectionInfo({
    required this.stationCode,
    required this.stationName,
    required this.arrivalTime,
    required this.departureTime,
  });

  Duration get waitTime => departureTime.difference(arrivalTime);

  String get formattedWaitTime {
    final hours = waitTime.inHours;
    final minutes = waitTime.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h${minutes.toString().padLeft(2, '0')}';
    }
    return '${minutes}min';
  }

  String get formattedArrival {
    return '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDeparture {
    return '${departureTime.hour.toString().padLeft(2, '0')}:${departureTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Represents a complete journey with 1-3 connections
class ConnectedJourney {
  final List<JourneySegment> segments;

  ConnectedJourney({required this.segments});

  /// Number of connections (segments - 1)
  int get connectionCount => segments.length - 1;

  /// First departure time
  DateTime get totalDeparture => segments.first.departure;

  /// Last arrival time
  DateTime get totalArrival => segments.last.arrival;

  /// Total journey duration
  Duration get totalDuration => totalArrival.difference(totalDeparture);

  /// Minimum available seats across all segments (bottleneck)
  int get availableSeats =>
      segments.map((s) => s.availableSeats).reduce(min);

  /// Origin of the entire journey
  String get originName => segments.first.originName;
  String get originCode => segments.first.originCode;

  /// Destination of the entire journey
  String get destinationName => segments.last.destinationName;
  String get destinationCode => segments.last.destinationCode;

  /// Get connection details between segments
  List<ConnectionInfo> get connections {
    final List<ConnectionInfo> result = [];
    for (int i = 0; i < segments.length - 1; i++) {
      result.add(ConnectionInfo(
        stationCode: segments[i].destinationCode,
        stationName: segments[i].destinationName,
        arrivalTime: segments[i].arrival,
        departureTime: segments[i + 1].departure,
      ));
    }
    return result;
  }

  /// Total waiting time at all connections
  Duration get totalWaitTime {
    return connections.fold(
      Duration.zero,
      (sum, conn) => sum + conn.waitTime,
    );
  }

  String get formattedTotalDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  String get formattedDeparture {
    final dt = totalDeparture;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedArrival {
    final dt = totalArrival;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Summary of connection stations
  String get connectionsSummary {
    if (connections.isEmpty) return '';
    return connections.map((c) => c.stationName).join(' - ');
  }
}
