# SNCF Connect Booking API - Documentation

Analyse du fichier HAR `larochelle9janvier5h00.har` pour comprendre le flux de reservation.

## Flux de Reservation

```
1. Page chargee (cookies auth)
     |
     v
2. POST /bff/api/v1/itineraries  (recherche trains)
     |
     v
3. POST /bff/api/v1/book  (ajout panier)
     |
     v
4. POST /bff/api/v1/finalizations/create  (confirmation)
```

---

## 1. Recherche de Trains - `/bff/api/v1/itineraries`

### Headers Requis

```
x-bff-key: ah1MPO-izehIHD-QZZ9y88n-kku876
x-client-app-id: front-web
x-market-locale: fr_FR
x-api-env: production
x-client-channel: web
Content-Type: application/json
```

### Request Body (CRITIQUE!)

```json
{
  "schedule": {
    "outward": {
      "date": "2026-01-09T14:39:00.000Z",  // IMPORTANT: heure exacte de depart!
      "arrivalAt": false
    }
  },
  "mainJourney": {
    "origin": {
      "label": "La Rochelle Ville",
      "id": "RESARAIL_STA_8748500",
      "codes": [],
      "geolocation": false
    },
    "destination": {
      "label": "Paris",
      "id": "CITY_FR_6455259",
      "geolocation": false,
      "codes": []
    }
  },
  "passengers": [{
    "id": "08150b04-2227-4da7-9481-cb6fcf95469d",  // UUID genere
    "customerId": "100033756555",                   // ID client SNCF
    "age": 23,                                      // Age obligatoire!
    "dateOfBirth": "2002-09-21",                   // Date naissance obligatoire!
    "discountCards": [
      {
        "code": "TGV_MAX",
        "number": "29090125920426223",             // Numero carte MAX obligatoire!
        "label": "MAX JEUNE",
        "selected": true,
        "storedInAccount": true
      }
    ],
    "typology": "YOUNG",
    "displayName": "Alois Dreneri",
    "firstName": "Alois",
    "lastName": "Dreneri",
    "initials": "AD",
    "withoutSeatAssignment": false,
    "hasDisability": false,
    "hasWheelchair": false
  }],
  "pets": [],
  "forceDisplayResults": true,
  "trainExpected": true,
  "wishBike": false,
  "strictMode": false,
  "directJourney": false,
  "transporterLabels": [],
  "shortItineraryFilters": {
    "excludableLineCategories": [],
    "includibleTransportTypes": [],
    "excludableConnections": [],
    "wheelchairAccessible": "NOT_SELECTED"
  },
  "userNavigation": ["IS_NOT_BUSINESS"]
}
```

### Response (200 OK)

```json
{
  "itineraryId": "1a6a96ae-a450-4cb4-9137-0355354433ff",
  "longDistance": {
    "outward": {
      "proposals": [
        {
          "travelId": "7ea1da04-e61f-4848-a2c3-b0f3c5a0c223",
          "segments": [{
            "id": "8dc7e0e2-4d5c-42f4-8633-7b76fd01c16e",
            "departureDateTime": "2026-01-09T05:39:00",
            "transporter": {
              "number": "8370",
              "label": "TGV INOUI"
            }
          }]
        }
      ]
    }
  }
}
```

---

## 2. Ajout au Panier - `/bff/api/v1/book`

### Request Body

```json
{
  "itineraryId": "1a6a96ae-a450-4cb4-9137-0355354433ff",
  "selectedTravelId": "7ea1da04-e61f-4848-a2c3-b0f3c5a0c223",
  "discountCardPushSelected": false,
  "selectedPlacements": {
    "inwardSelectedPlacement": [],
    "outwardSelectedPlacement": [{
      "selectedPreferencesPlacementMode": {
        "berthLevelChoices": [],
        "facingForward": false,
        "placementChoices": []
      },
      "segmentId": "8dc7e0e2-4d5c-42f4-8633-7b76fd01c16e"
    }]
  },
  "segmentSelectedAdditionalServices": []
}
```

### Response (200 OK)

Contient:
- `items[0].id` = tripId pour finalisation
- `itemsByDeliveryModes[0].groupId` = groupId pour finalisation
- `buyer` = infos acheteur

---

## 3. Finalisation - `/bff/api/v1/finalizations/create`

### Request Body

```json
{
  "deliveryModes": [{
    "groupId": "e5d12e51-dcbc-4367-9cb5-07327511d18f",
    "deliveryMode": "TKD",
    "addressRequired": false
  }],
  "travelers": [{
    "tripId": "02edcd97-778e-491a-9ab0-551129febad1",
    "travelers": [{
      "civility": "MISTER",
      "dateOfBirth": "2002-09-21",
      "discountCard": {
        "number": "29090125920426223"
      },
      "firstName": "Alois",
      "lastName": "Dreneri",
      "phoneNumber": "+33629918856",
      "email": "lamerouge3@gmail.com",
      "id": "0"
    }]
  }],
  "buyer": {
    "civility": "MISTER",
    "email": "lamerouge3@gmail.com",
    "firstName": "Alois",
    "lastName": "Dreneri",
    "phoneNumber": "+33629918856"
  },
  "insurances": [],
  "donations": []
}
```

---

## Problemes Identifies dans le Code Actuel

### 1. Passager Incomplet (CAUSE PRINCIPALE du 400)

Le code actuel envoie:
```json
{
  "id": "0",
  "typology": "YOUNG",
  "discountCards": [{"code": "TGV_MAX"}],
  "withoutSeatAssignment": false
}
```

Il manque:
- **customerId** - ID client SNCF
- **age** - Age du voyageur
- **dateOfBirth** - Date de naissance
- **discountCards[].number** - Numero de carte TGV MAX!
- **firstName**, **lastName**, **displayName**

### 2. Date de Recherche Incorrecte

Le code utilise `06:00:00.000Z` au lieu de l'heure de depart du train cible.

### 3. Recuperation des Infos Utilisateur

Le code tente de recuperer les infos depuis `__NEXT_DATA__` ou `/bff/api/v1/carts`, mais ces sources ne contiennent pas:
- Le numero de carte TGV MAX
- Le customerId SNCF
- La date de naissance

---

## Solution: Recuperer les donnees utilisateur

L'info passager complete est stockee dans le state de l'application SNCF Connect.

### Approche 1: Redux Store
```javascript
// Acceder au store Redux de SNCF Connect
const store = window.__NEXT_REDUX_STORE__;
const state = store?.getState();
const user = state?.user;  // Contient firstName, lastName, dateOfBirth, etc.
```

### Approche 2: localStorage
```javascript
// SNCF Connect stocke les donnees dans localStorage
const persistedState = localStorage.getItem('persist:root');
// ou
const passengers = localStorage.getItem('passengers');
```

### Approche 3: __NEXT_DATA__
```javascript
// Donnees initiales de la page Next.js
const nextData = JSON.parse(document.getElementById('__NEXT_DATA__').textContent);
const user = nextData?.props?.pageProps?.user;
```

### Approche 4: Utiliser le formulaire de recherche existant
Naviguer vers la page de recherche pre-remplie:
```
https://www.sncf-connect.com/app/home/shop/search?
  origin=La%20Rochelle&
  destination=Paris&
  outwardDate=2026-01-09&
  outwardTime=05:39
```
Puis extraire les donnees du DOM/state apres chargement.

---

## IDs des Gares

| Code IATA | ID SNCF Connect | Label |
|-----------|-----------------|-------|
| FRLRH | RESARAIL_STA_8748500 | La Rochelle Ville |
| FRPST | CITY_FR_6455259 | Paris (toutes gares) |
| FRLYS | RESARAIL_STA_8774319 | Lyon Part-Dieu |
| FRMRS | RESARAIL_STA_8775100 | Marseille Saint-Charles |
| FRBOJ | RESARAIL_STA_8758503 | Bordeaux Saint-Jean |

---

## Headers Complets (Reference)

```
x-bff-key: ah1MPO-izehIHD-QZZ9y88n-kku876
x-client-app-id: front-web
x-market-locale: fr_FR
x-api-env: production
x-client-channel: web
x-device-class: desktop
x-visitor-type: 1
Content-Type: application/json
Accept: application/json, text/plain, */*
```
