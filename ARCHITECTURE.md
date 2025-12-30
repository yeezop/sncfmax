# TGV Max Checker - Architecture

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────┐
│                        VPS (Docker)                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              sncfmax-backend (Node.js)                    │  │
│  │  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐   │  │
│  │  │   Express   │───▶│  Puppeteer   │───▶│  Chromium   │   │  │
│  │  │   :3000     │    │  (headless)  │    │  (browser)  │   │  │
│  │  └─────────────┘    └──────────────┘    └─────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│                    ┌──────────────────┐                         │
│                    │  SNCF API        │                         │
│                    │  (maxjeune-      │                         │
│                    │   tgvinoui.sncf) │                         │
│                    └──────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
                               ▲
                               │ HTTP
                               │
┌─────────────────────────────────────────────────────────────────┐
│                    App Flutter (iOS/Android)                    │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────────┐     │
│  │  Calendar   │◀──▶│  Backend    │───▶│  VPS Backend     │     │
│  │  Screen     │    │  ApiService │    │  51.210.111.11   │     │
│  └─────────────┘    └─────────────┘    └──────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

## Problème résolu : DataDome

L'API SNCF (`maxjeune-tgvinoui.sncf`) est protégée par **DataDome**, un système anti-bot qui :
- Bloque les requêtes HTTP classiques (403)
- Nécessite l'exécution de JavaScript
- Génère un fingerprint navigateur
- Valide les cookies de session

**Solution** : Un backend avec Puppeteer qui lance un vrai navigateur Chrome headless.

## Backend (VPS Docker)

### Stack
- **Node.js 20** (slim)
- **Express** - Serveur HTTP
- **Puppeteer** - Contrôle Chrome headless
- **Chromium** - Navigateur système

### Fonctionnement DataDome

```javascript
// 1. Lancement du navigateur avec profil réaliste
browser = await puppeteer.launch({ headless: 'new' });
page = await browser.newPage();
await page.setUserAgent('Mozilla/5.0 ...');
await page.setViewport({ width: 1920, height: 1080 });

// 2. Navigation initiale pour obtenir les cookies DataDome
await page.goto('https://www.maxjeune-tgvinoui.sncf/recherche');

// 3. Requêtes API depuis le contexte du navigateur (cookies inclus)
const result = await page.evaluate(async (url) => {
  return await fetch(url, { credentials: 'include' });
}, apiUrl);
```

### Endpoints

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/health` | GET | Status du serveur et session |
| `/init` | POST | (Ré)initialise la session navigateur |
| `/api/stations?label=` | GET | Recherche de gares |
| `/api/trains?origin=&destination=&date=` | GET | Trains pour un jour |
| `/api/trains/month?origin=&destination=&year=&month=` | GET | Trains pour un mois |

### Gestion de session
- **Timeout** : 15 minutes d'inactivité → réinitialisation
- **Retry automatique** : Si 403, relance la session et réessaie
- **Rate limiting** : 200ms entre chaque requête (recherche mensuelle)

### Docker

```yaml
# docker-compose.yml
services:
  sncfmax-backend:
    build: .
    container_name: sncfmax-backend
    ports:
      - "3000:3000"
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN  # Requis pour Chromium sandbox
    security_opt:
      - seccomp=unconfined
```

## Frontend (Flutter)

### Structure

```
lib/
├── main.dart                 # Point d'entrée
├── models/
│   ├── station.dart          # Modèle gare (code, nom)
│   └── train_proposal.dart   # Modèle train + DayProposals
├── screens/
│   └── calendar_screen.dart  # UI principale (calendrier)
└── services/
    ├── backend_api_service.dart  # Client API vers VPS (utilisé)
    ├── sncf_api_service.dart     # Client API direct (non utilisé)
    └── cookie_manager.dart       # Gestion cookies (legacy)
```

### Flux de données

1. **Initialisation** : `BackendApiService.initialize()` → vérifie `/health`
2. **Chargement mois** : `searchTrainsForMonth()` → `/api/trains/month`
3. **Affichage** : `_proposalsMap[date]` → couleur cellule calendrier

### Code couleur calendrier

| Couleur | Signification |
|---------|---------------|
| Gris | Pas de données |
| Rouge | Aucune place |
| Jaune | 1-20 places |
| Orange | 21-50 places |
| Vert | 50+ places |

## Modèles de données

### Station
```dart
{
  "codeStation": "FRPST",   // Code SNCF
  "station": "Paris Est"     // Nom affiché
}
```

### TrainProposal
```dart
{
  "arr": "2025-01-15T12:30:00",  // Arrivée ISO
  "dep": "2025-01-15T09:00:00",  // Départ ISO
  "count": 42,                   // Places disponibles
  "dest": "Paris Est",
  "orig": "La Rochelle",
  "num": "8532",                 // Numéro train
  "type": "TGV INOUI"
}
```

### DayProposals
```dart
{
  "proposals": [...],  // Liste TrainProposal
  "ratio": 0.75        // Taux de remplissage (0-1)
}
```

## Déploiement

### Backend (VPS)

```bash
cd backend
docker-compose up -d --build
```

### Frontend (Flutter)

```bash
flutter run
# ou
flutter build ios
flutter build apk
```

## Configuration

| Variable | Fichier | Valeur |
|----------|---------|--------|
| URL Backend | `backend_api_service.dart:13` | `http://51.210.111.11:3000` |
| Session timeout | `server.js:19` | 15 minutes |
| Délai entre requêtes | `server.js:266` | 200ms |

## Limites connues

- **DataDome captcha** : Si le site détecte une activité suspecte, un captcha peut apparaître. Le backend attend 5s mais ne peut pas le résoudre automatiquement.
- **Rate limit SNCF** : Non documenté, estimé ~30-60 req/min. Le délai de 200ms devrait suffire.
- **Session unique** : Le backend maintient une seule session navigateur. Plusieurs utilisateurs simultanés partagent cette session.
