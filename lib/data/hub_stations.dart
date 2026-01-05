// Major TGV hub stations used for pathfinding connections
// These are the main interchange stations in France

class HubStation {
  final String code;
  final String name;
  final String? alternativeName; // For matching with tgvMaxRoutes

  const HubStation(this.code, this.name, {this.alternativeName});
}

/// List of major TGV hub stations for connections
const List<HubStation> tgvHubStations = [
  // Paris stations
  HubStation('FRPLY', 'Paris Gare de Lyon', alternativeName: 'PARIS'),
  HubStation('FRPNO', 'Paris Montparnasse', alternativeName: 'PARIS'),
  HubStation('FRPST', 'Paris Est', alternativeName: 'PARIS'),
  HubStation('FRPSL', 'Paris Gare du Nord', alternativeName: 'PARIS'),

  // Major regional hubs
  HubStation('FRLYS', 'Lyon Part Dieu', alternativeName: 'LYON'),
  HubStation('FRMLW', 'Marseille St Charles', alternativeName: 'MARSEILLE ST CHARLES'),
  HubStation('FRBSC', 'Bordeaux St Jean', alternativeName: 'BORDEAUX ST JEAN'),
  HubStation('FRRNS', 'Rennes', alternativeName: 'RENNES'),
  HubStation('FRLLE', 'Lille Europe', alternativeName: 'LILLE'),
  HubStation('FRLFE', 'Lille Flandres', alternativeName: 'LILLE'),
  HubStation('FRNTS', 'Nantes', alternativeName: 'NANTES'),
  HubStation('FRMPL', 'Montpellier Saint Roch', alternativeName: 'MONTPELLIER SAINT ROCH'),
  HubStation('FRSXB', 'Strasbourg', alternativeName: 'STRASBOURG'),
  HubStation('FRTLS', 'Toulouse Matabiau', alternativeName: 'TOULOUSE MATABIAU'),

  // Important TGV interchange stations
  HubStation('FRAVT', 'Avignon TGV', alternativeName: 'AVIGNON TGV'),
  HubStation('FRMTG', 'Massy TGV', alternativeName: 'MASSY TGV'),
  HubStation('FRMLV', 'Marne la Vallee Chessy', alternativeName: 'MARNE LA VALLEE CHESSY'),
  HubStation('FRAIX', 'Aix en Provence TGV', alternativeName: 'AIX EN PROVENCE TGV'),
  HubStation('FRLPX', 'Lyon St Exupery TGV', alternativeName: 'LYON ST EXUPERY TGV'),
  HubStation('FRVCE', 'Valence TGV', alternativeName: 'VALENCE TGV AUVERGNE RHONE ALPES'),
  HubStation('FRCDG', 'Aeroport CDG 2 TGV', alternativeName: 'AEROPORT ROISSY CDG 2 TGV'),

  // Other important stations
  HubStation('FRANG', 'Angers Saint Laud', alternativeName: 'ANGERS SAINT LAUD'),
  HubStation('FRTRS', 'Tours', alternativeName: 'ST PIERRE DES CORPS'),
  HubStation('FRPOI', 'Poitiers', alternativeName: 'POITIERS'),
  HubStation('FRLMN', 'Le Mans', alternativeName: 'LE MANS'),
  HubStation('FRDJN', 'Dijon Ville', alternativeName: 'DIJON VILLE'),
];

/// Set of hub station codes for O(1) lookup
final Set<String> hubStationCodes = tgvHubStations.map((h) => h.code).toSet();

/// Map from station code to hub station
final Map<String, HubStation> hubStationByCode = {
  for (final hub in tgvHubStations) hub.code: hub,
};

/// Map from alternative name (uppercase) to hub station
final Map<String, HubStation> hubStationByName = {
  for (final hub in tgvHubStations)
    if (hub.alternativeName != null) hub.alternativeName!: hub,
};

/// Get hub station by code or name
HubStation? findHubStation(String codeOrName) {
  return hubStationByCode[codeOrName] ?? hubStationByName[codeOrName.toUpperCase()];
}

/// Check if a station is a hub
bool isHubStation(String code) => hubStationCodes.contains(code);
