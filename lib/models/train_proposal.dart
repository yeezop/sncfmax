class TrainProposal {
  final String arrivalTime;
  final String departureTime;
  final int availableSeats;
  final String destination;
  final String origin;
  final String trainNumber;
  final String trainType;

  TrainProposal({
    required this.arrivalTime,
    required this.departureTime,
    required this.availableSeats,
    required this.destination,
    required this.origin,
    required this.trainNumber,
    required this.trainType,
  });

  factory TrainProposal.fromJson(Map<String, dynamic> json) {
    return TrainProposal(
      arrivalTime: json['arr'] as String,
      departureTime: json['dep'] as String,
      availableSeats: json['count'] as int,
      destination: json['dest'] as String,
      origin: json['orig'] as String,
      trainNumber: json['num'] as String,
      trainType: json['type'] as String,
    );
  }

  DateTime get departure => DateTime.parse(departureTime);
  DateTime get arrival => DateTime.parse(arrivalTime);

  String get formattedDeparture {
    final dt = departure;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedArrival {
    final dt = arrival;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Duration get duration => arrival.difference(departure);

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }
}

class DayProposals {
  final DateTime date;
  final List<TrainProposal> proposals;
  final double ratio;

  DayProposals({
    required this.date,
    required this.proposals,
    required this.ratio,
  });

  bool get hasAvailability => proposals.isNotEmpty;
  int get totalSeats => proposals.fold(0, (sum, p) => sum + p.availableSeats);
}
