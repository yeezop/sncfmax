# SNCF Max Backend Server

Serveur proxy utilisant Puppeteer pour contourner la protection DataDome de SNCF.

## VPS Production

| Info | Valeur |
|------|--------|
| Host | `vps-59c34905.vps.ovh.net` |
| IPv4 | `51.210.111.11` |
| IPv6 | `2001:41d0:305:2100::da52` |
| User | `debian` |
| OS | Debian 12 - Docker |
| Container | `sncfback` |

### Connexion SSH

```bash
ssh debian@51.210.111.11
```

### Deploiement

```bash
# Copier les fichiers modifies
scp server.js debian@51.210.111.11:~/sncfback/

# Sur le VPS: rebuild et restart
ssh debian@51.210.111.11 "cd ~/sncfback && docker compose up -d --build"
```

### Logs

```bash
ssh debian@51.210.111.11 "docker logs -f sncfback"
```

## Installation locale

```bash
cd backend
npm install
npm start
```

Le serveur demarre sur `http://localhost:3000`

## Endpoints

### Core
- `GET /health` - Status du serveur et taille du cache
- `POST /init` - Reinitialiser la session navigateur

### Stations
- `GET /api/stations?label=paris` - Rechercher des gares

### Trains
- `GET /api/trains?origin=FRPST&destination=FRLRH&date=2025-01-15T01:00:00.000Z` - Trains pour un jour
- `GET /api/trains/month?origin=FRPST&destination=FRLRH&year=2025&month=1` - Trains pour un mois

Ajouter `&refresh=true` pour forcer le rafraichissement (ignorer le cache).

### Cache
- `GET /api/cache/stats` - Voir toutes les entrees du cache
- `DELETE /api/cache` - Vider tout le cache
- `DELETE /api/cache/route?origin=X&destination=Y` - Vider le cache d'une route

## Systeme de cache

Le cache utilise un TTL variable selon la proximite de la date :

| Periode | TTL | Raison |
|---------|-----|--------|
| Aujourd'hui | 2 min | Places partent vite |
| Demain | 5 min | Encore volatile |
| J+2 a J+7 | 15 min | Changements moderes |
| J+8+ | 1 heure | Peu de changements |

## Configuration pour appareil mobile

Si vous testez sur un appareil reel (pas le simulateur), modifiez l'adresse du serveur dans:
`lib/services/backend_api_service.dart`

```dart
// Remplacez localhost par l'IP de votre ordinateur
static const String _baseUrl = 'http://192.168.x.x:3000';
```
