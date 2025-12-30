const express = require('express');
const puppeteer = require('puppeteer');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const SNCF_BASE_URL = 'https://www.maxjeune-tgvinoui.sncf';
const API_BASE_URL = `${SNCF_BASE_URL}/api/public/refdata`;

let browser = null;
let page = null;
let isReady = false;
let lastActivity = Date.now();

// Session timeout (15 minutes)
const SESSION_TIMEOUT = 15 * 60 * 1000;

// === CACHE SYSTEM ===
const cache = new Map();

function getCacheTTL(dateStr) {
  const targetDate = new Date(dateStr);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const diffDays = Math.floor((targetDate - today) / (1000 * 60 * 60 * 24));

  if (diffDays <= 0) return 2 * 60 * 1000;      // 2 min - aujourd'hui
  if (diffDays === 1) return 5 * 60 * 1000;     // 5 min - demain
  if (diffDays <= 7) return 15 * 60 * 1000;     // 15 min - cette semaine
  return 60 * 60 * 1000;                         // 1 heure - au-delà
}

function getCacheKey(origin, destination, date) {
  return `${origin}_${destination}_${date}`;
}

function getFromCache(key) {
  const entry = cache.get(key);
  if (!entry) return null;

  if (Date.now() > entry.expiresAt) {
    cache.delete(key);
    return null;
  }
  return { data: entry.data, cachedAt: entry.cachedAt };
}

function setCache(key, data, ttl) {
  cache.set(key, {
    data,
    expiresAt: Date.now() + ttl,
    cachedAt: Date.now()
  });
}

// Nettoyage périodique du cache (toutes les 10 min)
setInterval(() => {
  const now = Date.now();
  let cleaned = 0;
  for (const [key, entry] of cache.entries()) {
    if (now > entry.expiresAt) {
      cache.delete(key);
      cleaned++;
    }
  }
  if (cleaned > 0) {
    log(`Cache cleanup: ${cleaned} expired entries removed, ${cache.size} remaining`);
  }
}, 10 * 60 * 1000);

function log(message) {
  console.log(`[${new Date().toISOString()}] ${message}`);
}

async function initBrowser() {
  if (browser) {
    try {
      await browser.close();
    } catch (e) {
      // Ignore
    }
  }

  log('Launching browser...');

  const launchOptions = {
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-accelerated-2d-canvas',
      '--disable-gpu',
      '--window-size=1920,1080',
      '--single-process',
    ],
  };

  // Use system Chromium if available (Docker)
  if (process.env.PUPPETEER_EXECUTABLE_PATH) {
    launchOptions.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
  }

  browser = await puppeteer.launch(launchOptions);

  page = await browser.newPage();

  // Set realistic user agent
  await page.setUserAgent(
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  );

  // Set viewport
  await page.setViewport({ width: 1920, height: 1080 });

  // Set extra headers
  await page.setExtraHTTPHeaders({
    'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
  });

  log('Navigating to SNCF website...');

  try {
    // Navigate to the search page to initialize session
    await page.goto(`${SNCF_BASE_URL}/recherche`, {
      waitUntil: 'networkidle2',
      timeout: 60000,
    });

    // Wait for the page to be fully loaded
    await page.waitForSelector('body', { timeout: 30000 });

    // Check if we hit a captcha
    const pageContent = await page.content();
    if (pageContent.includes('captcha') || pageContent.includes('DataDome')) {
      log('Captcha detected! Waiting for manual resolution...');
      // Wait longer for captcha to be resolved
      await new Promise(resolve => setTimeout(resolve, 5000));
    }

    log('Browser session initialized successfully');
    isReady = true;
    lastActivity = Date.now();

  } catch (error) {
    log(`Error initializing browser: ${error.message}`);
    isReady = false;
    throw error;
  }
}

async function ensureSession() {
  const now = Date.now();

  // Check if session has timed out
  if (now - lastActivity > SESSION_TIMEOUT) {
    log('Session timeout, reinitializing...');
    isReady = false;
  }

  if (!isReady || !browser || !page) {
    await initBrowser();
  }

  lastActivity = now;
}

async function makeApiRequest(url) {
  await ensureSession();

  log(`Fetching: ${url}`);

  try {
    // Use page.evaluate to make fetch request with browser cookies
    const result = await page.evaluate(async (apiUrl) => {
      try {
        const response = await fetch(apiUrl, {
          method: 'GET',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Accept-Language': 'fr-FR,fr;q=0.9',
            'x-client-app': 'MAX_JEUNE',
            'x-client-app-version': '2.45.1',
            'x-distribution-channel': 'OUI',
          },
        });

        const data = await response.json();
        return {
          success: true,
          status: response.status,
          data: data,
        };
      } catch (error) {
        return {
          success: false,
          error: error.message,
        };
      }
    }, url);

    if (!result.success) {
      throw new Error(result.error);
    }

    if (result.status === 403) {
      log('Got 403, session may be invalid. Reinitializing...');
      isReady = false;
      await ensureSession();
      // Retry once
      return makeApiRequest(url);
    }

    return result.data;

  } catch (error) {
    log(`API request error: ${error.message}`);
    throw error;
  }
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    ready: isReady,
    lastActivity: new Date(lastActivity).toISOString(),
    cacheSize: cache.size,
  });
});

// Cache statistics endpoint
app.get('/api/cache/stats', (req, res) => {
  const now = Date.now();
  const entries = [];

  for (const [key, entry] of cache.entries()) {
    const [origin, destination, date] = key.split('_');
    const ttlRemaining = Math.max(0, Math.round((entry.expiresAt - now) / 1000));
    entries.push({
      route: `${origin} -> ${destination}`,
      date,
      cachedAt: new Date(entry.cachedAt).toISOString(),
      expiresIn: `${ttlRemaining}s`,
      hasAvailability: entry.data?.ratio > 0
    });
  }

  res.json({
    totalEntries: cache.size,
    entries: entries.sort((a, b) => a.date.localeCompare(b.date))
  });
});

// Clear entire cache
app.delete('/api/cache', (req, res) => {
  const count = cache.size;
  cache.clear();
  log(`Cache cleared: ${count} entries removed`);
  res.json({ success: true, message: `Cache cleared (${count} entries removed)` });
});

// Clear cache for specific route
app.delete('/api/cache/route', (req, res) => {
  const { origin, destination } = req.query;

  if (!origin || !destination) {
    return res.status(400).json({ error: 'origin and destination parameters required' });
  }

  let count = 0;
  const prefix = `${origin}_${destination}_`;

  for (const key of cache.keys()) {
    if (key.startsWith(prefix)) {
      cache.delete(key);
      count++;
    }
  }

  log(`Route cache cleared: ${origin} -> ${destination}, ${count} entries removed`);
  res.json({ success: true, message: `Cleared ${count} entries for ${origin} -> ${destination}` });
});

// Initialize/reinitialize browser session
app.post('/init', async (req, res) => {
  try {
    await initBrowser();
    res.json({ success: true, message: 'Browser session initialized' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Search stations
app.get('/api/stations', async (req, res) => {
  const { label } = req.query;

  if (!label) {
    return res.status(400).json({ error: 'label parameter required' });
  }

  try {
    const url = `${API_BASE_URL}/freeplaces-stations?label=${encodeURIComponent(label)}`;
    const data = await makeApiRequest(url);
    res.json(data);
  } catch (error) {
    log(`Error searching stations: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// Search trains for a specific day
app.get('/api/trains', async (req, res) => {
  const { origin, destination, date, refresh } = req.query;
  const forceRefresh = refresh === 'true';

  if (!origin || !destination || !date) {
    return res.status(400).json({
      error: 'origin, destination, and date parameters required'
    });
  }

  try {
    // Extract date key from ISO string (YYYY-MM-DD)
    const dateObj = new Date(date);
    const dayKey = `${dateObj.getFullYear()}-${String(dateObj.getMonth() + 1).padStart(2, '0')}-${String(dateObj.getDate()).padStart(2, '0')}`;
    const cacheKey = getCacheKey(origin, destination, dayKey);

    // Check cache first (unless force refresh)
    if (!forceRefresh) {
      const cached = getFromCache(cacheKey);
      if (cached) {
        log(`Cache hit for ${dayKey}: ${origin} -> ${destination}`);
        return res.json({
          ...cached.data,
          _cached: true,
          _cachedAt: new Date(cached.cachedAt).toISOString()
        });
      }
    }

    const url = `${API_BASE_URL}/search-freeplaces-proposals?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&departureDateTime=${encodeURIComponent(date)}`;
    const data = await makeApiRequest(url);

    // Cache with appropriate TTL
    const ttl = getCacheTTL(dayKey);
    setCache(cacheKey, data, ttl);

    res.json({ ...data, _cached: false });
  } catch (error) {
    log(`Error searching trains: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// Search trains for entire month
app.get('/api/trains/month', async (req, res) => {
  const { origin, destination, year, month, refresh } = req.query;
  const forceRefresh = refresh === 'true';

  if (!origin || !destination || !year || !month) {
    return res.status(400).json({
      error: 'origin, destination, year, and month parameters required'
    });
  }

  try {
    const yearNum = parseInt(year);
    const monthNum = parseInt(month);
    const firstDay = new Date(yearNum, monthNum - 1, 1);
    const lastDay = new Date(yearNum, monthNum, 0);
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const results = {};
    const errors = [];
    const fromCache = [];
    const fetched = [];

    log(`Monthly search: ${monthNum}/${yearNum}, ${origin} -> ${destination}${forceRefresh ? ' (force refresh)' : ''}`);

    for (let day = new Date(firstDay); day <= lastDay; day.setDate(day.getDate() + 1)) {
      // Skip past days
      if (day < today) continue;

      const dayKey = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
      const cacheKey = getCacheKey(origin, destination, dayKey);

      // Check cache first (unless force refresh)
      if (!forceRefresh) {
        const cached = getFromCache(cacheKey);
        if (cached) {
          results[dayKey] = cached.data;
          fromCache.push(dayKey);
          continue;
        }
      }

      // Fetch from API
      try {
        const dateStr = new Date(Date.UTC(day.getFullYear(), day.getMonth(), day.getDate(), 1)).toISOString();
        const url = `${API_BASE_URL}/search-freeplaces-proposals?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&departureDateTime=${encodeURIComponent(dateStr)}`;
        const data = await makeApiRequest(url);

        // Cache with appropriate TTL
        const ttl = getCacheTTL(dayKey);
        setCache(cacheKey, data, ttl);
        results[dayKey] = data;
        fetched.push(dayKey);

        // Small delay between requests
        await new Promise(resolve => setTimeout(resolve, 200));

      } catch (error) {
        log(`Error for ${dayKey}: ${error.message}`);
        errors.push({ date: dayKey, error: error.message });
        results[dayKey] = { proposals: [], ratio: 0 };
      }
    }

    // Summary
    const totalDays = Object.keys(results).length;
    const daysWithAvailability = Object.values(results).filter(d => d.ratio > 0).length;
    const totalTrains = Object.values(results).reduce((sum, d) => sum + (d.proposals?.length || 0), 0);

    log(`Monthly summary: ${totalDays} days, ${daysWithAvailability} with availability, ${totalTrains} trains | Cache: ${fromCache.length} hits, ${fetched.length} fetched`);

    res.json({
      results,
      summary: {
        totalDays,
        daysWithAvailability,
        totalTrains,
        errors: errors.length,
      },
      cacheInfo: {
        fromCache: fromCache.length,
        fetched: fetched.length,
        cacheHitRate: totalDays > 0 ? Math.round((fromCache.length / totalDays) * 100) : 0
      }
    });

  } catch (error) {
    log(`Error in monthly search: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// =====================================
// AUTHENTICATED ENDPOINTS (Mon Max)
// =====================================

// Store user session data
let userSession = {
  isAuthenticated: false,
  cardNumber: null,
  lastName: null,
  firstName: null,
  email: null,
};

// Get authentication status and login URL
app.get('/api/auth/status', (req, res) => {
  res.json({
    isAuthenticated: userSession.isAuthenticated,
    user: userSession.isAuthenticated ? {
      cardNumber: userSession.cardNumber,
      lastName: userSession.lastName,
      firstName: userSession.firstName,
      email: userSession.email,
    } : null,
    loginUrl: `${SNCF_BASE_URL}/sncf-connect/mes-voyages`,
  });
});

// Navigate to login page (for WebView)
app.post('/api/auth/login', async (req, res) => {
  try {
    await ensureSession();

    log('Navigating to SNCF Connect login page...');
    await page.goto(`${SNCF_BASE_URL}/sncf-connect/mes-voyages`, {
      waitUntil: 'networkidle2',
      timeout: 60000,
    });

    res.json({
      success: true,
      message: 'Ready for login',
      url: `${SNCF_BASE_URL}/sncf-connect/mes-voyages`
    });
  } catch (error) {
    log(`Error navigating to login: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Check if user is logged in (returns stored session from mobile app)
app.post('/api/auth/check', (req, res) => {
  log('Checking authentication status...');

  if (userSession.isAuthenticated) {
    log(`User authenticated: ${userSession.firstName} ${userSession.lastName} (${cachedBookings.length} bookings cached)`);
    res.json({
      success: true,
      isAuthenticated: true,
      user: {
        cardNumber: userSession.cardNumber,
        lastName: userSession.lastName,
        firstName: userSession.firstName,
        email: userSession.email,
      }
    });
  } else {
    log('User not authenticated');
    res.json({ success: true, isAuthenticated: false });
  }
});

// Store session data from mobile app (WebView fetched the data directly)
let cachedBookings = [];

app.post('/api/auth/store-session', (req, res) => {
  const { user, bookings } = req.body;

  if (!user) {
    return res.status(400).json({ error: 'user data required' });
  }

  userSession = {
    isAuthenticated: true,
    cardNumber: user.cardNumber || null,
    lastName: user.lastName,
    firstName: user.firstName,
    email: user.email,
  };

  cachedBookings = bookings || [];

  log(`Session stored: ${userSession.firstName} ${userSession.lastName} with ${cachedBookings.length} bookings`);

  res.json({
    success: true,
    isAuthenticated: true,
    user: userSession,
    bookingsCount: cachedBookings.length,
  });
});

// Sync cookies from mobile app WebView
app.post('/api/auth/sync-cookies', async (req, res) => {
  const { cookies } = req.body;

  if (!cookies) {
    return res.status(400).json({ error: 'cookies parameter required' });
  }

  try {
    await ensureSession();

    log('Syncing cookies from mobile app...');

    // Parse cookies string into array
    const cookieList = cookies.split('; ').map(c => {
      const [name, ...valueParts] = c.split('=');
      return { name: name.trim(), value: valueParts.join('=') };
    });

    // Set cookies in Puppeteer browser
    for (const cookie of cookieList) {
      if (cookie.name && cookie.value) {
        await page.setCookie({
          name: cookie.name,
          value: cookie.value,
          domain: '.maxjeune-tgvinoui.sncf',
          path: '/',
        });
      }
    }

    log(`Set ${cookieList.length} cookies in browser session`);

    // Navigate to trigger authentication
    await page.goto(`${SNCF_BASE_URL}/sncf-connect/mes-voyages`, {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });

    // Try to fetch customer data to verify authentication
    const result = await page.evaluate(async (baseUrl) => {
      try {
        const response = await fetch(`${baseUrl}/api/public/customer/read-customer`, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-client-app': 'MAX_JEUNE',
            'x-client-app-version': '2.45.1',
          },
          body: JSON.stringify({
            productTypes: ['TGV_MAX_JEUNE', 'FIDEL', 'IDTGV_MAX']
          }),
        });

        if (response.status === 401 || response.status === 403) {
          return { authenticated: false };
        }

        const data = await response.json();
        return { authenticated: true, data };
      } catch (error) {
        return { authenticated: false, error: error.message };
      }
    }, SNCF_BASE_URL);

    if (result.authenticated && result.data) {
      const card = result.data.cards?.find(c => c.productType === 'TGV_MAX_JEUNE');
      userSession = {
        isAuthenticated: true,
        cardNumber: card?.cardNumber || null,
        lastName: result.data.lastName,
        firstName: result.data.firstName,
        email: result.data.email,
      };

      log(`Cookie sync successful! User: ${userSession.firstName} ${userSession.lastName}`);
      res.json({
        success: true,
        isAuthenticated: true,
        user: {
          cardNumber: userSession.cardNumber,
          lastName: userSession.lastName,
          firstName: userSession.firstName,
          email: userSession.email,
        }
      });
    } else {
      log('Cookie sync: Not authenticated after sync');
      res.json({ success: true, isAuthenticated: false });
    }
  } catch (error) {
    log(`Error syncing cookies: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Logout
app.post('/api/auth/logout', async (req, res) => {
  userSession = {
    isAuthenticated: false,
    cardNumber: null,
    lastName: null,
    firstName: null,
    email: null,
  };

  // Clear browser session
  if (page) {
    try {
      const client = await page.target().createCDPSession();
      await client.send('Network.clearBrowserCookies');
      await client.send('Network.clearBrowserCache');
    } catch (e) {
      log(`Error clearing browser data: ${e.message}`);
    }
  }

  log('User logged out');
  res.json({ success: true });
});

// Get user bookings (returns cached data from WebView)
app.get('/api/bookings', (req, res) => {
  if (!userSession.isAuthenticated) {
    return res.status(401).json({ error: 'Not authenticated' });
  }

  log(`Returning ${cachedBookings.length} cached bookings for ${userSession.firstName}`);

  res.json({
    bookings: cachedBookings,
    user: {
      firstName: userSession.firstName,
      lastName: userSession.lastName,
    }
  });
});

// Refresh bookings - returns cached bookings from last login
// (Cannot fetch fresh data without user re-authenticating due to HttpOnly cookies)
app.post('/api/bookings/refresh', (req, res) => {
  if (!userSession.isAuthenticated) {
    return res.status(401).json({ error: 'Not authenticated', needsReauth: true });
  }

  log(`Returning ${cachedBookings.length} cached bookings for ${userSession.firstName}`);

  res.json({
    success: true,
    bookings: cachedBookings,
    user: {
      firstName: userSession.firstName,
      lastName: userSession.lastName,
      cardNumber: userSession.cardNumber,
    }
  });
});

// Get booking details
app.post('/api/bookings/details', async (req, res) => {
  if (!userSession.isAuthenticated) {
    return res.status(401).json({ error: 'Not authenticated' });
  }

  const { customerName, departureDateTime, marketingCarrierRef, trainNumber } = req.body;

  if (!customerName || !departureDateTime || !marketingCarrierRef || !trainNumber) {
    return res.status(400).json({ error: 'Missing required parameters' });
  }

  try {
    await ensureSession();

    log(`Fetching booking details for train ${trainNumber}...`);

    const result = await page.evaluate(async (baseUrl, params) => {
      try {
        const response = await fetch(`${baseUrl}/api/public/reservation/get-travel`, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-client-app': 'MAX_JEUNE',
            'x-client-app-version': '2.45.1',
            'x-distribution-channel': 'OUI',
          },
          body: JSON.stringify(params),
        });

        if (!response.ok) {
          return { success: false, status: response.status };
        }

        const data = await response.json();
        return { success: true, data };
      } catch (error) {
        return { success: false, error: error.message };
      }
    }, SNCF_BASE_URL, { customerName, departureDateTime, marketingCarrierRef, trainNumber });

    if (result.success) {
      res.json(result.data);
    } else {
      throw new Error(result.error || `HTTP ${result.status}`);
    }
  } catch (error) {
    log(`Error fetching booking details: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// Debug endpoint to check rate limit headers
app.get('/api/debug-headers', async (req, res) => {
  try {
    await ensureSession();

    const url = `${API_BASE_URL}/freeplaces-stations?label=Paris`;
    log(`Debug headers for: ${url}`);

    const result = await page.evaluate(async (apiUrl) => {
      try {
        const response = await fetch(apiUrl, {
          method: 'GET',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Accept-Language': 'fr-FR,fr;q=0.9',
            'x-client-app': 'MAX_JEUNE',
            'x-client-app-version': '2.45.1',
            'x-distribution-channel': 'OUI',
          },
        });

        // Capture all headers
        const headers = {};
        response.headers.forEach((value, key) => {
          headers[key] = value;
        });

        return {
          success: true,
          status: response.status,
          statusText: response.statusText,
          headers: headers,
        };
      } catch (error) {
        return {
          success: false,
          error: error.message,
        };
      }
    }, url);

    // Log interesting headers
    if (result.success) {
      log('=== Response Headers ===');
      const interestingKeys = ['rate', 'limit', 'retry', 'x-', 'cf-', 'cache', 'throttle'];
      for (const [key, value] of Object.entries(result.headers)) {
        const keyLower = key.toLowerCase();
        if (interestingKeys.some(k => keyLower.includes(k))) {
          log(`  ${key}: ${value}`);
        }
      }
      log('========================');
    }

    res.json(result);

  } catch (error) {
    log(`Error in debug-headers: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// Graceful shutdown
process.on('SIGINT', async () => {
  log('Shutting down...');
  if (browser) {
    await browser.close();
  }
  process.exit(0);
});

// Start server
app.listen(PORT, async () => {
  log(`Server running on http://localhost:${PORT}`);
  log('Initializing browser session...');

  try {
    await initBrowser();
    log('Server ready!');
  } catch (error) {
    log(`Warning: Initial browser setup failed: ${error.message}`);
    log('Use POST /init to retry initialization');
  }
});
