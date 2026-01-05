/**
 * SNCF Authentication Service via Puppeteer
 * Handles user login, session management, and auto-confirmation
 *
 * This runs PARALLEL to the existing WebView-based auth system
 */

const puppeteer = require('puppeteer');

const SNCF_BASE_URL = 'https://www.maxjeune-tgvinoui.sncf';

// Store for authenticated user sessions (separate from main browser)
// userId -> { browser, page, session, bookings, lastActivity }
const authenticatedSessions = new Map();

// Auto-confirmation schedules
// bookingKey -> { userId, booking, scheduledAt, status }
const autoConfirmSchedule = new Map();

// Session timeout: 2 hours (SNCF sessions last ~24-48h but we refresh earlier)
const AUTH_SESSION_TIMEOUT = 2 * 60 * 60 * 1000;

// Check interval for auto-confirmations: every 5 minutes
const AUTO_CONFIRM_CHECK_INTERVAL = 5 * 60 * 1000;

function log(message) {
  console.log(`[${new Date().toISOString()}] [SNCFAuth] ${message}`);
}

/**
 * Get booking unique key
 */
function getBookingKey(booking) {
  return `${booking.orderId}_${booking.trainNumber}_${booking.departureDateTime}`;
}

/**
 * Create a new browser instance for a user session
 */
async function createUserBrowser(proxyConfig) {
  const launchArgs = [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--disable-accelerated-2d-canvas',
    '--disable-gpu',
    '--window-size=1920,1080',
    '--disable-blink-features=AutomationControlled', // Hide automation
  ];

  if (proxyConfig?.host) {
    launchArgs.push(`--proxy-server=${proxyConfig.host}:${proxyConfig.port}`);
  }

  const launchOptions = {
    headless: 'new',
    args: launchArgs,
  };

  if (process.env.PUPPETEER_EXECUTABLE_PATH) {
    launchOptions.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
  }

  const browser = await puppeteer.launch(launchOptions);
  const page = await browser.newPage();

  if (proxyConfig?.host && proxyConfig?.username) {
    await page.authenticate({
      username: proxyConfig.username,
      password: proxyConfig.password,
    });
  }

  // Use a modern Chrome user agent that SNCF will accept
  await page.setUserAgent(
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
  );

  await page.setViewport({ width: 1920, height: 1080 });

  await page.setExtraHTTPHeaders({
    'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
  });

  // Hide webdriver property
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });

  return { browser, page };
}

/**
 * Login user via Puppeteer
 * @param {string} userId - Unique user identifier
 * @param {string} email - SNCF account email
 * @param {string} password - SNCF account password
 * @param {object} proxyConfig - Optional proxy configuration (NOT used for auth - causes issues)
 * @returns {object} - { success, session, error, needs2FA }
 */
async function loginUser(userId, email, password, proxyConfig = null) {
  log(`========== LOGIN START ==========`);
  log(`User: ${userId}`);
  log(`Email: ${email.substring(0, 3)}***@***`);

  try {
    // Close existing session if any
    log(`[1/10] Fermeture session existante...`);
    await logoutUser(userId);

    // Don't use proxy for auth - it causes tunnel failures
    log(`[2/10] Création navigateur Puppeteer...`);
    const { browser, page } = await createUserBrowser(null);
    log(`[2/10] ✓ Navigateur créé`);

    // Navigate to login page
    log(`[3/10] Navigation vers Max Jeune...`);
    await page.goto(`${SNCF_BASE_URL}/sncf-connect/mes-voyages`, {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    log(`[3/10] ✓ Page chargée: ${page.url()}`);

    // Wait for page to load
    await new Promise(resolve => setTimeout(resolve, 3000));

    // Accept cookies if banner present
    log(`[4/10] Recherche bannière cookies...`);
    try {
      const acceptButton = await page.$('button.didomi-dismiss-button');
      if (acceptButton) {
        log(`[4/10] Clic sur "Accepter cookies"...`);
        await acceptButton.click();
        await new Promise(resolve => setTimeout(resolve, 1500));
        log(`[4/10] ✓ Cookies acceptés`);
      } else {
        log(`[4/10] Pas de bannière cookies`);
      }
    } catch (e) {
      log(`[4/10] Erreur cookies (ignorée): ${e.message}`);
    }

    // Check current URL
    log(`[5/10] URL actuelle: ${page.url()}`);

    // Look for "Me connecter" button on the page (Max Jeune specific)
    log(`[5/10] Recherche bouton "Me connecter"...`);
    try {
      // Find the button first
      const buttonSelector = await page.evaluate(() => {
        const buttons = document.querySelectorAll('button, a');
        for (let i = 0; i < buttons.length; i++) {
          const btn = buttons[i];
          const text = btn.innerText?.trim().toLowerCase() || '';
          if (text === 'me connecter' || text.includes('me connecter')) {
            // Add a temporary ID to find it
            btn.id = 'tmp-login-btn';
            return '#tmp-login-btn';
          }
        }
        return null;
      });

      if (buttonSelector) {
        log(`[5/10] ✓ Bouton trouvé, clic + attente navigation...`);

        // Listen for new page/popup
        const newPagePromise = new Promise(resolve => {
          browser.once('targetcreated', async target => {
            const newPage = await target.page();
            if (newPage) {
              log(`[5/10] ✓ Nouvelle page/popup détectée!`);
              resolve(newPage);
            }
          });
          // Timeout after 10s
          setTimeout(() => resolve(null), 10000);
        });

        // Click and wait for navigation OR popup
        const navigationPromise = page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 15000 }).catch(e => {
          log(`[5/10] Pas de navigation dans la page principale`);
          return null;
        });

        await page.click(buttonSelector);
        log(`[5/10] ✓ Clic effectué`);

        // Wait for either navigation or new page
        const [navResult, newPage] = await Promise.all([navigationPromise, newPagePromise]);

        if (newPage) {
          log(`[5/10] ✓ Popup ouvert, on bascule dessus`);
          page = newPage; // Switch to the popup page
          await page.setViewport({ width: 1920, height: 1080 });
          await new Promise(resolve => setTimeout(resolve, 2000));
        } else {
          await new Promise(resolve => setTimeout(resolve, 2000));
        }
      } else {
        log(`[5/10] ✗ Bouton "Me connecter" non trouvé`);
      }
    } catch (e) {
      log(`[5/10] Erreur clic login: ${e.message}`);
    }

    // Should now be on auth.monidentifiant.sncf
    log(`[6/10] URL après clic: ${page.url()}`);

    // If still on maxjeune, try direct navigation to auth page
    if (!page.url().includes('auth.monidentifiant.sncf') && !page.url().includes('login')) {
      log(`[6/10] Toujours sur maxjeune, tentative navigation directe vers auth...`);

      // Check for iframes
      const frames = page.frames();
      log(`[6/10] Nombre de frames: ${frames.length}`);
      for (const frame of frames) {
        const frameUrl = frame.url();
        if (frameUrl.includes('auth') || frameUrl.includes('login')) {
          log(`[6/10] ✓ Frame auth trouvée: ${frameUrl}`);
        }
      }

      // Try navigating directly to the SNCF Connect login
      log(`[6/10] Navigation directe vers sncf-connect login...`);
      await page.goto('https://www.sncf-connect.com/app/account/login', {
        waitUntil: 'networkidle2',
        timeout: 30000,
      });
      log(`[6/10] URL après navigation directe: ${page.url()}`);

      // Wait for SPA to fully render
      log(`[6/10] Attente chargement SPA (5s)...`);
      await new Promise(resolve => setTimeout(resolve, 5000));

      // Check for redirect to auth.monidentifiant.sncf
      const currentUrl = page.url();
      log(`[6/10] URL après attente SPA: ${currentUrl}`);

      if (currentUrl.includes('auth.monidentifiant.sncf')) {
        log(`[6/10] ✓ Redirigé vers auth.monidentifiant.sncf`);
      }
    }

    // Wait for email input - try multiple selectors
    log(`[7/10] Attente champ email...`);
    const emailSelectors = [
      'input[name="email"]',
      'input[type="email"]',
      'input#email',
      'input[autocomplete="email"]',
      'input[placeholder*="mail"]',
      'input[data-testid*="email"]',
    ];

    let emailInput = null;
    for (const selector of emailSelectors) {
      try {
        await page.waitForSelector(selector, { timeout: 5000 });
        emailInput = await page.$(selector);
        if (emailInput) {
          log(`[7/10] ✓ Champ email trouvé avec: ${selector}`);
          break;
        }
      } catch (e) {
        // Try next selector
      }
    }

    if (!emailInput) {
      // Log page content for debugging
      const html = await page.content();
      const pageText = await page.evaluate(() => document.body.innerText.substring(0, 500));
      log(`[7/10] ✗ Champ email non trouvé!`);
      log(`[7/10] URL: ${page.url()}`);
      log(`[7/10] Text: ${pageText.substring(0, 200)}`);
      throw new Error('Could not find email input field on auth page');
    }

    // Fill email using the found input
    log(`[7/10] Saisie email...`);
    await emailInput.type(email, { delay: 30 });
    log(`[7/10] ✓ Email saisi`);

    // Click "Se connecter" button
    await new Promise(resolve => setTimeout(resolve, 500));
    log(`[7/10] Clic "Se connecter"...`);
    await page.click('button[type="submit"]');
    log(`[7/10] ✓ Bouton cliqué`);

    // Wait for password page
    await new Promise(resolve => setTimeout(resolve, 3000));
    log(`[8/10] URL après email: ${page.url()}`);

    // Wait for password field (using name="password" as per SNCF HTML)
    log(`[8/10] Attente champ password...`);
    try {
      await page.waitForSelector('input[name="password"]', { timeout: 10000 });
      log(`[8/10] ✓ Champ password trouvé (input[name="password"])`);
    } catch (e) {
      const pageText = await page.evaluate(() => document.body.innerText);
      log(`[8/10] ✗ Champ password non trouvé!`);
      log(`[8/10] Page text: ${pageText.substring(0, 200)}`);
      if (pageText.includes('incorrect') || pageText.includes('invalide')) {
        throw new Error('Email incorrect ou compte inexistant');
      }
      throw new Error('Could not find password input field');
    }

    // Fill password
    log(`[9/10] Saisie password...`);
    await page.type('input[name="password"]', password, { delay: 30 });
    log(`[9/10] ✓ Password saisi`);

    // Submit login
    await new Promise(resolve => setTimeout(resolve, 500));
    log(`[9/10] Clic submit login...`);
    await page.click('button[type="submit"]');
    log(`[9/10] ✓ Login soumis`);

    // Wait for redirect back to Max Jeune or 2FA
    await new Promise(resolve => setTimeout(resolve, 5000));
    log(`[10/10] URL finale: ${page.url()}`);

    // Check for 2FA prompt (MuiOtpInput = 6 separate input fields)
    log(`[10/10] Vérification 2FA...`);
    const has2FA = await page.evaluate(() => {
      // Look for the MuiOtpInput fields (6 separate inputs)
      const otpInputs = document.querySelectorAll('.MuiOtpInput-TextField input, input[inputmode="numeric"]');
      const pageText = document.body.innerText || '';
      return otpInputs.length >= 6 ||
             pageText.includes('code') && (pageText.includes('SMS') || pageText.includes('vérification') || pageText.includes('reçu'));
    });

    if (has2FA) {
      log('[10/10] ✓ 2FA détecté - en attente du code SMS');
      authenticatedSessions.set(userId, {
        browser,
        page,
        session: null,
        bookings: [],
        lastActivity: Date.now(),
        pending2FA: true,
      });
      return { success: false, needs2FA: true, message: 'Code 2FA requis - vérifie tes SMS' };
    }

    // Check if login successful by trying to fetch customer data
    log('Verifying login...');
    const customerResult = await page.evaluate(async (baseUrl) => {
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

        if (!response.ok) {
          return { success: false, status: response.status };
        }

        return { success: true, data: await response.json() };
      } catch (error) {
        return { success: false, error: error.message };
      }
    }, SNCF_BASE_URL);

    if (!customerResult.success) {
      log(`Login verification failed: ${customerResult.error || customerResult.status}`);
      await browser.close();
      return { success: false, error: 'Échec de la connexion - vérifiez vos identifiants' };
    }

    // Extract user info
    const card = customerResult.data.cards?.find(c => c.productType === 'TGV_MAX_JEUNE');
    const session = {
      isAuthenticated: true,
      cardNumber: card?.cardNumber || null,
      lastName: customerResult.data.lastName,
      firstName: customerResult.data.firstName,
      email: customerResult.data.email,
    };

    log(`Login successful: ${session.firstName} ${session.lastName}`);

    // Fetch initial bookings
    const bookings = await fetchBookingsInternal(page, session.cardNumber);

    // Store session
    authenticatedSessions.set(userId, {
      browser,
      page,
      session,
      bookings,
      lastActivity: Date.now(),
      pending2FA: false,
    });

    return { success: true, session, bookingsCount: bookings.length };

  } catch (error) {
    log(`Login error: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Submit 2FA code
 * SNCF uses MuiOtpInput with 6 separate input fields
 */
async function submit2FACode(userId, code) {
  const userSession = authenticatedSessions.get(userId);
  if (!userSession || !userSession.pending2FA) {
    return { success: false, error: 'Pas de session 2FA en attente' };
  }

  const { browser, page } = userSession;

  try {
    log(`========== 2FA SUBMIT ==========`);
    log(`[2FA-1/5] User: ${userId}, Code: ${code.substring(0, 2)}****`);

    // Wait for OTP inputs to be present
    log(`[2FA-2/5] Recherche champs OTP (MuiOtpInput)...`);

    // Try to find the 6 MuiOtpInput fields
    const otpInputsFound = await page.evaluate(() => {
      const inputs = document.querySelectorAll('.MuiOtpInput-TextField input');
      return inputs.length;
    });

    log(`[2FA-2/5] Trouvé ${otpInputsFound} champs OTP`);

    if (otpInputsFound >= 6) {
      // Fill each OTP input field separately
      log(`[2FA-3/5] Saisie code dans les 6 champs...`);
      for (let i = 0; i < 6; i++) {
        const digit = code[i];
        if (!digit) break;

        const selector = `.MuiOtpInput-TextField-${i + 1} input`;
        try {
          await page.waitForSelector(selector, { timeout: 2000 });
          await page.click(selector);
          await page.type(selector, digit, { delay: 50 });
          log(`[2FA-3/5] ✓ Digit ${i + 1}/6 saisi`);
        } catch (e) {
          // Fallback: try generic selector with nth-child
          const fallbackSelector = `.MuiOtpInput-TextField:nth-child(${i + 1}) input`;
          try {
            await page.click(fallbackSelector);
            await page.type(fallbackSelector, digit, { delay: 50 });
            log(`[2FA-3/5] ✓ Digit ${i + 1}/6 saisi (fallback)`);
          } catch (e2) {
            log(`[2FA-3/5] ✗ Erreur digit ${i + 1}: ${e2.message}`);
          }
        }
      }
    } else {
      // Fallback for other input types
      log(`[2FA-3/5] Fallback: recherche autre type d'input...`);
      const singleInput = await page.$('input[inputmode="numeric"], input[type="text"][maxlength="6"]');
      if (singleInput) {
        await singleInput.type(code, { delay: 50 });
        log(`[2FA-3/5] ✓ Code saisi dans input unique`);
      } else {
        log(`[2FA-3/5] ✗ Aucun champ OTP trouvé`);
        return { success: false, error: 'Champs OTP non trouvés' };
      }
    }

    // Wait a bit for validation
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Submit the 2FA form
    log(`[2FA-4/5] Clic bouton submit...`);
    await page.click('button[type="submit"]');
    log(`[2FA-4/5] ✓ Submit cliqué`);

    // Wait for redirect
    log(`[2FA-5/5] Attente redirection...`);
    await new Promise(resolve => setTimeout(resolve, 5000));
    log(`[2FA-5/5] URL finale: ${page.url()}`);

    // Verify login
    log(`[2FA-VERIF] Vérification connexion via API SNCF...`);
    const customerResult = await page.evaluate(async (baseUrl) => {
      try {
        const response = await fetch(`${baseUrl}/api/public/customer/read-customer`, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-client-app': 'MAX_JEUNE',
          },
          body: JSON.stringify({
            productTypes: ['TGV_MAX_JEUNE', 'FIDEL', 'IDTGV_MAX']
          }),
        });

        if (!response.ok) return { success: false, status: response.status };
        return { success: true, data: await response.json() };
      } catch (error) {
        return { success: false, error: error.message };
      }
    }, SNCF_BASE_URL);

    if (!customerResult.success) {
      log(`[2FA-VERIF] ✗ Échec: ${customerResult.error || 'status ' + customerResult.status}`);
      return { success: false, error: 'Code invalide ou expiré' };
    }

    log(`[2FA-VERIF] ✓ API répond OK`);

    const card = customerResult.data.cards?.find(c => c.productType === 'TGV_MAX_JEUNE');
    const session = {
      isAuthenticated: true,
      cardNumber: card?.cardNumber || null,
      lastName: customerResult.data.lastName,
      firstName: customerResult.data.firstName,
      email: customerResult.data.email,
    };

    log(`[2FA-VERIF] ✓ User: ${session.firstName} ${session.lastName}`);
    log(`[2FA-VERIF] ✓ Card: ${session.cardNumber || 'non trouvée'}`);

    const bookings = await fetchBookingsInternal(page, session.cardNumber);
    log(`[2FA-VERIF] ✓ ${bookings.length} réservations trouvées`);

    userSession.session = session;
    userSession.bookings = bookings;
    userSession.pending2FA = false;
    userSession.lastActivity = Date.now();

    log(`========== 2FA SUCCESS ==========`);
    log(`✓ Connecté: ${session.firstName} ${session.lastName}`);

    return { success: true, session, bookingsCount: bookings.length };

  } catch (error) {
    log(`2FA error: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Fetch bookings for authenticated session
 */
async function fetchBookingsInternal(page, cardNumber) {
  if (!cardNumber) return [];

  try {
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 90);

    const result = await page.evaluate(async (baseUrl, cardNum, startDateStr) => {
      try {
        const response = await fetch(`${baseUrl}/api/public/reservation/travel-consultation`, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-client-app': 'MAX_JEUNE',
            'x-distribution-channel': 'OUI',
          },
          body: JSON.stringify({
            cardNumber: cardNum,
            startDate: startDateStr
          }),
        });

        if (!response.ok) return { success: false };
        return { success: true, data: await response.json() };
      } catch (error) {
        return { success: false, error: error.message };
      }
    }, SNCF_BASE_URL, cardNumber, startDate.toISOString());

    if (result.success && Array.isArray(result.data)) {
      log(`Fetched ${result.data.length} bookings`);
      return result.data;
    }
    return [];
  } catch (error) {
    log(`Error fetching bookings: ${error.message}`);
    return [];
  }
}

/**
 * Refresh bookings for a user
 */
async function refreshBookings(userId) {
  const userSession = authenticatedSessions.get(userId);
  if (!userSession || !userSession.session?.isAuthenticated) {
    return { success: false, error: 'Non authentifié', needsReauth: true };
  }

  try {
    const bookings = await fetchBookingsInternal(userSession.page, userSession.session.cardNumber);
    userSession.bookings = bookings;
    userSession.lastActivity = Date.now();

    return { success: true, bookings, session: userSession.session };
  } catch (error) {
    log(`Error refreshing bookings: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Confirm a booking
 */
async function confirmBooking(userId, booking) {
  const userSession = authenticatedSessions.get(userId);
  if (!userSession || !userSession.session?.isAuthenticated) {
    return { success: false, error: 'Non authentifié', needsReauth: true };
  }

  log(`Confirming booking: Train ${booking.trainNumber} for user ${userId}`);

  try {
    const result = await userSession.page.evaluate(async (baseUrl, bookingData) => {
      try {
        const response = await fetch(`${baseUrl}/api/public/reservation/travel-confirm`, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-client-app': 'MAX_JEUNE',
            'x-distribution-channel': 'OUI',
          },
          body: JSON.stringify({
            marketingCarrierRef: bookingData.dvNumber || bookingData.marketingCarrierRef,
            trainNumber: bookingData.trainNumber,
            departureDateTime: bookingData.departureDateTime,
          }),
        });

        if (response.status === 204) {
          return { success: true };
        }

        if (response.status === 401 || response.status === 403) {
          return { success: false, needsReauth: true };
        }

        const text = await response.text();
        return { success: false, error: text || `HTTP ${response.status}` };
      } catch (error) {
        return { success: false, error: error.message };
      }
    }, SNCF_BASE_URL, booking);

    userSession.lastActivity = Date.now();

    if (result.success) {
      log(`Booking confirmed: Train ${booking.trainNumber}`);
      // Remove from auto-confirm schedule
      autoConfirmSchedule.delete(getBookingKey(booking));
    }

    return result;

  } catch (error) {
    log(`Error confirming booking: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Cancel a booking
 */
async function cancelBooking(userId, booking, customerName) {
  const userSession = authenticatedSessions.get(userId);
  if (!userSession || !userSession.session?.isAuthenticated) {
    return { success: false, error: 'Non authentifié', needsReauth: true };
  }

  log(`Cancelling booking: Train ${booking.trainNumber} for user ${userId}`);

  try {
    const result = await userSession.page.evaluate(async (baseUrl, bookingData, custName) => {
      try {
        const response = await fetch(`${baseUrl}/api/public/reservation/cancel-reservation`, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-client-app': 'MAX_JEUNE',
            'x-distribution-channel': 'OUI',
          },
          body: JSON.stringify({
            travelsInfo: [{
              marketingCarrierRef: bookingData.dvNumber || bookingData.marketingCarrierRef,
              orderId: bookingData.orderId,
              customerName: custName,
              trainNumber: bookingData.trainNumber,
              departureDateTime: bookingData.departureDateTime,
            }]
          }),
        });

        if (!response.ok) {
          return { success: false, status: response.status };
        }

        const data = await response.json();
        if (data.info?.[0]?.cancelled === true) {
          return { success: true };
        }
        return { success: false, error: 'Annulation échouée' };
      } catch (error) {
        return { success: false, error: error.message };
      }
    }, SNCF_BASE_URL, booking, customerName);

    userSession.lastActivity = Date.now();

    if (result.success) {
      log(`Booking cancelled: Train ${booking.trainNumber}`);
    }

    return result;

  } catch (error) {
    log(`Error cancelling booking: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Schedule auto-confirmation for a booking
 */
function scheduleAutoConfirm(userId, booking) {
  const key = getBookingKey(booking);

  autoConfirmSchedule.set(key, {
    userId,
    booking,
    scheduledAt: Date.now(),
    status: 'pending',
  });

  log(`Auto-confirm scheduled: Train ${booking.trainNumber} for user ${userId}`);

  return { success: true, key };
}

/**
 * Cancel scheduled auto-confirmation
 */
function cancelAutoConfirm(bookingKey) {
  if (autoConfirmSchedule.has(bookingKey)) {
    autoConfirmSchedule.delete(bookingKey);
    return { success: true };
  }
  return { success: false, error: 'Pas de confirmation planifiée' };
}

/**
 * Get all scheduled auto-confirmations for a user
 */
function getAutoConfirmSchedule(userId) {
  const userSchedule = [];
  for (const [key, schedule] of autoConfirmSchedule.entries()) {
    if (schedule.userId === userId) {
      userSchedule.push({ key, ...schedule });
    }
  }
  return userSchedule;
}

/**
 * Check and execute pending auto-confirmations
 */
async function checkAutoConfirmations() {
  const now = new Date();
  log(`Checking auto-confirmations... (${autoConfirmSchedule.size} scheduled)`);

  for (const [key, schedule] of autoConfirmSchedule.entries()) {
    if (schedule.status !== 'pending') continue;

    const booking = schedule.booking;
    const departure = new Date(booking.departureDateTime);
    const confirmationAvailableAt = new Date(departure.getTime() - 48 * 60 * 60 * 1000);

    // Check if we can confirm now (48h window opened)
    if (now >= confirmationAvailableAt && now < departure) {
      log(`Auto-confirming: Train ${booking.trainNumber}`);

      schedule.status = 'confirming';

      const result = await confirmBooking(schedule.userId, booking);

      if (result.success) {
        schedule.status = 'confirmed';
        log(`Auto-confirm SUCCESS: Train ${booking.trainNumber}`);
      } else if (result.needsReauth) {
        schedule.status = 'needs_reauth';
        log(`Auto-confirm FAILED (needs reauth): Train ${booking.trainNumber}`);
      } else {
        schedule.status = 'failed';
        schedule.error = result.error;
        log(`Auto-confirm FAILED: Train ${booking.trainNumber} - ${result.error}`);
      }
    }
  }
}

/**
 * Logout user and close browser
 */
async function logoutUser(userId) {
  const userSession = authenticatedSessions.get(userId);
  if (userSession) {
    try {
      await userSession.browser.close();
    } catch (e) {
      // Ignore
    }
    authenticatedSessions.delete(userId);

    // Remove user's auto-confirm schedules
    for (const [key, schedule] of autoConfirmSchedule.entries()) {
      if (schedule.userId === userId) {
        autoConfirmSchedule.delete(key);
      }
    }

    log(`User ${userId} logged out`);
  }
}

/**
 * Get session status
 */
function getSessionStatus(userId) {
  const userSession = authenticatedSessions.get(userId);
  if (!userSession) {
    return { isAuthenticated: false };
  }

  return {
    isAuthenticated: userSession.session?.isAuthenticated || false,
    pending2FA: userSession.pending2FA || false,
    session: userSession.session,
    bookingsCount: userSession.bookings?.length || 0,
    lastActivity: userSession.lastActivity,
  };
}

/**
 * Cleanup stale sessions
 */
function cleanupStaleSessions() {
  const now = Date.now();
  for (const [userId, userSession] of authenticatedSessions.entries()) {
    if (now - userSession.lastActivity > AUTH_SESSION_TIMEOUT) {
      log(`Cleaning up stale session for user: ${userId}`);
      logoutUser(userId);
    }
  }
}

// Start periodic tasks
let autoConfirmInterval = null;
let cleanupInterval = null;

function startPeriodicTasks() {
  // Check auto-confirmations every 5 minutes
  autoConfirmInterval = setInterval(checkAutoConfirmations, AUTO_CONFIRM_CHECK_INTERVAL);

  // Cleanup stale sessions every 30 minutes
  cleanupInterval = setInterval(cleanupStaleSessions, 30 * 60 * 1000);

  log('Periodic tasks started');
}

function stopPeriodicTasks() {
  if (autoConfirmInterval) clearInterval(autoConfirmInterval);
  if (cleanupInterval) clearInterval(cleanupInterval);
}

// Export everything
module.exports = {
  loginUser,
  submit2FACode,
  refreshBookings,
  confirmBooking,
  cancelBooking,
  scheduleAutoConfirm,
  cancelAutoConfirm,
  getAutoConfirmSchedule,
  checkAutoConfirmations,
  logoutUser,
  getSessionStatus,
  startPeriodicTasks,
  stopPeriodicTasks,
  // For debugging
  getActiveSessions: () => Array.from(authenticatedSessions.keys()),
  getAutoConfirmCount: () => autoConfirmSchedule.size,
};
