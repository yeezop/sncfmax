const express = require('express');
const puppeteer = require('puppeteer');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const app = express();

// === SECURITY CONFIG ===
const API_KEY = process.env.API_KEY;
const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',')
  : ['http://localhost:3000'];

// CORS configuration
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, etc.)
    if (!origin) return callback(null, true);
    if (ALLOWED_ORIGINS.includes(origin) || ALLOWED_ORIGINS.includes('*')) {
      return callback(null, true);
    }
    return callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
}));

app.use(express.json());

// Rate limiting
const limiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 100, // 100 requests per minute
  message: { error: 'Too many requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// API Key authentication middleware
const authenticateApiKey = (req, res, next) => {
  // Skip auth if no API_KEY is configured (dev mode)
  if (!API_KEY) {
    return next();
  }

  const providedKey = req.headers['x-api-key'];
  if (!providedKey || providedKey !== API_KEY) {
    return res.status(401).json({ error: 'Unauthorized: Invalid or missing API key' });
  }
  next();
};

// Apply API key auth to all routes except health
app.use((req, res, next) => {
  if (req.path === '/health') {
    return next();
  }
  return authenticateApiKey(req, res, next);
});

// Admin-only middleware for sensitive endpoints
const ADMIN_KEY = process.env.ADMIN_KEY;
const IS_PRODUCTION = process.env.NODE_ENV === 'production';

const adminOnly = (req, res, next) => {
  // In production, require admin key
  if (IS_PRODUCTION) {
    const providedKey = req.headers['x-admin-key'];
    if (!ADMIN_KEY || !providedKey || providedKey !== ADMIN_KEY) {
      return res.status(403).json({ error: 'Forbidden: Admin access required' });
    }
  }
  next();
};

// Stricter rate limit for admin endpoints
const adminLimiter = rateLimit({
  windowMs: 1 * 60 * 1000,
  max: 10, // 10 requests per minute for admin endpoints
  message: { error: 'Too many admin requests' },
});

const PORT = process.env.PORT || 3000;
const SNCF_BASE_URL = 'https://www.maxjeune-tgvinoui.sncf';
const API_BASE_URL = `${SNCF_BASE_URL}/api/public/refdata`;

// Proxy configuration from environment variables
const PROXY_CONFIG = {
  host: process.env.PROXY_HOST,
  port: parseInt(process.env.PROXY_PORT) || 16666,
  username: process.env.PROXY_USERNAME,
  password: process.env.PROXY_PASSWORD,
};
const USE_PROXY = process.env.USE_PROXY !== 'false' && PROXY_CONFIG.host;

let browser = null;
let page = null;
let isReady = false;
let lastActivity = Date.now();
let initializingPromise = null; // Mutex for browser initialization

// Session timeout (2 hours - extended to minimize proxy usage)
const SESSION_TIMEOUT = 2 * 60 * 60 * 1000;

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

async function initBrowserInternal() {
  if (browser) {
    try {
      await browser.close();
    } catch (e) {
      // Ignore
    }
  }

  log('Launching browser...');
  if (USE_PROXY) {
    log(`Using proxy: ${PROXY_CONFIG.host}:${PROXY_CONFIG.port}`);
  }

  const launchArgs = [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--disable-accelerated-2d-canvas',
    '--disable-gpu',
    '--window-size=1920,1080',
    '--single-process',
  ];

  // Add proxy server argument if enabled
  if (USE_PROXY) {
    launchArgs.push(`--proxy-server=${PROXY_CONFIG.host}:${PROXY_CONFIG.port}`);
  }

  const launchOptions = {
    headless: 'new',
    args: launchArgs,
  };

  // Use system Chromium if available (Docker)
  if (process.env.PUPPETEER_EXECUTABLE_PATH) {
    launchOptions.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
  }

  browser = await puppeteer.launch(launchOptions);

  page = await browser.newPage();

  // Authenticate with proxy if enabled
  if (USE_PROXY) {
    await page.authenticate({
      username: PROXY_CONFIG.username,
      password: PROXY_CONFIG.password,
    });
    log('Proxy authentication configured');
  }

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

  // Block unnecessary resources to save proxy bandwidth
  await page.setRequestInterception(true);
  page.on('request', (req) => {
    const resourceType = req.resourceType();
    const url = req.url();

    // Block all non-essential resource types
    if (['image', 'font', 'stylesheet', 'media', 'texttrack', 'manifest'].includes(resourceType)) {
      req.abort();
      return;
    }

    // Block tracking/analytics scripts and other unnecessary domains
    const blockedDomains = [
      'google-analytics', 'gtag', 'googletagmanager',
      'facebook', 'fbcdn', 'hotjar', 'clarity.ms',
      'doubleclick', 'adsense', 'adservice',
      'sentry.io', 'newrelic', 'nr-data',
      'onetrust', 'cookielaw', 'didomi',
      'youtube', 'vimeo', 'twitter', 'linkedin'
    ];

    if (blockedDomains.some(d => url.includes(d))) {
      req.abort();
      return;
    }

    // Only allow captcha-delivery.com (DataDome) and main domain
    if (resourceType === 'script') {
      if (!url.includes('captcha-delivery.com') && !url.includes('maxjeune-tgvinoui.sncf')) {
        req.abort();
        return;
      }
    }

    req.continue();
  });
  log('Request interception enabled (minimal mode - only DataDome + essential)');

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
    const pageTitle = await page.title();
    log(`Page title: ${pageTitle}`);

    if (pageContent.includes('captcha') || pageContent.includes('DataDome') || pageContent.includes('blocked')) {
      log('Captcha/Block detected! Page content preview:');
      log(pageContent.substring(0, 500));
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

// Mutex-protected browser initialization
async function initBrowser() {
  // If already initializing, wait for that to complete
  if (initializingPromise) {
    log('Browser init already in progress, waiting...');
    return initializingPromise;
  }

  initializingPromise = initBrowserInternal();
  try {
    await initializingPromise;
  } finally {
    initializingPromise = null;
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

async function makeApiRequest(url, retryCount = 0) {
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

        const text = await response.text();
        let data;
        try {
          data = JSON.parse(text);
        } catch {
          data = { raw: text.substring(0, 500) };
        }
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
      log(`Got 403 (attempt ${retryCount + 1}). Response: ${JSON.stringify(result.data).substring(0, 300)}`);
      if (retryCount >= 2) {
        throw new Error('Got 403 after retries - DataDome blocking');
      }
      // Rotate proxy IP by reinitializing browser
      log('Rotating proxy IP due to 403...');
      isReady = false;
      await initBrowser();
      return makeApiRequest(url, retryCount + 1);
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
    proxy: {
      enabled: USE_PROXY,
      host: USE_PROXY ? PROXY_CONFIG.host : null,
    },
  });
});

// Check current proxy IP (admin only)
app.get('/api/proxy/ip', adminLimiter, adminOnly, async (req, res) => {
  try {
    await ensureSession();

    const result = await page.evaluate(async () => {
      try {
        const response = await fetch('https://ipinfo.io/json', {
          method: 'GET',
        });
        return { success: true, data: await response.json() };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });

    if (result.success) {
      log(`Current IP: ${result.data.ip} (${result.data.city}, ${result.data.country})`);
      res.json({
        proxyEnabled: USE_PROXY,
        ...result.data,
      });
    } else {
      throw new Error(result.error);
    }
  } catch (error) {
    log(`Error checking IP: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// Force new proxy IP (reinitialize browser session) (admin only)
app.post('/api/proxy/rotate', adminLimiter, adminOnly, async (req, res) => {
  try {
    log('Rotating proxy IP (reinitializing browser)...');
    isReady = false;
    await initBrowser();

    // Check new IP
    const result = await page.evaluate(async () => {
      try {
        const response = await fetch('https://ipinfo.io/json');
        return { success: true, data: await response.json() };
      } catch (error) {
        return { success: false, error: error.message };
      }
    });

    if (result.success) {
      log(`New IP: ${result.data.ip} (${result.data.city}, ${result.data.country})`);
      res.json({
        success: true,
        message: 'Proxy IP rotated',
        newIp: result.data.ip,
        location: `${result.data.city}, ${result.data.country}`,
      });
    } else {
      res.json({ success: true, message: 'Browser reinitialized, could not verify IP' });
    }
  } catch (error) {
    log(`Error rotating proxy: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Cache statistics endpoint (admin only)
app.get('/api/cache/stats', adminLimiter, adminOnly, (req, res) => {
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

// Clear entire cache (admin only)
app.delete('/api/cache', adminLimiter, adminOnly, (req, res) => {
  const count = cache.size;
  cache.clear();
  log(`Cache cleared: ${count} entries removed`);
  res.json({ success: true, message: `Cache cleared (${count} entries removed)` });
});

// Clear cache for specific route (admin only)
app.delete('/api/cache/route', adminLimiter, adminOnly, (req, res) => {
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

// Initialize/reinitialize browser session (admin only)
app.post('/init', adminLimiter, adminOnly, async (req, res) => {
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

// Search trains for entire month (parallelized)
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

    // Collect all days to fetch
    const daysToFetch = [];
    for (let day = new Date(firstDay); day <= lastDay; day.setDate(day.getDate() + 1)) {
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

      daysToFetch.push({
        dayKey,
        cacheKey,
        date: new Date(day.getTime()),
      });
    }

    log(`Monthly search: ${monthNum}/${yearNum}, ${origin} -> ${destination} | Cache: ${fromCache.length}, To fetch: ${daysToFetch.length}${forceRefresh ? ' (force refresh)' : ''}`);

    // Fetch days in parallel batches (6 = Chrome connection limit per domain)
    const BATCH_SIZE = 6;
    const DELAY_BETWEEN_BATCHES = 30; // ms

    for (let i = 0; i < daysToFetch.length; i += BATCH_SIZE) {
      const batch = daysToFetch.slice(i, i + BATCH_SIZE);

      const batchPromises = batch.map(async ({ dayKey, cacheKey, date }) => {
        try {
          const dateStr = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 1)).toISOString();
          const url = `${API_BASE_URL}/search-freeplaces-proposals?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&departureDateTime=${encodeURIComponent(dateStr)}`;
          const data = await makeApiRequest(url);

          // Cache with appropriate TTL
          const ttl = getCacheTTL(dayKey);
          setCache(cacheKey, data, ttl);

          return { dayKey, data, success: true };
        } catch (error) {
          log(`Error for ${dayKey}: ${error.message}`);
          return { dayKey, error: error.message, success: false };
        }
      });

      const batchResults = await Promise.all(batchPromises);

      for (const result of batchResults) {
        if (result.success) {
          results[result.dayKey] = result.data;
          fetched.push(result.dayKey);
        } else {
          errors.push({ date: result.dayKey, error: result.error });
          results[result.dayKey] = { proposals: [], ratio: 0 };
        }
      }

      // Small delay between batches to avoid rate limiting
      if (i + BATCH_SIZE < daysToFetch.length) {
        await new Promise(resolve => setTimeout(resolve, DELAY_BETWEEN_BATCHES));
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

// Multi-user session storage (userId -> session data)
const userSessions = new Map();
const userBookingsCache = new Map();

// Session cleanup (remove sessions older than 24 hours)
const SESSION_MAX_AGE = 24 * 60 * 60 * 1000;
setInterval(() => {
  const now = Date.now();
  let cleaned = 0;
  for (const [userId, session] of userSessions.entries()) {
    if (now - session.createdAt > SESSION_MAX_AGE) {
      userSessions.delete(userId);
      userBookingsCache.delete(userId);
      cleaned++;
    }
  }
  if (cleaned > 0) {
    log(`Session cleanup: ${cleaned} expired sessions removed`);
  }
}, 60 * 60 * 1000); // Check every hour

// Helper to get userId from request (from header or generate)
function getUserId(req) {
  return req.headers['x-user-id'] || 'anonymous';
}

function getUserSession(userId) {
  return userSessions.get(userId) || {
    isAuthenticated: false,
    cardNumber: null,
    lastName: null,
    firstName: null,
    email: null,
  };
}

function setUserSession(userId, session) {
  userSessions.set(userId, {
    ...session,
    createdAt: Date.now(),
  });
}

// Get authentication status and login URL
app.get('/api/auth/status', (req, res) => {
  const userId = getUserId(req);
  const userSession = getUserSession(userId);

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
  const userId = getUserId(req);
  const userSession = getUserSession(userId);
  const cachedBookings = userBookingsCache.get(userId) || [];

  log(`Checking authentication status for user: ${userId}`);

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
app.post('/api/auth/store-session', (req, res) => {
  const userId = getUserId(req);
  const { user, bookings } = req.body;

  if (!user) {
    return res.status(400).json({ error: 'user data required' });
  }

  const newSession = {
    isAuthenticated: true,
    cardNumber: user.cardNumber || null,
    lastName: user.lastName,
    firstName: user.firstName,
    email: user.email,
  };

  setUserSession(userId, newSession);
  userBookingsCache.set(userId, bookings || []);

  const cachedBookings = userBookingsCache.get(userId);
  log(`Session stored for ${userId}: ${newSession.firstName} ${newSession.lastName} with ${cachedBookings.length} bookings`);

  res.json({
    success: true,
    isAuthenticated: true,
    user: newSession,
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
      const userId = getUserId(req);
      const card = result.data.cards?.find(c => c.productType === 'TGV_MAX_JEUNE');
      const newSession = {
        isAuthenticated: true,
        cardNumber: card?.cardNumber || null,
        lastName: result.data.lastName,
        firstName: result.data.firstName,
        email: result.data.email,
      };

      setUserSession(userId, newSession);

      log(`Cookie sync successful for ${userId}! User: ${newSession.firstName} ${newSession.lastName}`);
      res.json({
        success: true,
        isAuthenticated: true,
        user: {
          cardNumber: newSession.cardNumber,
          lastName: newSession.lastName,
          firstName: newSession.firstName,
          email: newSession.email,
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
  const userId = getUserId(req);

  userSessions.delete(userId);
  userBookingsCache.delete(userId);

  log(`User ${userId} logged out`);
  res.json({ success: true });
});

// Get user bookings (returns cached data from WebView)
app.get('/api/bookings', (req, res) => {
  const userId = getUserId(req);
  const userSession = getUserSession(userId);
  const cachedBookings = userBookingsCache.get(userId) || [];

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
  const userId = getUserId(req);
  const userSession = getUserSession(userId);
  const cachedBookings = userBookingsCache.get(userId) || [];

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
  const userId = getUserId(req);
  const userSession = getUserSession(userId);

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

// Debug endpoint to check rate limit headers (admin only, dev only)
app.get('/api/debug-headers', adminLimiter, adminOnly, async (req, res) => {
  // Only allow in non-production
  if (IS_PRODUCTION && !ADMIN_KEY) {
    return res.status(404).json({ error: 'Not found' });
  }
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

// =====================================
// PUPPETEER AUTH ENDPOINTS (Auto-Confirm)
// Backend-based authentication for automatic confirmations
// Runs PARALLEL to existing WebView auth
// =====================================

const sncfAuth = require('./sncf-auth-service');

// Get proxy config for auth service
function getProxyConfig() {
  if (!USE_PROXY) return null;
  return PROXY_CONFIG;
}

// Login via Puppeteer (stores credentials-based session)
app.post('/api/puppeteer/login', async (req, res) => {
  const userId = getUserId(req);
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'email et password requis' });
  }

  log(`[PuppeteerAuth] Login attempt for user: ${userId}`);

  try {
    const result = await sncfAuth.loginUser(userId, email, password, getProxyConfig());

    if (result.success) {
      res.json({
        success: true,
        session: result.session,
        bookingsCount: result.bookingsCount,
      });
    } else if (result.needs2FA) {
      res.json({
        success: false,
        needs2FA: true,
        message: result.message,
      });
    } else {
      res.status(401).json({
        success: false,
        error: result.error,
      });
    }
  } catch (error) {
    log(`[PuppeteerAuth] Login error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Submit 2FA code
app.post('/api/puppeteer/2fa', async (req, res) => {
  const userId = getUserId(req);
  const { code } = req.body;

  if (!code) {
    return res.status(400).json({ error: 'code requis' });
  }

  try {
    const result = await sncfAuth.submit2FACode(userId, code);
    res.json(result);
  } catch (error) {
    log(`[PuppeteerAuth] 2FA error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get Puppeteer auth status
app.get('/api/puppeteer/status', (req, res) => {
  const userId = getUserId(req);
  const status = sncfAuth.getSessionStatus(userId);
  res.json(status);
});

// Refresh bookings via Puppeteer session
app.post('/api/puppeteer/bookings/refresh', async (req, res) => {
  const userId = getUserId(req);

  try {
    const result = await sncfAuth.refreshBookings(userId);

    if (result.needsReauth) {
      return res.status(401).json({ success: false, needsReauth: true, error: result.error });
    }

    res.json(result);
  } catch (error) {
    log(`[PuppeteerAuth] Refresh error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get bookings from Puppeteer session
app.get('/api/puppeteer/bookings', (req, res) => {
  const userId = getUserId(req);
  const status = sncfAuth.getSessionStatus(userId);

  if (!status.isAuthenticated) {
    return res.status(401).json({ error: 'Non authentifié via Puppeteer' });
  }

  // Need to refresh to get bookings
  res.json({
    message: 'Use POST /api/puppeteer/bookings/refresh to get fresh bookings',
    bookingsCount: status.bookingsCount,
  });
});

// Confirm a booking via Puppeteer
app.post('/api/puppeteer/confirm', async (req, res) => {
  const userId = getUserId(req);
  const { booking } = req.body;

  if (!booking) {
    return res.status(400).json({ error: 'booking requis' });
  }

  try {
    const result = await sncfAuth.confirmBooking(userId, booking);

    if (result.needsReauth) {
      return res.status(401).json({ success: false, needsReauth: true });
    }

    res.json(result);
  } catch (error) {
    log(`[PuppeteerAuth] Confirm error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Cancel a booking via Puppeteer
app.post('/api/puppeteer/cancel', async (req, res) => {
  const userId = getUserId(req);
  const { booking, customerName } = req.body;

  if (!booking || !customerName) {
    return res.status(400).json({ error: 'booking et customerName requis' });
  }

  try {
    const result = await sncfAuth.cancelBooking(userId, booking, customerName);

    if (result.needsReauth) {
      return res.status(401).json({ success: false, needsReauth: true });
    }

    res.json(result);
  } catch (error) {
    log(`[PuppeteerAuth] Cancel error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Logout from Puppeteer session
app.post('/api/puppeteer/logout', async (req, res) => {
  const userId = getUserId(req);

  try {
    await sncfAuth.logoutUser(userId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// =====================================
// AUTO-CONFIRM ENDPOINTS
// Schedule automatic booking confirmations
// =====================================

// Schedule auto-confirmation for a booking
app.post('/api/auto-confirm/schedule', (req, res) => {
  const userId = getUserId(req);
  const { booking } = req.body;

  if (!booking) {
    return res.status(400).json({ error: 'booking requis' });
  }

  // Check if user is authenticated via Puppeteer
  const status = sncfAuth.getSessionStatus(userId);
  if (!status.isAuthenticated) {
    return res.status(401).json({
      error: 'Authentification Puppeteer requise pour l\'auto-confirmation',
      needsReauth: true,
    });
  }

  const result = sncfAuth.scheduleAutoConfirm(userId, booking);
  res.json(result);
});

// Cancel scheduled auto-confirmation
app.delete('/api/auto-confirm/:bookingKey', (req, res) => {
  const { bookingKey } = req.params;

  const result = sncfAuth.cancelAutoConfirm(decodeURIComponent(bookingKey));
  res.json(result);
});

// Get all scheduled auto-confirmations for user
app.get('/api/auto-confirm', (req, res) => {
  const userId = getUserId(req);
  const schedule = sncfAuth.getAutoConfirmSchedule(userId);

  res.json({
    count: schedule.length,
    schedule: schedule.map(s => ({
      key: s.key,
      trainNumber: s.booking.trainNumber,
      departure: s.booking.departureDateTime,
      origin: s.booking.origin?.label,
      destination: s.booking.destination?.label,
      status: s.status,
      scheduledAt: new Date(s.scheduledAt).toISOString(),
    })),
  });
});

// Force check auto-confirmations now (admin only)
app.post('/api/auto-confirm/check-now', adminLimiter, adminOnly, async (req, res) => {
  try {
    await sncfAuth.checkAutoConfirmations();
    res.json({ success: true, message: 'Auto-confirmations checked' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Debug: Get all active Puppeteer sessions (admin only)
app.get('/api/puppeteer/debug/sessions', adminLimiter, adminOnly, (req, res) => {
  res.json({
    activeSessions: sncfAuth.getActiveSessions(),
    autoConfirmCount: sncfAuth.getAutoConfirmCount(),
  });
});

// Graceful shutdown
process.on('SIGINT', async () => {
  log('Shutting down...');
  sncfAuth.stopPeriodicTasks();
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

  // Start auto-confirm periodic tasks
  sncfAuth.startPeriodicTasks();
  log('Auto-confirm service started (checks every 5 minutes)');
});
