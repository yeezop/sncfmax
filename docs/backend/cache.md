# Systeme de Cache Backend

Le backend utilise un cache en memoire pour eviter de refaire des requetes identiques a l'API SNCF. Cela ameliore significativement les performances lors des recherches mensuelles.

## Pourquoi un cache ?

Sans cache, une recherche mensuelle de 30 jours = 30 requetes API SNCF, soit environ **6-10 secondes** d'attente.

Avec cache, si les donnees sont deja en memoire, la reponse est **instantanee**.

## Fonctionnement

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│  Backend Cache  │────▶│    SNCF API     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                        ┌───────────┐
                        │  En cache │──▶ Reponse instantanee
                        │     ?     │
                        └───────────┘
                              │ Non
                              ▼
                        Fetch SNCF + Stockage
```

### Structure du cache

Le cache est une `Map` JavaScript stockee en memoire :

```javascript
cache = Map {
  "FRLPD_FRPAR_2025-01-15" => {
    data: { proposals: [...], ratio: 0.4 },
    expiresAt: 1704312000000,  // timestamp expiration
    cachedAt: 1704308400000    // timestamp creation
  },
  ...
}
```

**Cle de cache** : `{origin}_{destination}_{YYYY-MM-DD}`

Exemple : `FRLPD_FRPAR_2025-01-15` (La Rochelle -> Paris, 15 janvier 2025)

## TTL Variable (Time To Live)

Le TTL depend de la proximite de la date recherchee :

| Periode | TTL | Raison |
|---------|-----|--------|
| Aujourd'hui (J+0) | 2 min | Les places TGV Max partent tres vite |
| Demain (J+1) | 5 min | Encore volatile, reservations de derniere minute |
| Cette semaine (J+2 a J+7) | 15 min | Changements moderes |
| Au-dela (J+8+) | 1 heure | Peu de changements, stabilite |

### Logique de calcul

```javascript
function getCacheTTL(dateStr) {
  const targetDate = new Date(dateStr);
  const today = new Date();
  const diffDays = Math.floor((targetDate - today) / (1000 * 60 * 60 * 24));

  if (diffDays <= 0) return 2 * 60 * 1000;      // 2 min
  if (diffDays === 1) return 5 * 60 * 1000;     // 5 min
  if (diffDays <= 7) return 15 * 60 * 1000;     // 15 min
  return 60 * 60 * 1000;                         // 1 heure
}
```

## Scenarios d'utilisation

### Scenario 1 : Premiere recherche

```
User: Recherche janvier 2025 (La Rochelle -> Paris)
Cache: VIDE
Action: 30 requetes SNCF (environ 8 secondes)
Resultat: 30 entrees ajoutees au cache
```

### Scenario 2 : Recherche identique 5 min plus tard

```
User: Recherche janvier 2025 (La Rochelle -> Paris)
Cache: 30 entrees valides
Action: 0 requete SNCF
Resultat: Reponse instantanee (< 100ms)
Logs: "Cache: 30 hits, 0 fetched (100% hit rate)"
```

### Scenario 3 : Recherche partielle apres expiration

```
User: Recherche janvier 2025 (meme route)
Cache: 25 entrees valides, 5 expirees
Action: 5 requetes SNCF
Resultat: ~1.5 secondes
Logs: "Cache: 25 hits, 5 fetched (83% hit rate)"
```

### Scenario 4 : Route differente

```
User: Recherche janvier 2025 (Paris -> Lyon)
Cache: 30 entrees La Rochelle->Paris (inutiles)
Action: 30 requetes SNCF (nouvelle route)
Resultat: 30 nouvelles entrees ajoutees
```

## API Endpoints

### GET /api/cache/stats

Voir l'etat actuel du cache.

```bash
curl http://51.210.111.11:3000/api/cache/stats
```

Reponse :
```json
{
  "totalEntries": 45,
  "entries": [
    {
      "route": "FRLPD -> FRPAR",
      "date": "2025-01-15",
      "cachedAt": "2025-01-14T10:30:00.000Z",
      "expiresIn": "2847s",
      "hasAvailability": true
    }
  ]
}
```

### DELETE /api/cache

Vider tout le cache.

```bash
curl -X DELETE http://51.210.111.11:3000/api/cache
```

Reponse :
```json
{
  "success": true,
  "message": "Cache cleared (45 entries removed)"
}
```

### DELETE /api/cache/route

Vider le cache pour une route specifique.

```bash
curl -X DELETE "http://51.210.111.11:3000/api/cache/route?origin=FRLPD&destination=FRPAR"
```

Reponse :
```json
{
  "success": true,
  "message": "Cleared 30 entries for FRLPD -> FRPAR"
}
```

### Parametre ?refresh=true

Forcer le rafraichissement (ignorer le cache).

```bash
# Recherche jour
curl "http://51.210.111.11:3000/api/trains?origin=FRLPD&destination=FRPAR&date=2025-01-15T01:00:00.000Z&refresh=true"

# Recherche mois
curl "http://51.210.111.11:3000/api/trains/month?origin=FRLPD&destination=FRPAR&year=2025&month=1&refresh=true"
```

## Reponses enrichies

### /api/trains (jour)

```json
{
  "proposals": [...],
  "ratio": 0.4,
  "_cached": true,
  "_cachedAt": "2025-01-14T10:30:00.000Z"
}
```

### /api/trains/month

```json
{
  "results": { ... },
  "summary": {
    "totalDays": 30,
    "daysWithAvailability": 12,
    "totalTrains": 45,
    "errors": 0
  },
  "cacheInfo": {
    "fromCache": 25,
    "fetched": 5,
    "cacheHitRate": 83
  }
}
```

## Nettoyage automatique

Le cache est nettoye automatiquement toutes les 10 minutes :

```javascript
setInterval(() => {
  for (const [key, entry] of cache.entries()) {
    if (Date.now() > entry.expiresAt) {
      cache.delete(key);
    }
  }
}, 10 * 60 * 1000);
```

## Limitations

1. **Cache en memoire** : Perdu au redemarrage du serveur
2. **Pas de persistance** : Pas de stockage sur disque (Redis ou fichier)
3. **Single instance** : Pas de partage entre plusieurs instances

## Ameliorations futures possibles

- [ ] Persistance Redis pour survie au redemarrage
- [ ] Cache warming au demarrage (pre-fetch routes populaires)
- [ ] Invalidation webhook (si SNCF notifiait des changements)
- [ ] Metriques Prometheus pour monitoring
