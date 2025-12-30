# Structure du projet TGV Max Checker

```
sncfmax/
│
├── backend/                          # BACKEND VPS (Docker)
│   ├── server.js                     # Serveur principal
│   ├── Dockerfile                    # Image Docker
│   ├── docker-compose.yml            # Config deployment
│   └── package.json                  # Deps: express, puppeteer, cors
│
├── lib/                              # APP FLUTTER
│   ├── main.dart                     # Point d'entrée
│   │
│   ├── models/                       # Modèles de données
│   │   ├── station.dart              # Gare (code, nom)
│   │   └── train_proposal.dart       # Train + DayProposals
│   │
│   ├── screens/                      # Écrans UI
│   │   └── calendar_screen.dart      # Calendrier principal
│   │
│   └── services/                     # Logique métier
│       ├── backend_api_service.dart  # Appels API vers VPS ✓
│       ├── sncf_api_service.dart     # Appels directs SNCF (obsolète)
│       └── cookie_manager.dart       # Gestion cookies (obsolète)
│
├── android/                          # Config native Android
├── ios/                              # Config native iOS
├── build/                            # Fichiers compilés
│
├── pubspec.yaml                      # Deps Flutter
├── ARCHITECTURE.md                   # Doc technique détaillée
└── STRUCTURE.md                      # Ce fichier
```

## Fichiers clés

### Backend (`backend/`)

| Fichier | Rôle |
|---------|------|
| `server.js` | Express + Puppeteer. Contourne DataDome via Chrome headless |
| `Dockerfile` | Node 20 + Chromium installé |
| `docker-compose.yml` | Port 3000, restart auto, permissions Chromium |

### Flutter (`lib/`)

| Fichier | Rôle |
|---------|------|
| `main.dart` | Lance l'app, init locale FR |
| `calendar_screen.dart` | UI calendrier + liste trains |
| `backend_api_service.dart` | Singleton, appels HTTP vers VPS |
| `train_proposal.dart` | Parse JSON trains, calcul durée |
| `station.dart` | Parse JSON gares |

## Flux simplifié

```
[App Flutter]
     │
     │ HTTP GET /api/trains/month
     ▼
[VPS Docker :3000]
     │
     │ page.evaluate(fetch(...))
     ▼
[Chrome Headless]
     │
     │ Requête avec cookies DataDome
     ▼
[SNCF API]
     │
     │ JSON trains
     ▼
[Retour vers Flutter]
```

## Commandes utiles

```bash
# Backend
cd backend && docker-compose up -d --build    # Démarrer
docker logs -f sncfmax-backend                # Logs
docker-compose restart                        # Redémarrer

# Flutter
flutter run                                   # Dev
flutter build ios                             # Build iOS
flutter build apk                             # Build Android
```

## Configuration rapide

| Quoi | Où | Valeur actuelle |
|------|-----|-----------------|
| IP du VPS | `lib/services/backend_api_service.dart:13` | `51.210.111.11` |
| Port backend | `backend/docker-compose.yml:8` | `3000` |
| Timeout session | `backend/server.js:19` | 15 min |
| Délai entre requêtes | `backend/server.js:266` | 200ms |
| Trajet par défaut | `lib/screens/calendar_screen.dart:17-20` | La Rochelle → Paris |
