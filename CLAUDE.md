# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TGV Max Checker - A Flutter mobile app with Node.js backend that checks TGV Max (SNCF discount train) seat availability. The backend uses Puppeteer to bypass DataDome anti-bot protection on the SNCF API.

## Architecture

```
Flutter App (iOS/Android) → Backend Server (Express + Puppeteer) → SNCF API
```

- **Backend**: Node.js server running Puppeteer headless Chrome to make authenticated requests to SNCF's API (bypasses DataDome protection)
- **Flutter App**: Calendar-based UI showing train availability with color-coded days
- **Discord Bot**: Optional alerting system for availability notifications

The backend maintains a single browser session with DataDome cookies. All API requests go through `page.evaluate()` to include browser cookies.

## Common Commands

### Backend (Node.js)
```bash
cd backend
npm install           # Install dependencies
npm start             # Start server (port 3000)
npm run dev           # Start with --watch for auto-reload
docker-compose up -d --build   # Deploy with Docker
docker logs -f sncfmax-backend  # View logs
```

### Flutter
```bash
flutter pub get       # Install dependencies
flutter run           # Run on connected device/simulator
flutter build ios     # Build iOS release
flutter build apk     # Build Android release
flutter analyze       # Run static analysis
flutter test          # Run tests
```

### Discord Bot
```bash
cd discord-bot
npm install
npm start
```

## Key Configuration

| Setting | Location | Description |
|---------|----------|-------------|
| Backend URL | `lib/services/backend_api_service.dart:13` | VPS IP address |
| Session timeout | `backend/server.js:19` | 15 minutes |
| Request delay | `backend/server.js:266` | 200ms between API calls |
| Default route | `lib/screens/calendar_screen.dart:17-20` | La Rochelle → Paris |

## Backend API Endpoints

### Train Search (Public)
- `GET /health` - Server and session status
- `POST /init` - Reinitialize browser session
- `GET /api/stations?label=` - Search stations
- `GET /api/trains?origin=&destination=&date=` - Trains for one day
- `GET /api/trains/month?origin=&destination=&year=&month=` - Trains for entire month

### Mon Max - Authentication & Bookings
- `GET /api/auth/status` - Get current auth status
- `POST /api/auth/store-session` - Store user session from mobile app
- `POST /api/auth/logout` - Clear user session
- `GET /api/bookings` - Get cached bookings
- `POST /api/bookings/refresh` - Return cached bookings (for fallback)

## Mon Max Feature

The "Mon Max" feature allows users to view their TGV Max reservations.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Flutter App                                                    │
│  ┌─────────────┐    ┌──────────────────┐    ┌───────────────┐  │
│  │ Mon Max     │───▶│ WebView Login    │───▶│ SNCF Auth     │  │
│  │ Screen      │    │ (visible)        │    │ Cookies saved │  │
│  └─────────────┘    └──────────────────┘    └───────────────┘  │
│         │                                            │          │
│         │ Refresh                                    │          │
│         ▼                                            ▼          │
│  ┌─────────────────┐                    ┌───────────────────┐  │
│  │ Silent Refresh  │───────────────────▶│ WebView invisible │  │
│  │ Service         │  uses saved cookies│ fetch bookings    │  │
│  └─────────────────┘                    └───────────────────┘  │
│         │                                            │          │
│         ▼                                            ▼          │
│  ┌─────────────────┐                    ┌───────────────────┐  │
│  │ BookingsStore   │◀───────────────────│ Fresh SNCF data   │  │
│  │ (local + prefs) │                    └───────────────────┘  │
│  └─────────────────┘                                            │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────────┐                                            │
│  │ Backend Cache   │  (fallback storage)                       │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Authentication Flow

1. **Login**: User opens WebView, logs into SNCF Connect
2. **Data Fetch**: WebView JavaScript fetches user data + bookings via SNCF API
3. **Storage**: Data stored locally (SharedPreferences) + backend cache
4. **Cookies**: iOS WKWebView persists auth cookies automatically

### Silent Refresh (Key Feature)

The refresh button fetches **fresh data from SNCF** without showing login UI:

1. `SilentRefreshService` creates an invisible WebView
2. WebView reuses persisted SNCF auth cookies (iOS cookie jar)
3. JavaScript fetches bookings from SNCF API
4. Data returned to app, local store + backend updated

**Why this works**: iOS WKWebView shares cookies across WebView instances. After initial login, cookies persist and can be reused for API calls.

**Limitation**: If SNCF session expires (typically 24-48h), user must re-login via visible WebView.

### Key Files

| File | Purpose |
|------|---------|
| `lib/screens/mon_max_screen.dart` | Main bookings UI |
| `lib/screens/sncf_login_screen.dart` | WebView login + initial data fetch |
| `lib/services/silent_refresh_service.dart` | Invisible WebView refresh |
| `lib/models/booking.dart` | Booking model + BookingsStore (persistence) |
| `backend/server.js` (auth endpoints) | Backend session cache |

### SNCF API Endpoints Used

```
POST /api/public/customer/read-customer
  → Get user info + TGV Max card number

POST /api/public/reservation/travel-consultation
  → Get bookings for card number (last 90 days)
```

Headers required: `x-client-app: MAX_JEUNE`, `credentials: include`

## Code Structure

**Active files:**
- `backend/server.js` - Main backend: Express routes + Puppeteer session management
- `lib/services/backend_api_service.dart` - Flutter HTTP client (singleton)
- `lib/services/silent_refresh_service.dart` - Silent WebView refresh for Mon Max
- `lib/screens/calendar_screen.dart` - Main UI with calendar and train list
- `lib/screens/mon_max_screen.dart` - User bookings display
- `lib/screens/sncf_login_screen.dart` - WebView SNCF login
- `lib/models/train_proposal.dart` - Train/DayProposals data models
- `lib/models/booking.dart` - Booking model + BookingsStore with SharedPreferences persistence

**Legacy (not used):**
- `lib/services/sncf_api_service.dart`
- `lib/services/cookie_manager.dart`

## VPS Deployment

### Access
- **Host**: `vps` (alias configuré dans `~/.ssh/config`)
- **IP**: 51.210.111.11
- **User**: debian
- **Auth**: Clé SSH (pas de mot de passe nécessaire)

### Paths on VPS
| Service | Path | Container |
|---------|------|-----------|
| Backend | `/home/debian/sncfmax-backend` | `sncfmax-backend` (port 3000) |
| Discord Bot | `/home/debian/discord-bot` | `paris-lille-monitor` |

### Deploy Commands
```bash
# Connect to VPS
ssh vps

# Deploy backend
ssh vps "cd /home/debian/sncfmax-backend && docker-compose up -d --build"

# View backend logs
ssh vps "docker logs -f sncfmax-backend"

# Restart backend
ssh vps "docker restart sncfmax-backend"

# Copy local file to VPS
scp backend/server.js vps:/home/debian/sncfmax-backend/
```

### Quick Deploy (from local)
```bash
# Copy and rebuild
scp backend/server.js vps:/home/debian/sncfmax-backend/ && ssh vps "cd /home/debian/sncfmax-backend && docker-compose up -d --build"
```

## Known Limitations

- DataDome captcha cannot be solved automatically (backend waits 5s then continues)
- Single shared browser session for all users
- SNCF rate limit estimated ~30-60 req/min
- Mon Max: SNCF auth cookies are HttpOnly (cannot be transferred to backend)
- Mon Max: Session expires after ~24-48h, requires WebView re-login
