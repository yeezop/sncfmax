import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/train_proposal.dart';
import '../models/sncf_connect_session.dart';
import '../models/booking.dart';

class BookingConfirmationScreen extends StatefulWidget {
  final TrainProposal train;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final DateTime date;

  const BookingConfirmationScreen({
    super.key,
    required this.train,
    required this.originCode,
    required this.originName,
    required this.destinationCode,
    required this.destinationName,
    required this.date,
  });

  @override
  State<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  WebViewController? _controller;
  Completer<String>? _jsCompleter;

  bool _isLoading = false;
  bool _isBookingInProgress = false;
  bool _showWebView = false;
  String _statusMessage = '';
  BookingResult? _bookingResult;

  // Colors
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF3B82F6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _errorColor = Color(0xFFEF4444);

  SncfConnectSession? _session;
  String? _tgvMaxCardNumber;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    await SncfConnectStore().loadSession();
    await BookingsStore().initialize();
    setState(() {
      _session = SncfConnectStore().session;
      _tgvMaxCardNumber = BookingsStore().userSession?.cardNumber;
    });
    debugPrint('[BookingConfirmation] Session loaded - SNCF Connect: ${_session?.isAuthenticated}, TGV Max card: ${_tgvMaxCardNumber != null}');
  }

  void _initWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('[Booking] JS Channel: ${message.message.substring(0, message.message.length > 200 ? 200 : message.message.length)}');
          if (_jsCompleter != null && !_jsCompleter!.isCompleted) {
            _jsCompleter!.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[Booking] Page started: $url');
          },
          onPageFinished: (url) {
            debugPrint('[Booking] Page finished: $url');
          },
        ),
      );
  }

  Completer<void>? _loginCompleter;

  Future<void> _waitForLogin() async {
    _loginCompleter = Completer<void>();

    // Set up navigation listener to detect successful login
    _controller!.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          debugPrint('[Booking] Login page started: $url');
        },
        onPageFinished: (url) async {
          debugPrint('[Booking] Login page finished: $url');

          // Skip about:blank
          if (url == 'about:blank' || url.isEmpty) return;

          // Detect successful OAuth redirect back to sncf-connect.com
          // After login on monidentifiant.sncf, user is redirected to sncf-connect.com
          if (url.contains('sncf-connect.com') && !url.contains('monidentifiant')) {
            // Check if this is the authenticated-redirect or a post-login page
            if (url.contains('authenticated-redirect') ||
                url.contains('/authenticate') ||
                url.contains('/home') ||
                url.contains('/compte') ||
                url == 'https://www.sncf-connect.com/' ||
                url == 'https://www.sncf-connect.com') {

              debugPrint('[Booking] Detected redirect to sncf-connect.com after login!');

              // Wait for page to settle
              await Future.delayed(const Duration(seconds: 2));

              if (_loginCompleter != null && !_loginCompleter!.isCompleted) {
                debugPrint('[Booking] Login successful via OAuth redirect!');
                _loginCompleter!.complete();
              }
            }
          }
        },
      ),
    );

    // Wait for login or timeout after 3 minutes
    try {
      await _loginCompleter!.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          debugPrint('[Booking] Login timeout');
        },
      );
    } catch (e) {
      debugPrint('[Booking] Login wait error: $e');
    }

    // Small delay to let page settle
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<String> _runJsAsync(String jsCode, {int timeoutSeconds = 30}) async {
    if (_controller == null) return '{"error": "No controller"}';

    _jsCompleter = Completer<String>();

    final wrappedJs = '''
      (async function() {
        try {
          $jsCode
        } catch(e) {
          FlutterChannel.postMessage(JSON.stringify({error: e.toString()}));
        }
      })();
    ''';

    await _controller!.runJavaScript(wrappedJs);

    return _jsCompleter!.future.timeout(
      Duration(seconds: timeoutSeconds),
      onTimeout: () => '{"error": "Timeout"}',
    );
  }

  Future<void> _startBooking() async {
    if (_isBookingInProgress) return;

    setState(() {
      _isBookingInProgress = true;
      _isLoading = true;
      _statusMessage = 'Initialisation...';
    });

    try {
      // Initialize WebView
      _initWebView();

      // Format date for SNCF search - use train departure time!
      final day = widget.date.day.toString().padLeft(2, '0');
      final month = widget.date.month.toString().padLeft(2, '0');
      final year = widget.date.year;
      final departureTime = widget.train.formattedDeparture; // "05:39" format
      final trainNumber = widget.train.trainNumber;

      // Station ID mapping - use CITY_FR IDs for cities, or RESARAIL codes for specific stations
      // SNCF Connect API accepts both formats but prefers CITY_FR for major cities
      const stationMapping = {
        // Paris - use city ID (covers all Paris stations)
        'FRPST': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPST', 'city': 'Paris'},
        'FRPLY': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPLY', 'city': 'Paris'},
        'FRPMO': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPMO', 'city': 'Paris'},
        'FRPNO': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPNO', 'city': 'Paris'},
        'FRPSL': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPSL', 'city': 'Paris'},
        'FRPAU': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPAU', 'city': 'Paris'},
        'FRPBE': {'id': 'CITY_FR_6455259', 'label': 'Paris', 'resarailCode': 'FRPBE', 'city': 'Paris'},
        // Lille - use city ID with main station code FRLIL
        'FRLIL': {'id': 'CITY_FR_6454414', 'label': 'Lille', 'resarailCode': 'FRLIL', 'city': 'Lille'},
        'FRLEF': {'id': 'CITY_FR_6454414', 'label': 'Lille', 'resarailCode': 'FRLIL', 'city': 'Lille'},
        'FRLLE': {'id': 'CITY_FR_6454414', 'label': 'Lille', 'resarailCode': 'FRLIL', 'city': 'Lille'},
        // Other major cities
        'FRLRH': {'id': 'CITY_FR_6449566', 'label': 'La Rochelle', 'resarailCode': 'FRLRH', 'city': 'La Rochelle'},
        'FRLYS': {'id': 'CITY_FR_6454573', 'label': 'Lyon', 'resarailCode': 'FRLYS', 'city': 'Lyon'},
        'FRLPD': {'id': 'CITY_FR_6454573', 'label': 'Lyon', 'resarailCode': 'FRLPD', 'city': 'Lyon'},
        'FRMRS': {'id': 'CITY_FR_6454974', 'label': 'Marseille', 'resarailCode': 'FRMRS', 'city': 'Marseille'},
        'FRBOJ': {'id': 'CITY_FR_6451348', 'label': 'Bordeaux', 'resarailCode': 'FRBOJ', 'city': 'Bordeaux'},
        'FRNTS': {'id': 'CITY_FR_6455254', 'label': 'Nantes', 'resarailCode': 'FRNTS', 'city': 'Nantes'},
        'FRNTE': {'id': 'CITY_FR_6455254', 'label': 'Nantes', 'resarailCode': 'FRNTE', 'city': 'Nantes'},
        'FRTLS': {'id': 'CITY_FR_6458094', 'label': 'Toulouse', 'resarailCode': 'FRTLS', 'city': 'Toulouse'},
        'FRSXB': {'id': 'CITY_FR_6457793', 'label': 'Strasbourg', 'resarailCode': 'FRSXB', 'city': 'Strasbourg'},
        'FRNCY': {'id': 'CITY_FR_6455213', 'label': 'Nancy', 'resarailCode': 'FRNCY', 'city': 'Nancy'},
        'FRRNS': {'id': 'CITY_FR_6456628', 'label': 'Rennes', 'resarailCode': 'FRRNS', 'city': 'Rennes'},
        'FRMPL': {'id': 'CITY_FR_6455066', 'label': 'Montpellier', 'resarailCode': 'FRMPL', 'city': 'Montpellier'},
        'FRNCE': {'id': 'CITY_FR_6455296', 'label': 'Nice', 'resarailCode': 'FRNCE', 'city': 'Nice'},
        'FRAIX': {'id': 'CITY_FR_6447068', 'label': 'Aix-en-Provence', 'resarailCode': 'FRAIX', 'city': 'Aix-en-Provence'},
        'FRAVE': {'id': 'CITY_FR_6449222', 'label': 'Avignon', 'resarailCode': 'FRAVE', 'city': 'Avignon'},
        'FRQXB': {'id': 'CITY_FR_6449669', 'label': 'Le Mans', 'resarailCode': 'FRQXB', 'city': 'Le Mans'},
        'FRQAN': {'id': 'CITY_FR_6447479', 'label': 'Angouleme', 'resarailCode': 'FRQAN', 'city': 'Angouleme'},
        'FRPIS': {'id': 'CITY_FR_6455983', 'label': 'Poitiers', 'resarailCode': 'FRPIS', 'city': 'Poitiers'},
      };

      final originMapping = stationMapping[widget.originCode];
      final destMapping = stationMapping[widget.destinationCode];

      if (originMapping == null || destMapping == null) {
        throw Exception('Gare non supportee: ${widget.originCode} ou ${widget.destinationCode}');
      }

      final originId = originMapping['id']!;
      final originLabel = originMapping['label']!;
      final destId = destMapping['id']!;
      final destLabel = destMapping['label']!;
      final destResarail = destMapping['resarailCode']!;
      final destCity = destMapping['city']!;

      debugPrint('[Booking] Train: $trainNumber a $departureTime');
      debugPrint('[Booking] Route: $originLabel -> $destLabel');

      setState(() => _statusMessage = 'Chargement SNCF Connect...');

      // Load SNCF Connect homepage to get proper context and cookies
      await _controller!.loadRequest(Uri.parse('https://www.sncf-connect.com/'));
      await Future.delayed(const Duration(seconds: 3));

      setState(() => _statusMessage = 'Verification connexion...');

      // Step 1: Check if logged in and get user data
      final userDataResult = await _runJsAsync('''
        // DEBUG: Check all possible sources of user data
        const debug = {
          hasNextData: !!document.getElementById("__NEXT_DATA__"),
          hasReduxStore: !!window.__NEXT_REDUX_STORE__,
          localStorageKeys: Object.keys(localStorage),
          url: location.href
        };

        let userData = null;
        let source = "none";

        // Method 1: Redux store (most reliable if available)
        try {
          if (window.__NEXT_REDUX_STORE__) {
            const state = window.__NEXT_REDUX_STORE__.getState();
            if (state?.user?.data) {
              userData = state.user.data;
              source = "redux";
            } else if (state?.passengers?.list?.[0]) {
              userData = state.passengers.list[0];
              source = "redux_passengers";
            }
          }
        } catch(e) { debug.reduxError = e.toString(); }

        // Method 2: localStorage persist:user or persist:passengers
        if (!userData) {
          try {
            const keys = ["persist:user", "persist:passengers", "persist:root", "sncf-user"];
            for (const key of keys) {
              const val = localStorage.getItem(key);
              if (val) {
                const parsed = JSON.parse(val);
                if (parsed.data) {
                  userData = JSON.parse(parsed.data);
                  source = "localStorage:" + key;
                  break;
                } else if (parsed.dateOfBirth) {
                  userData = parsed;
                  source = "localStorage:" + key;
                  break;
                }
              }
            }
          } catch(e) { debug.localStorageError = e.toString(); }
        }

        // Method 3: __NEXT_DATA__ props
        if (!userData) {
          try {
            const nextDataEl = document.getElementById("__NEXT_DATA__");
            if (nextDataEl) {
              const nextData = JSON.parse(nextDataEl.textContent);
              const props = nextData?.props;
              userData = props?.pageProps?.user ||
                        props?.pageProps?.passengers?.[0] ||
                        props?.initialProps?.user ||
                        props?.user;
              if (userData) source = "__NEXT_DATA__";
            }
          } catch(e) { debug.nextDataError = e.toString(); }
        }

        // Method 4: Check if logged in via indicator in DOM
        const loggedInIndicator = document.querySelector('[data-testid="user-menu"]') ||
                                  document.querySelector('.user-initials') ||
                                  document.querySelector('[class*="Avatar"]');
        debug.hasLoginIndicator = !!loggedInIndicator;
        if (loggedInIndicator) {
          debug.indicatorText = loggedInIndicator.textContent?.trim();
        }

        // Send result
        FlutterChannel.postMessage(JSON.stringify({
          step: "user_check",
          isLoggedIn: !!userData || !!loggedInIndicator,
          userData: userData,
          source: source,
          debug: debug
        }));
      ''', timeoutSeconds: 15);

      debugPrint('[Booking] User check result: $userDataResult');
      final userCheck = json.decode(userDataResult);

      if (userCheck['error'] != null) {
        throw Exception('Erreur verification: ${userCheck['error']}');
      }

      final isLoggedIn = userCheck['isLoggedIn'] == true;
      final userData = userCheck['userData'] as Map<String, dynamic>?;
      final debugInfo = userCheck['debug'];

      debugPrint('[Booking] Logged in: $isLoggedIn, Source: ${userCheck['source']}');
      debugPrint('[Booking] Debug: $debugInfo');

      // Try to get user data from SNCF Connect API
      setState(() => _statusMessage = 'Recuperation profil...');

      final profileResult = await _runJsAsync('''
        // Try to fetch user profile from SNCF Connect API
        let userData = null;

        // Method 1: Try /bff/api/v1/account or similar
        const endpoints = [
          "/bff/api/v1/account",
          "/bff/api/v1/user",
          "/bff/api/v1/profile",
          "/bff/api/v1/passengers"
        ];

        for (const endpoint of endpoints) {
          try {
            const resp = await fetch(endpoint, {
              credentials: "include",
              headers: {
                "Accept": "application/json",
                "x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876",
                "x-client-app-id": "front-web",
                "x-market-locale": "fr_FR"
              }
            });
            if (resp.ok) {
              const data = await resp.json();
              console.log("[Profile] " + endpoint + " =", JSON.stringify(data).substring(0, 200));
              if (data.firstName || data.dateOfBirth || data.passengers || data.user) {
                userData = data;
                break;
              }
            }
          } catch(e) {}
        }

        // Method 2: Navigate to account page and extract data
        if (!userData) {
          // Check if __NEXT_DATA__ has user info now
          try {
            const nextData = document.getElementById("__NEXT_DATA__");
            if (nextData) {
              const parsed = JSON.parse(nextData.textContent);
              const pageProps = parsed?.props?.pageProps;
              if (pageProps?.user) userData = pageProps.user;
              if (pageProps?.account) userData = pageProps.account;
              if (pageProps?.passengers?.[0]) userData = pageProps.passengers[0];
            }
          } catch(e) {}
        }

        // Method 3: Check for initials in DOM to confirm logged in
        let initials = null;
        const spans = document.querySelectorAll('span, div');
        for (const span of spans) {
          const text = span.textContent?.trim();
          if (text && /^[A-Z]{2}\$/.test(text) && span.offsetWidth > 0) {
            initials = text;
            break;
          }
        }

        FlutterChannel.postMessage(JSON.stringify({
          userData: userData,
          initials: initials,
          isLoggedIn: !!initials
        }));
      ''', timeoutSeconds: 15);

      debugPrint('[Booking] Profile result: $profileResult');
      final profileData = json.decode(profileResult);
      final fetchedUserData = profileData['userData'] as Map<String, dynamic>?;

      // If not logged in, show WebView for login
      if (profileData['initials'] == null && profileData['isLoggedIn'] != true) {
        debugPrint('[Booking] Not logged in, showing login WebView');
        setState(() {
          _statusMessage = 'Connexion requise...';
          _showWebView = true;
        });

        // Use direct SNCF OAuth login URL
        const loginUrl = 'https://monidentifiant.sncf/login?'
            'scope=openid%20profile%20email&'
            'response_type=code&'
            'client_id=CCL_01002&'
            'redirect_uri=https%3A%2F%2Fwww.sncf-connect.com%2Fbff%2Fapi%2Fv1%2Fauthenticated-redirect&'
            'state=eyJzIjoiUzZzaTJ1djZRTCIsInIiOiJodHRwczovL3d3dy5zbmNmLWNvbm5lY3QuY29tL2F1dGhlbnRpY2F0ZSJ9';

        await _controller!.loadRequest(Uri.parse(loginUrl));

        // Wait for user to log in (detect redirect back to sncf-connect.com)
        await _waitForLogin();

        setState(() {
          _showWebView = false;
          _statusMessage = 'Verification connexion...';
        });

        // Reload homepage to verify login status (avoid about:blank issue)
        await _controller!.loadRequest(Uri.parse('https://www.sncf-connect.com/'));
        await Future.delayed(const Duration(seconds: 3));

        // Re-check login status after login
        final reCheckResult = await _runJsAsync('''
          let initials = null;
          let isLoggedIn = false;

          // Check for user indicators
          const userMenu = document.querySelector('[data-testid="user-menu"], [class*="Avatar"], [class*="UserMenu"]');
          if (userMenu) isLoggedIn = true;

          // Check for initials
          const spans = document.querySelectorAll('span, div');
          for (const span of spans) {
            const text = span.textContent?.trim();
            if (text && /^[A-Z]{2}\$/.test(text) && span.offsetWidth > 0 && span.offsetWidth < 60) {
              initials = text;
              isLoggedIn = true;
              break;
            }
          }

          // Check localStorage for user data
          const hasUserData = localStorage.getItem('persist:user') || localStorage.getItem('sncf-user');
          if (hasUserData) isLoggedIn = true;

          FlutterChannel.postMessage(JSON.stringify({initials: initials, isLoggedIn: isLoggedIn}));
        ''', timeoutSeconds: 10);

        debugPrint('[Booking] Re-check result: $reCheckResult');
        final reCheck = json.decode(reCheckResult);
        if (reCheck['isLoggedIn'] != true) {
          throw Exception('Connexion annulee ou echouee. Reessayez.');
        }
        debugPrint('[Booking] Login successful!');
      }

      debugPrint('[Booking] User data fetched: $fetchedUserData');

      // Get stored user data from Mon Max login (same TGV MAX card!)
      await BookingsStore().initialize();
      final storedSession = BookingsStore().userSession;
      final storedCardNumber = storedSession?.cardNumber;
      final storedFirstName = storedSession?.firstName;
      final storedLastName = storedSession?.lastName;

      debugPrint('[Booking] Stored data - Card: $storedCardNumber, Name: $storedFirstName $storedLastName');

      if (storedCardNumber == null || storedCardNumber.isEmpty) {
        throw Exception('Numero de carte TGV MAX non trouve. Connectez-vous d\'abord dans Mon Max.');
      }

      setState(() => _statusMessage = 'Recherche du train...');

      // Build search date in SNCF format (YYYY-MM-DDTHH:mm:ss)
      final searchDateTime = '$year-$month-${day}T$departureTime:00';

      // Escape any special characters in names for JSON safety
      final escapedFirstName = (storedFirstName ?? '').replaceAll('"', '\\"').replaceAll('\n', '');
      final escapedLastName = (storedLastName ?? '').replaceAll('"', '\\"').replaceAll('\n', '');

      // Step 2: Search for trains with COMPLETE passenger data
      final searchResult = await _runJsAsync('''
        const storedCardNumber = "$storedCardNumber";
        const storedFirstName = "$escapedFirstName";
        const storedLastName = "$escapedLastName";
        const targetTime = "$departureTime";
        const targetTrainNumber = "$trainNumber";

        // Generate UUID for passenger
        function uuid() {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
          });
        }

        const passengerId = uuid();
        const birthYear = new Date().getFullYear() - 22;

        // Try to fetch real passenger data from SNCF session first
        let passenger = null;
        try {
          const passengersResp = await fetch("/bff/api/v1/passengers", {
            credentials: "include",
            headers: {
              "Accept": "application/json",
              "x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876",
              "x-client-app-id": "front-web",
              "x-market-locale": "fr_FR"
            }
          });
          if (passengersResp.ok) {
            const passengersData = await passengersResp.json();
            console.log("[Booking] Passengers API response:", JSON.stringify(passengersData).substring(0, 500));
            // Use the first passenger from the response
            if (passengersData.passengers && passengersData.passengers.length > 0) {
              passenger = passengersData.passengers[0];
              console.log("[Booking] Using passenger from API:", passenger.customerId);
            } else if (passengersData.length > 0) {
              passenger = passengersData[0];
              console.log("[Booking] Using passenger from array:", passenger.customerId);
            }
          }
        } catch(e) {
          console.log("[Booking] Failed to fetch passengers:", e.toString());
        }

        // Fallback: construct passenger manually if API didn't return data
        if (!passenger) {
          passenger = {
            id: passengerId,
            customerId: passengerId,
            typology: "YOUNG",
            firstName: storedFirstName || "Voyageur",
            lastName: storedLastName || "TGV Max",
            displayName: (storedFirstName && storedLastName) ? (storedFirstName + " " + storedLastName) : "Voyageur TGV Max",
            initials: (storedFirstName && storedLastName) ? (storedFirstName[0] + storedLastName[0]) : "VT",
            age: 22,
            dateOfBirth: birthYear + "-01-15",
            hasDisability: false,
            hasWheelchair: false,
            withoutSeatAssignment: false,
            discountCards: [
              {
                code: "YOUNG_PASS",
                number: storedCardNumber,
                label: "Carte Avantage Jeune"
              },
              {
                code: "MAX_JEUNE",
                number: storedCardNumber,
                label: "MAX JEUNE"
              }
            ]
          };
        }

        console.log("[Booking] Passenger:", JSON.stringify(passenger));

        // SNCF Connect format - complete search body (matches working request structure)
        const searchBody = {
          schedule: {
            outward: {
              date: "$searchDateTime.000Z",
              arrivalAt: false
            }
          },
          mainJourney: {
            origin: {
              id: "$originId",
              label: "$originLabel",
              codes: [],
              geolocation: false
            },
            destination: {
              id: "$destId",
              label: "$destLabel",
              codes: [{type: "RESARAIL", value: "$destResarail"}],
              geolocation: false,
              resarailCode: "$destResarail",
              city: "$destCity"
            }
          },
          passengers: [passenger],
          pets: [],
          metadataY: {
            decisionAction: "OUTWARD DATE"
          },
          branch: "SHOP",
          directJourney: false,
          forceDisplayResults: true,
          trainExpected: true,
          strictMode: false,
          shortItineraryFilters: {
            excludableLineCategories: [],
            includibleTransportTypes: [],
            excludableConnections: [],
            wheelchairAccessible: "NOT_SELECTED"
          },
          userNavigation: ["IS_NOT_BUSINESS"],
          wishBike: false,
          transporterLabels: []
        };

        const searchBodyStr = JSON.stringify(searchBody);

        const resp = await fetch("/bff/api/v1/itineraries", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876",
            "x-client-app-id": "front-web",
            "x-market-locale": "fr_FR",
            "x-api-env": "production",
            "x-client-channel": "web",
            "x-device-class": "desktop",
            "x-visitor-type": "1",
            "x-search-usage": "AUTOCOMPLETION",
            "virtual-env-name": "master"
          },
          body: searchBodyStr
        });

        if (!resp.ok) {
          const err = await resp.text();
          FlutterChannel.postMessage(JSON.stringify({
            error: "Recherche echouee: " + resp.status,
            details: err.substring(0, 500),
            passengerSent: JSON.stringify(passenger),
            scheduleSent: JSON.stringify(searchBody.schedule),
            mainJourneySent: JSON.stringify(searchBody.mainJourney),
            bodyLength: searchBodyStr.length
          }));
          return;
        }

        const searchData = await resp.json();
        const itineraryId = searchData.itineraryId;
        const proposals = searchData.longDistance?.outward?.proposals || [];

        console.log("[Booking] Found " + proposals.length + " proposals");

        // Find target train by time or number
        let found = null;
        for (const proposal of proposals) {
          for (const segment of (proposal.segments || [])) {
            const depTime = segment.departureDateTime;
            const trainNum = segment.transporter?.number || "";
            if (depTime) {
              const d = new Date(depTime);
              const timeStr = d.getHours().toString().padStart(2, "0") + ":" + d.getMinutes().toString().padStart(2, "0");
              console.log("[Booking] Checking train " + trainNum + " at " + timeStr);
              if (timeStr === targetTime || trainNum === targetTrainNumber) {
                found = {
                  step: "search_complete",
                  itineraryId: itineraryId,
                  selectedTravelId: proposal.travelId,
                  segmentId: segment.id,
                  trainNumber: trainNum,
                  departureTime: timeStr,
                  proposalsCount: proposals.length
                };
                break;
              }
            }
          }
          if (found) break;
        }

        if (found) {
          FlutterChannel.postMessage(JSON.stringify(found));
        } else {
          // List available trains for debug
          const available = proposals.slice(0, 5).map(p => {
            const seg = p.segments?.[0];
            if (seg) {
              const d = new Date(seg.departureDateTime);
              return (seg.transporter?.number || "?") + " a " + d.getHours() + ":" + d.getMinutes().toString().padStart(2, "0");
            }
            return "?";
          });
          FlutterChannel.postMessage(JSON.stringify({
            error: "Train " + targetTrainNumber + " (" + targetTime + ") non trouve",
            available: available.join(", "),
            totalProposals: proposals.length
          }));
        }
      ''', timeoutSeconds: 30);

      debugPrint('[Booking] Search result: $searchResult');
      final searchData = json.decode(searchResult);

      if (searchData['error'] != null) {
        // Log debug info
        debugPrint('[Booking] === DEBUG INFO ===');
        debugPrint('[Booking] Body length: ${searchData['bodyLength']}');
        debugPrint('[Booking] Passenger sent: ${searchData['passengerSent']}');
        debugPrint('[Booking] Schedule sent: ${searchData['scheduleSent']}');
        debugPrint('[Booking] MainJourney sent: ${searchData['mainJourneySent']}');
        debugPrint('[Booking] Error details: ${searchData['details']}');
        throw Exception('${searchData['error']}');
      }

      setState(() => _statusMessage = 'Ajout au panier...');

      // Book the train
      final bookResult = await _runJsAsync('''
        const bookBody = {
          itineraryId: "${searchData['itineraryId']}",
          selectedTravelId: "${searchData['selectedTravelId']}",
          discountCardPushSelected: false,
          selectedPlacements: {
            inwardSelectedPlacement: [],
            outwardSelectedPlacement: [{
              selectedPreferencesPlacementMode: {
                berthLevelChoices: [],
                facingForward: false,
                placementChoices: []
              },
              segmentId: "${searchData['segmentId']}"
            }]
          },
          segmentSelectedAdditionalServices: []
        };

        console.log("[Booking] Book body:", JSON.stringify(bookBody));

        const resp = await fetch("/bff/api/v1/book", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876",
            "x-client-app-id": "front-web",
            "x-market-locale": "fr_FR",
            "x-api-env": "production",
            "x-client-channel": "web"
          },
          body: JSON.stringify(bookBody)
        });

        if (!resp.ok) {
          const err = await resp.text();
          FlutterChannel.postMessage(JSON.stringify({
            error: "Ajout panier: " + resp.status,
            details: err.substring(0, 300)
          }));
          return;
        }

        const data = await resp.json();
        console.log("[Booking] Book response:", JSON.stringify(data).substring(0, 500));

        if (data.items?.length > 0) {
          const trip = data.items[0];
          FlutterChannel.postMessage(JSON.stringify({
            step: "book_complete",
            tripId: trip.id,
            groupId: data.itemsByDeliveryModes?.[0]?.groupId,
            traveler: trip.trip?.travelers?.[0],
            buyer: data.buyer
          }));
        } else {
          FlutterChannel.postMessage(JSON.stringify({
            error: "Panier vide apres reservation",
            response: JSON.stringify(data).substring(0, 300)
          }));
        }
      ''', timeoutSeconds: 20);

      debugPrint('[Booking] Book result: $bookResult');
      final bookData = json.decode(bookResult);

      if (bookData['error'] != null) {
        throw Exception('${bookData['error']}\\n${bookData['details'] ?? ''}');
      }

      setState(() => _statusMessage = 'Finalisation...');

      // Finalize
      final finalResult = await _runJsAsync('''
        const traveler = ${json.encode(bookData['traveler'])};
        const buyer = ${json.encode(bookData['buyer'])};

        // Build traveler with discount card number
        const travelerData = {
          civility: traveler?.civility || buyer?.civility || "MISTER",
          dateOfBirth: traveler?.dateOfBirth || buyer?.dateOfBirth,
          firstName: traveler?.firstName || buyer?.firstName,
          lastName: traveler?.lastName || buyer?.lastName,
          phoneNumber: traveler?.phoneNumber || buyer?.phoneNumber,
          email: traveler?.email || buyer?.email,
          id: traveler?.id || "0"
        };

        // Add discount card if available
        if (traveler?.discountCard?.number) {
          travelerData.discountCard = {number: traveler.discountCard.number};
        }

        const body = {
          deliveryModes: [{
            groupId: "${bookData['groupId']}",
            deliveryMode: "TKD",
            addressRequired: false
          }],
          travelers: [{
            tripId: "${bookData['tripId']}",
            travelers: [travelerData]
          }],
          buyer: {
            civility: buyer?.civility || "MISTER",
            email: buyer?.email,
            firstName: buyer?.firstName,
            lastName: buyer?.lastName,
            phoneNumber: buyer?.phoneNumber
          },
          insurances: [],
          donations: []
        };

        console.log("[Booking] Finalize body:", JSON.stringify(body));

        const resp = await fetch("/bff/api/v1/finalizations/create", {
          method: "POST",
          credentials: "include",
          headers: {
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "x-bff-key": "ah1MPO-izehIHD-QZZ9y88n-kku876",
            "x-client-app-id": "front-web",
            "x-market-locale": "fr_FR",
            "x-api-env": "production",
            "x-client-channel": "web"
          },
          body: JSON.stringify(body)
        });

        if (!resp.ok) {
          const err = await resp.text();
          FlutterChannel.postMessage(JSON.stringify({
            error: "Finalisation: " + resp.status,
            details: err.substring(0, 300)
          }));
          return;
        }

        const data = await resp.json();
        console.log("[Booking] Finalize response:", JSON.stringify(data).substring(0, 500));

        FlutterChannel.postMessage(JSON.stringify({
          success: true,
          confirmationNumber: data.order?.reference || data.orderId || "OK"
        }));
      ''', timeoutSeconds: 20);

      debugPrint('[Booking] Final result: $finalResult');
      final finalData = json.decode(finalResult);

      if (finalData['error'] != null) {
        throw Exception('${finalData['error']}\\n${finalData['details'] ?? ''}');
      }

      setState(() {
        _isLoading = false;
        _statusMessage = '';
        _bookingResult = BookingResult(
          success: true,
          confirmationNumber: finalData['confirmationNumber'] ?? 'OK',
          message: 'Reservation confirmee!',
        );
      });

    } catch (e) {
      debugPrint('[Booking] Error: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = '';
        _bookingResult = BookingResult(
          success: false,
          message: e.toString(),
        );
      });
    } finally {
      setState(() => _isBookingInProgress = false);
    }
  }

  String _formatDate() {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
    return '${days[widget.date.weekday - 1]} ${widget.date.day} ${months[widget.date.month - 1]} ${widget.date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_showWebView && _controller != null) ...[
              // Show WebView for login
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(PhosphorIcons.signIn(PhosphorIconsStyle.fill), size: 20, color: _accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Connectez-vous a SNCF Connect',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _accentColor),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: WebViewWidget(controller: _controller!),
                ),
              ),
            ] else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTrainCard(),
                      const SizedBox(height: 20),
                      if (_session != null && _session!.isAuthenticated)
                        _buildUserCard(),
                      const SizedBox(height: 20),
                      _buildPriceCard(),
                      const SizedBox(height: 24),
                      if (_bookingResult != null)
                        _buildResultCard()
                      else if (_isLoading)
                        _buildLoadingCard()
                      else
                        _buildBookButton(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: IconButton(
              icon: Icon(
                PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                size: 22,
                color: _textSecondary,
              ),
              onPressed: () => Navigator.of(context).pop(_bookingResult?.success ?? false),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.ticket(PhosphorIconsStyle.fill),
                      size: 18,
                      color: _textPrimary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Confirmer la reservation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.train(PhosphorIconsStyle.fill), size: 14, color: _textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.train.trainType} ${widget.train.trainNumber}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFBBF7D0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.armchair(PhosphorIconsStyle.fill), size: 14, color: const Color(0xFF166534)),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.train.availableSeats} places',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.train.formattedDeparture,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.originName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold), size: 20, color: _textMuted),
                  const SizedBox(height: 4),
                  Text(
                    widget.train.formattedDuration,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.train.formattedArrival,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.destinationName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _session?.displayName?.isNotEmpty == true
                    ? _session!.displayName!.substring(0, min(_session!.displayName!.length, 2)).toUpperCase()
                    : 'U',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voyageur',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _session?.displayName ?? 'Utilisateur',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
            size: 20,
            color: _successColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _successColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _successColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.tag(PhosphorIconsStyle.fill),
            size: 24,
            color: _successColor,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tarif MAX JEUNE',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  'Place gratuite avec votre abonnement',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '0 EUR',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _successColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _accentColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusMessage,
            style: const TextStyle(
              fontSize: 14,
              color: _textSecondary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final isSuccess = _bookingResult!.success;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isSuccess ? _successColor.withValues(alpha: 0.1) : _errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuccess ? _successColor.withValues(alpha: 0.3) : _errorColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            isSuccess
                ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                : PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
            size: 48,
            color: isSuccess ? _successColor : _errorColor,
          ),
          const SizedBox(height: 12),
          Text(
            isSuccess ? 'Reservation confirmee!' : 'Erreur',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isSuccess ? _successColor : _errorColor,
            ),
          ),
          if (_bookingResult!.confirmationNumber != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reference: ${_bookingResult!.confirmationNumber}',
              style: const TextStyle(
                fontSize: 14,
                color: _textSecondary,
              ),
            ),
          ],
          if (!isSuccess) ...[
            const SizedBox(height: 8),
            Text(
              _bookingResult!.message,
              style: const TextStyle(
                fontSize: 13,
                color: _textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _bookingResult = null;
                });
              },
              child: const Text('Reessayer'),
            ),
          ],
          if (isSuccess) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _successColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Fermer',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookButton() {
    final isConnected = _session?.isAuthenticated ?? false;
    final hasCardNumber = _tgvMaxCardNumber != null && _tgvMaxCardNumber!.isNotEmpty;

    // Check if TGV Max card number is missing
    if (!hasCardNumber) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), size: 24, color: Colors.orange),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Connectez-vous dans Mon Max pour recuperer votre numero de carte TGV MAX.',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    if (!isConnected) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(PhosphorIcons.warning(PhosphorIconsStyle.fill), size: 24, color: Colors.orange),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Connectez-vous a SNCF Connect dans les Reglages pour reserver.',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _startBooking,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _accentColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.ticket(PhosphorIconsStyle.fill),
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            const Text(
              'Reserver ce train',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingResult {
  final bool success;
  final String? confirmationNumber;
  final String message;

  BookingResult({
    required this.success,
    this.confirmationNumber,
    required this.message,
  });
}
