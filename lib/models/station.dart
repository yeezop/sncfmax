class Station {
  final String codeStation;
  final String station;

  Station({
    required this.codeStation,
    required this.station,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      codeStation: json['codeStation'] as String,
      station: json['station'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'codeStation': codeStation,
      'station': station,
    };
  }

  @override
  String toString() => station;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Station && other.codeStation == codeStation;
  }

  @override
  int get hashCode => codeStation.hashCode;
}
