/**
 * ECHO: Talk to Strangers - Real-time Backend (hardened)
 *
 * Security model
 *  - Every user/guest gets a signed session token (HMAC). userId is ALWAYS taken from
 *    the token, never from the request body or socket payload.
 *  - Admin endpoints need ADMIN_PASSWORD (env). If it is not set, admin is disabled.
 *  - Coin purchases are verified with the Google Play Developer API (service account).
 *  - Rewarded-ad coins are credited only by AdMob server-side verification (ads_ssv.js).
 *  - All socket handlers validate input and can't crash the process; per-socket flood limits.
 *
 * Environment variables (see SERVER_ENV.md):
 *  SERVER_SECRET, ADMIN_PASSWORD, GOOGLE_SERVICE_ACCOUNT_JSON | GOOGLE_SERVICE_ACCOUNT_FILE,
 *  ANDROID_PACKAGE_NAME, ADMOB_REWARDED_AD_UNIT, TURN_URLS, TURN_SECRET (or TURN_USERNAME/TURN_CREDENTIAL),
 *  ALLOWED_ORIGINS, TRUST_PROXY, PORT
 */

require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const { verifySsvQuery } = require('./ads_ssv');
const { verifyGoogleIdToken } = require('./google_auth');
const db = require('./db'); // Supabase persistence (memory-only if not configured)
const otpModule = require('./otp');

// ======================== CONFIG ========================
const PORT = process.env.PORT || 3000;
const GUEST_DURATION_MS = Number(process.env.GUEST_DURATION_MS) || 60 * 60 * 1000; // 60 minutes
const GUEST_SWEEP_MS = Number(process.env.GUEST_SWEEP_MS) || 15 * 1000;
const REMATCH_COOLDOWN_MS = Number(process.env.REMATCH_COOLDOWN_MS) || 5 * 60 * 1000;
const PARTNER_HISTORY_MS = 24 * 3600 * 1000;
const TOKEN_TTL_MS = 90 * 24 * 3600 * 1000;
const ANDROID_PACKAGE_NAME = process.env.ANDROID_PACKAGE_NAME || 'com.koshal.echotalk';
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);

const IS_PROD = process.env.NODE_ENV === 'production';
let SERVER_SECRET = process.env.SERVER_SECRET;
if (!SERVER_SECRET && IS_PROD) {
  console.error('FATAL: SERVER_SECRET must be set when NODE_ENV=production (otherwise every restart logs everyone out).');
  process.exit(1);
}
if (!SERVER_SECRET) {
  SERVER_SECRET = crypto.randomBytes(32).toString('hex');
  console.warn('[WARN] SERVER_SECRET not set: using a random one. All login tokens become invalid on every restart.');
}
if (!process.env.ADMIN_PASSWORD) console.warn('[WARN] ADMIN_PASSWORD not set: admin endpoints are disabled.');

const RESERVED_USERNAMES = new Set([
  'admin', 'echo', 'support', 'moderator', 'system', 'root', 'official', 'echoadmin', 'staff',
]);
const PACK_MAP = { coins_starter_49: 50, coins_popular_149: 200, coins_value_299: 500 };
const CALL_MODES = new Set(['audio', 'video', 'text']);
const CHAT_MAX_LEN = 500;
const REPORT_CATEGORIES = new Set([
  'Harassment or Bullying', 'Inappropriate / Explicit Audio', 'Hate Speech or Threats',
  'Scam or Fraud', 'Spam or Advertising', 'Underage User', 'other',
]);

const app = express();
const server = http.createServer(app);
app.disable('x-powered-by');
// Behind Render / Railway / Fly the real client IP is in X-Forwarded-For. Without this every user
// shares the proxy's IP and the rate limiters would block everybody at once.
if (process.env.TRUST_PROXY) app.set('trust proxy', Number(process.env.TRUST_PROXY) || process.env.TRUST_PROXY);
else if (IS_PROD || process.env.RENDER || process.env.RAILWAY_ENVIRONMENT || process.env.FLY_APP_NAME) app.set('trust proxy', 1);

const corsOrigin = ALLOWED_ORIGINS.length ? ALLOWED_ORIGINS : false; // mobile apps don't need CORS
const io = new Server(server, {
  cors: { origin: corsOrigin, methods: ['GET', 'POST'] },
  maxHttpBufferSize: 100 * 1024,
});

app.use(cors({ origin: corsOrigin }));
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  if (req.secure || req.headers['x-forwarded-proto'] === 'https') {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }
  next();
});
app.use(express.json({ limit: '20kb' }));
app.use(express.static(path.join(__dirname, 'public')));

// ======================== IN-MEMORY DATA STORES ========================
// Fast in-memory copies for real-time matching. Every change is ALSO saved to Supabase
// (see db.js) and everything is reloaded from Supabase on startup (loadFromDb below).
const users = new Map();               // userId -> user
const normalizedUsernames = new Map(); // normalized username -> userId
const googleSubs = new Map();          // Google account id (sub) -> userId
const emailToUser = new Map();         // VERIFIED email -> userId
const phoneToUser = new Map();         // verified phone (E.164) -> userId
const guestSessions = new Map();       // sessionId -> guest session
const guestByDevice = new Map();       // deviceId -> sessionId (one 60-min allowance per device)
const blockedPairs = new Set();        // "a:::b"
const blocksByUser = new Map();        // userId -> count
const reportQueue = [];
const walletLedgers = [];
const partnerHistory = new Map();      // userId -> Map(partnerId -> timestamp)
let matchQueue = [];                   // waiting sockets
const activeCalls = new Map();         // roomId -> call

const getBlockKey = (a, b) => [a, b].sort().join(':::');
const isBlocked = (a, b) => blockedPairs.has(getBlockKey(a, b));

// In-memory copy of the latest ledger rows (for the admin panel); Supabase keeps the full history.
const pushLedger = (entry) => { walletLedgers.push(entry); if (walletLedgers.length > 200) walletLedgers.shift(); };
const dbBusy = (res) => res.status(503).json({ error: 'Service temporarily unavailable. Please try again.' });

// ======================== HELPERS ========================
const b64url = (buf) => Buffer.from(buf).toString('base64url');
const hmac = (data) => crypto.createHmac('sha256', SERVER_SECRET).update(data).digest('base64url');

function signToken(payload) {
  const body = b64url(JSON.stringify(payload));
  return body + '.' + hmac(body);
}

function verifyToken(token) {
  if (typeof token !== 'string' || token.length > 1000) return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const expected = Buffer.from(hmac(parts[0]));
  const given = Buffer.from(parts[1]);
  if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    if (!payload || typeof payload.uid !== 'string' || typeof payload.exp !== 'number') return null;
    if (Date.now() > payload.exp) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

/** Resolves a token to a live account record, or null. */
function accountFromToken(token) {
  const p = verifyToken(token);
  if (!p) return null;
  if (p.g) {
    const s = guestSessions.get(p.uid);
    return s ? { userId: s.sessionId, isGuest: true, record: s } : null;
  }
  const u = users.get(p.uid);
  return u ? { userId: u.userId, isGuest: false, record: u } : null;
}

const cleanText = (v, max) =>
  typeof v === 'string' ? v.replace(/[\u0000-\u001F\u007F<>]/g, '').trim().slice(0, max) : '';
const isId = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{3,64}$/.test(v);

function rateLimit({ windowMs, max, name }) {
  const hits = new Map();
  setInterval(() => {
    const now = Date.now();
    for (const [k, v] of hits) if (now - v.start > windowMs) hits.delete(k);
  }, windowMs).unref();
  return (req, res, next) => {
    const key = (req.auth && req.auth.userId) || req.ip;
    const now = Date.now();
    let h = hits.get(key);
    if (!h || now - h.start > windowMs) { h = { start: now, count: 0 }; hits.set(key, h); }
    if (++h.count > max) {
      res.setHeader('Retry-After', Math.ceil((h.start + windowMs - now) / 1000));
      return res.status(429).json({ error: 'Too many requests. Please slow down.' });
    }
    next();
  };
}

function requireAuth({ allowGuest = false } = {}) {
  return (req, res, next) => {
    const h = req.headers.authorization || '';
    const acct = h.startsWith('Bearer ') ? accountFromToken(h.slice(7)) : null;
    if (!acct) return res.status(401).json({ error: 'Please sign in again.' });
    if (acct.isGuest && !allowGuest) return res.status(403).json({ error: 'Sign up with a username to use this feature.' });
    if (acct.isGuest && acct.record.expiresAt <= Date.now()) {
      return res.status(403).json({ error: 'Guest time is over. Please sign up.', expired: true });
    }
    if (!acct.isGuest && acct.record.status === 'suspended') return res.status(403).json({ error: 'Account suspended.' });
    req.auth = acct;
    next();
  };
}

function requireAdmin(req, res, next) {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) return res.status(503).json({ error: 'Admin is disabled on this server.' });
  const given = req.headers['x-admin-password'];
  if (typeof given !== 'string') return res.status(401).json({ error: 'Unauthorized' });
  const a = crypto.createHash('sha256').update(given).digest();
  const b = crypto.createHash('sha256').update(expected).digest();
  if (!crypto.timingSafeEqual(a, b)) return res.status(401).json({ error: 'Unauthorized' });
  next();
}

const guestLimiter = rateLimit({ windowMs: 3600 * 1000, max: 30, name: 'guest' });
const registerLimiter = rateLimit({ windowMs: 3600 * 1000, max: 20, name: 'register' });
const googleLimiter = rateLimit({ windowMs: 3600 * 1000, max: 60, name: 'google' });
const otpRequestLimiter = rateLimit({ windowMs: 3600 * 1000, max: 30, name: 'otp-request' });
const otpVerifyLimiter = rateLimit({ windowMs: 3600 * 1000, max: 60, name: 'otp-verify' });
const otp = otpModule.create({ secret: SERVER_SECRET });
const usernameLimiter = rateLimit({ windowMs: 60 * 1000, max: 60, name: 'username' });
const adminLimiter = rateLimit({ windowMs: 60 * 1000, max: Number(process.env.ADMIN_RATE_PER_MIN) || 60, name: 'admin' });
const walletLimiter = rateLimit({ windowMs: 60 * 1000, max: 20, name: 'wallet' });
const safetyLimiter = rateLimit({ windowMs: 3600 * 1000, max: 30, name: 'safety' });

// ======================== REST API ========================
app.get('/api/health', (req, res) => res.json({ status: 'online', serverTime: new Date().toISOString() }));

app.get('/api/config', (req, res) => {
  res.json({
    termsVersion: TERMS_VERSION,
    settings: {
      ads_banner_enabled: true,
      ads_interstitial_enabled: true,
      ads_rewarded_enabled: true,
      interstitial_cooldown_seconds: 120,
    },
  });
});

// Guest session: one 60-minute allowance per device id (server-enforced).
app.post('/api/guest/start', guestLimiter, async (req, res) => {
  const deviceId = (req.body || {}).deviceFingerprint;
  if (!isId(deviceId) || deviceId.length < 8) return res.status(400).json({ error: 'Invalid device id.' });

  let session = guestSessions.get(guestByDevice.get(deviceId));
  const now = Date.now();
  if (!session) {
    const sessionId = 'guest_' + uuidv4().replace(/-/g, '').slice(0, 16);
    session = {
      sessionId, deviceId, createdAt: now, expiresAt: now + GUEST_DURATION_MS,
      isGuest: true, displayName: 'Guest_' + crypto.randomInt(1000, 10000),
    };
    try {
      await db.insertGuest(session);
    } catch (e) {
      console.error('[DB] insertGuest failed:', e.message);
      return res.status(503).json({ error: 'Service temporarily unavailable. Please try again.' });
    }
    guestSessions.set(sessionId, session);
    guestByDevice.set(deviceId, sessionId);
  }
  if (session.expiresAt <= now) {
    return res.status(403).json({ error: 'Your free guest time is used up. Please sign up.', expired: true });
  }
  const token = signToken({ uid: session.sessionId, g: true, exp: session.expiresAt });
  res.json({
    success: true,
    session: { sessionId: session.sessionId, displayName: session.displayName, expiresAt: session.expiresAt, termsAccepted: termsOk(session) },
    remainingSeconds: Math.floor((session.expiresAt - now) / 1000),
    token,
  });
});

app.post('/api/username/check', usernameLimiter, (req, res) => {
  const { username } = req.body || {};
  if (typeof username !== 'string' || !username) {
    return res.status(400).json({ valid: false, message: 'Username is required' });
  }
  if (!/^[a-zA-Z][a-zA-Z0-9_]{3,19}$/.test(username)) {
    return res.json({ valid: false, message: 'Must be 4-20 characters, start with a letter, letters, numbers & underscore only.' });
  }
  const normalized = username.toLowerCase();
  if (RESERVED_USERNAMES.has(normalized)) return res.json({ valid: false, message: 'This username is reserved by Echo system.' });
  if (normalizedUsernames.has(normalized)) {
    const suffix = crypto.randomInt(1000, 10000);
    return res.json({
      valid: false, taken: true, message: 'Username is already taken.',
      suggestions: [`Echo_${username}`, `${username}_${suffix}`, `Real_${username}`].map((s) => s.slice(0, 20)),
    });
  }
  res.json({ valid: true, message: 'Username is available!' });
});

/** Returns an error message, or null if the username is acceptable. */
function validateUsername(username) {
  if (typeof username !== 'string' || !/^[a-zA-Z][a-zA-Z0-9_]{3,19}$/.test(username)) {
    return 'Username must be 4-20 characters, start with a letter, and use only letters, numbers and underscore.';
  }
  const normalized = username.toLowerCase();
  if (RESERVED_USERNAMES.has(normalized)) return 'This username is reserved.';
  if (normalizedUsernames.has(normalized)) return 'Username already taken';
  return null;
}

async function createUser({ username, displayName, email, googleSub, phone, emailVerified }) {
  const userId = 'usr_' + uuidv4().replace(/-/g, '').slice(0, 16);
  const user = {
    userId, username, normalizedUsername: username.toLowerCase(),
    displayName: cleanText(displayName, 30) || username,
    email: email || '',
    googleSub: googleSub || null,
    phone: phone || null,
    emailVerified: !!emailVerified,
    avatarUrl: `https://api.dicebear.com/7.x/bottts/png?seed=${encodeURIComponent(username)}`,
    coins: 50, createdAt: Date.now(), isGuest: false, status: 'active',
  };
  const welcomeTx = 'tx_' + uuidv4();
  await db.insertUser(user, welcomeTx); // throws if the DB rejects it (e.g. duplicate username)
  users.set(userId, user);
  normalizedUsernames.set(user.normalizedUsername, userId);
  if (googleSub) googleSubs.set(googleSub, userId);
  if (user.emailVerified && user.email && !emailToUser.has(user.email)) emailToUser.set(user.email, userId);
  if (user.phone) phoneToUser.set(user.phone, userId);
  pushLedger({
    transactionId: welcomeTx, userId, entryType: 'credit', coinDelta: 50,
    source: 'welcome_bonus', timestamp: Date.now(),
  });
  return user;
}

// ---- Terms and Conditions: nobody may use Echo (calls, chat, coins) until they accepted the CURRENT version.
const TERMS_VERSION = process.env.TERMS_VERSION || '2026-10-22'; // must match client/lib/constants/terms_text.dart
const TERMS_ENFORCE = process.env.TERMS_ENFORCE !== '0';          // '0' only for automated tests
const recordOf = (id) => users.get(id) || guestSessions.get(id) || null;
const termsOk = (rec) => !!rec && rec.termsVersion === TERMS_VERSION;
const mustAcceptTerms = (id) => TERMS_ENFORCE && !termsOk(recordOf(id));
const requireTerms = (req, res, next) => (mustAcceptTerms(req.auth.userId)
  ? res.status(403).json({ error: 'Please accept the Terms and Conditions first.', code: 'terms_required' })
  : next());

const publicUserOf = (u) => {
  const { email, googleSub, phone, emailVerified, termsVersion, ...pub } = u;
  return { ...pub, termsAccepted: termsVersion === TERMS_VERSION };
};
const tokenFor = (u) => signToken({ uid: u.userId, g: false, exp: Date.now() + TOKEN_TTL_MS });

app.post('/api/auth/register', registerLimiter, async (req, res) => {
  const { username, email, displayName } = req.body || {};
  const problem = validateUsername(username);
  if (problem) return res.status(400).json({ error: problem });

  let cleanEmail = '';
  if (email !== undefined && email !== null && email !== '') {
    if (typeof email !== 'string' || email.length > 100 || !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email)) {
      return res.status(400).json({ error: 'Invalid email address.' });
    }
    cleanEmail = email;
  }
  let user;
  try {
    user = await createUser({ username, displayName, email: cleanEmail });
  } catch (e) {
    console.error('[DB] createUser failed:', e.message);
    if (/duplicate|unique/i.test(e.message)) return res.status(400).json({ error: 'Username already taken' });
    return dbBusy(res);
  }
  res.json({ success: true, user: publicUserOf(user), token: tokenFor(user) });
});

// ---------------- OTP sign-in (email via SMTP, phone via SMS) ----------------
// 1) /otp/request  -> sends a code to the email / phone number.
// 2) /otp/verify   -> existing account: logs in. New account: { needsUsername, ticket }.
// 3) /otp/complete -> ticket + username creates the account.
const OTP_TICKET_TTL_MS = 10 * 60 * 1000;
const otpOwnerOf = (channel, target) => {
  const id = channel === 'email' ? emailToUser.get(target) : phoneToUser.get(target);
  return id ? users.get(id) : null;
};

app.post('/api/auth/otp/request', otpRequestLimiter, async (req, res) => {
  const { channel, target } = req.body || {};
  const r = await otp.request(channel, target);
  if (r.error) {
    if (r.retryAfter) res.setHeader('Retry-After', r.retryAfter);
    return res.status(r.status).json({ error: r.error, retryAfter: r.retryAfter });
  }
  res.json({ success: true, cooldownSeconds: r.cooldownSeconds });
});

app.post('/api/auth/otp/verify', otpVerifyLimiter, async (req, res) => {
  const { channel, target, code } = req.body || {};
  const v = await otp.verify(channel, target, code);
  if (v.error) return res.status(v.status).json({ error: v.error });
  const existing = otpOwnerOf(channel, v.value);
  if (existing) {
    if (existing.status === 'suspended') return res.status(403).json({ error: 'Account suspended.' });
    return res.json({ success: true, isNewUser: false, user: publicUserOf(existing), token: tokenFor(existing) });
  }
  const ticket = signToken({ uid: 'otp', ot: channel, tg: v.value, exp: Date.now() + OTP_TICKET_TTL_MS });
  res.json({ success: true, needsUsername: true, ticket });
});

app.post('/api/auth/otp/complete', registerLimiter, async (req, res) => {
  const { ticket, username, displayName } = req.body || {};
  const t = verifyToken(typeof ticket === 'string' ? ticket : '');
  if (!t || t.uid !== 'otp' || (t.ot !== 'email' && t.ot !== 'phone') || typeof t.tg !== 'string') {
    return res.status(400).json({ error: 'Verification expired. Please start again.' });
  }
  const existing = otpOwnerOf(t.ot, t.tg);
  if (existing) return res.json({ success: true, isNewUser: false, user: publicUserOf(existing), token: tokenFor(existing) });
  const problem = validateUsername(username);
  if (problem) return res.status(400).json({ error: problem });
  let user;
  try {
    user = await createUser({
      username, displayName: cleanText(displayName, 30) || username,
      email: t.ot === 'email' ? t.tg : '', emailVerified: t.ot === 'email',
      phone: t.ot === 'phone' ? t.tg : null,
    });
  } catch (e) {
    console.error('[DB] createUser (otp) failed:', e.message);
    if (/duplicate|unique/i.test(e.message)) return res.status(400).json({ error: 'Username already taken' });
    return dbBusy(res);
  }
  res.json({ success: true, isNewUser: true, user: publicUserOf(user), token: tokenFor(user) });
});

// ---------------- Google Sign-In ----------------
// Step 1: app sends the Google ID token.
//   - Known Google account -> logs in (works on any device = account recovery).
//   - New Google account   -> { needsUsername: true }; app asks for a username and
//     calls this endpoint again with the same idToken + username.
app.post('/api/auth/google', googleLimiter, async (req, res) => {
  const audiences = (process.env.GOOGLE_CLIENT_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!audiences.length) return res.status(503).json({ error: 'Google Sign-In is not available right now.' });

  const { idToken, username } = req.body || {};
  let g;
  try {
    g = await verifyGoogleIdToken(idToken, audiences);
  } catch (e) {
    console.warn('[GOOGLE] token rejected:', e.message);
    return res.status(401).json({ error: 'Google sign-in could not be verified. Please try again.' });
  }

  const existingId = googleSubs.get(g.sub);
  if (existingId) {
    const user = users.get(existingId);
    if (!user) return res.status(401).json({ error: 'Account not found.' });
    if (user.status === 'suspended') return res.status(403).json({ error: 'Account suspended.' });
    return res.json({ success: true, isNewUser: false, user: publicUserOf(user), token: tokenFor(user) });
  }

  if (username === undefined || username === null || username === '') {
    return res.json({ success: true, needsUsername: true, suggestedName: cleanText(g.name, 30) });
  }
  const problem = validateUsername(username);
  if (problem) return res.status(400).json({ error: problem });

  let user;
  try {
    user = await createUser({ username, displayName: cleanText((req.body || {}).displayName, 30) || g.name, email: g.email, googleSub: g.sub, emailVerified: true });
  } catch (e) {
    console.error('[DB] createUser (google) failed:', e.message);
    if (/duplicate|unique/i.test(e.message)) return res.status(400).json({ error: 'Username already taken' });
    return dbBusy(res);
  }
  res.json({ success: true, isNewUser: true, user: publicUserOf(user), token: tokenFor(user) });
});

// ---------------- Google Play purchase verification ----------------
let _gToken = { value: null, exp: 0 };
function loadServiceAccount() {
  try {
    if (process.env.GOOGLE_SERVICE_ACCOUNT_JSON) return JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
    if (process.env.GOOGLE_SERVICE_ACCOUNT_FILE) return JSON.parse(fs.readFileSync(process.env.GOOGLE_SERVICE_ACCOUNT_FILE, 'utf8'));
  } catch (e) {
    console.error('[PLAY] could not read service account:', e.message);
  }
  return null;
}

async function getGoogleAccessToken(sa) {
  if (_gToken.value && Date.now() < _gToken.exp - 60000) return _gToken.value;
  const now = Math.floor(Date.now() / 1000);
  const tokenUri = sa.token_uri || 'https://oauth2.googleapis.com/token';
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: tokenUri, iat: now, exp: now + 3600,
  }));
  const sig = crypto.createSign('RSA-SHA256').update(`${header}.${claims}`).sign(sa.private_key).toString('base64url');
  const r = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${claims}.${sig}` }),
  });
  if (!r.ok) throw new Error('Google auth failed: HTTP ' + r.status);
  const j = await r.json();
  _gToken = { value: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000 };
  return _gToken.value;
}

/** Returns { ok: boolean, reason?: string } using the Play Developer API. */
async function verifyPlayPurchase(productId, purchaseToken) {
  const sa = loadServiceAccount();
  if (!sa) return { ok: false, notConfigured: true };
  const at = await getGoogleAccessToken(sa);
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(ANDROID_PACKAGE_NAME)}` +
    `/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`;
  const r = await fetch(url, { headers: { Authorization: 'Bearer ' + at } });
  if (r.status === 404 || r.status === 400) return { ok: false, reason: 'Purchase not found.' };
  if (!r.ok) throw new Error('Play API HTTP ' + r.status);
  const p = await r.json();
  if (p.purchaseState !== 0) return { ok: false, reason: 'Purchase is not completed (cancelled or pending).' };
  return { ok: true, orderId: p.orderId };
}

app.post('/api/wallet/purchase', requireAuth(), requireTerms, walletLimiter, async (req, res) => {
  const { productId, purchaseToken } = req.body || {};
  if (typeof productId !== 'string' || !Object.prototype.hasOwnProperty.call(PACK_MAP, productId)) {
    return res.status(400).json({ error: 'Unknown product.' });
  }
  if (typeof purchaseToken !== 'string' || purchaseToken.length < 10 || purchaseToken.length > 2000) {
    return res.status(400).json({ error: 'Invalid purchase token.' });
  }
  const user = req.auth.record;
  try {
    // The database is the single source of truth for "was this token already used".
    const mine = await db.claimPurchase(purchaseToken, user.userId, productId);
    if (!mine) {
      const existing = await db.getPurchase(purchaseToken);
      if (existing && existing.user_id !== user.userId) return res.status(409).json({ error: 'This purchase belongs to another account.' });
      if (existing && existing.state === 'pending') return res.status(409).json({ error: 'Purchase is being verified. Try again shortly.' });
      return res.json({ success: true, duplicate: true, newBalance: user.coins, coinsAdded: 0 });
    }
  } catch (e) {
    console.error('[DB] claimPurchase failed:', e.message);
    return dbBusy(res);
  }
  try {
    const v = await verifyPlayPurchase(productId, purchaseToken);
    if (v.notConfigured) {
      await db.deletePurchase(purchaseToken);
      return res.status(503).json({ error: 'Purchases are not available right now.' });
    }
    if (!v.ok) {
      await db.deletePurchase(purchaseToken);
      return res.status(402).json({ error: v.reason || 'Purchase could not be verified.' });
    }
    const coins = PACK_MAP[productId];
    const dbBalance = await db.addCoins(user.userId, coins, 'google_play', productId, v.orderId || null);
    user.coins = dbBalance !== null ? dbBalance : user.coins + coins;
    await db.markPurchaseCredited(purchaseToken);
    pushLedger({
      transactionId: 'tx_' + uuidv4(), userId: user.userId, entryType: 'credit', coinDelta: coins,
      source: 'google_play', productId, reference: v.orderId || null, timestamp: Date.now(),
    });
    res.json({ success: true, newBalance: user.coins, coinsAdded: coins });
  } catch (e) {
    console.error('[PLAY] verification error:', e.message);
    try { await db.deletePurchase(purchaseToken); } catch (_) { /* allow retry later */ }
    res.status(502).json({ error: 'Could not verify the purchase. Please try again.' });
  }
});

// ---------------- Virtual gifts + wallet history ----------------
// The SERVER owns gift prices. The app only sends a gift id; a client-edited price is never used.
const DEFAULT_GIFTS = [
  { id: 'heart',       name: 'Heart',       price: 10,  animation: 'pop',     popular: false },
  { id: 'rose',        name: 'Rose',        price: 20,  animation: 'petals',  popular: false },
  { id: 'golden_star', name: 'Golden Star', price: 50,  animation: 'burst',   popular: true  },
  { id: 'diamond',     name: 'Diamond',     price: 100, animation: 'sparkle', popular: false },
];
let giftCatalog = DEFAULT_GIFTS; // replaced by the gift_catalog table at startup when Supabase is on
const GIFT_MIN_INTERVAL_MS = 1500;
const GIFT_REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;
const giftLimiter = rateLimit({ windowMs: 60 * 1000, max: 30, name: 'gifts' });
const giftInFlight = new Set();        // userId: one gift request at a time per person
const lastGiftAt = new Map();          // userId -> ms of last accepted gift
const memGiftRequests = new Map();     // memory-only mode: "user:requestId" -> first result (idempotency)

const SOURCE_TITLES = {
  welcome_bonus: 'Welcome bonus', google_play: 'Coin pack purchase', rewarded_ad: 'Rewarded ad',
  admin_gift: 'Gift from Echo', admin_adjust: 'Balance adjustment', gift_refund: 'Gift refund',
  filter_unlock: 'Unlocked advanced filters',
};
const ledgerTitle = (r) => {
  if (r.source === 'gift_sent') {
    const g = giftCatalog.find((x) => x.id === r.productId);
    return 'Sent ' + (g ? g.name : 'a gift');
  }
  return SOURCE_TITLES[r.source] || 'Coins';
};

app.get('/api/gifts', requireAuth({ allowGuest: true }), (req, res) => {
  res.json({ gifts: giftCatalog });
});

app.get('/api/wallet/transactions', requireAuth(), walletLimiter, async (req, res) => {
  const user = req.auth.record;
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 30, 1), 100);
  let rows;
  try {
    rows = await db.getLedger(user.userId, limit);
  } catch (e) {
    console.error('[DB] getLedger failed:', e.message);
    return dbBusy(res);
  }
  if (!rows) { // memory-only mode
    rows = walletLedgers.filter((e) => e.userId === user.userId).slice(-limit).reverse().map((e) => ({
      id: e.transactionId, delta: e.coinDelta, source: e.source, productId: e.productId || null, createdAt: e.timestamp,
    }));
  }
  res.json({
    balance: user.coins,
    transactions: rows.map((r) => ({ id: r.id, delta: r.delta, title: ledgerTitle(r), source: r.source, createdAt: r.createdAt })),
  });
});

app.post('/api/gifts/send', requireAuth(), requireTerms, giftLimiter, async (req, res) => {
  const { roomId, giftId, requestId } = req.body || {};
  if (typeof roomId !== 'string' || typeof giftId !== 'string' || typeof requestId !== 'string' || !GIFT_REQUEST_ID.test(requestId)) {
    return res.status(400).json({ error: 'Invalid gift request.' });
  }
  const gift = giftCatalog.find((g) => g.id === giftId);
  if (!gift) return res.status(400).json({ error: 'That gift is not available.' });

  const user = req.auth.record;
  const call = activeCalls.get(roomId);
  const players = call ? [call.user1, call.user2] : [];
  const me = players.find((p) => p.id === user.userId);
  const other = players.find((p) => p.id !== user.userId);
  if (!call || !me || !other) return res.status(409).json({ error: 'This call has ended. No coins were charged.' });
  if (!io.sockets.sockets.get(other.socketId)) {
    return res.status(409).json({ error: 'The other person just left. No coins were charged.' });
  }
  if (giftInFlight.has(user.userId) || Date.now() - (lastGiftAt.get(user.userId) || 0) < GIFT_MIN_INTERVAL_MS) {
    return res.status(429).json({ error: 'Slow down a little. Try again in a moment.' });
  }

  giftInFlight.add(user.userId);
  try {
    let result;
    try {
      if (db.enabled) {
        result = await db.sendGift({ senderId: user.userId, recipientId: other.id, callId: roomId, giftId, price: gift.price, requestId });
        user.coins = result.newBalance;
      } else {
        const key = user.userId + ':' + requestId;
        if (memGiftRequests.has(key)) {
          result = { ...memGiftRequests.get(key), duplicate: true, newBalance: user.coins };
        } else {
          if (user.coins < gift.price) throw new Error('insufficient_coins');
          user.coins -= gift.price;
          result = { duplicate: false, giftEventId: 'gft_' + uuidv4(), newBalance: user.coins, price: gift.price };
          memGiftRequests.set(key, { giftEventId: result.giftEventId, price: gift.price });
          if (memGiftRequests.size > 5000) memGiftRequests.delete(memGiftRequests.keys().next().value);
        }
      }
    } catch (e) {
      if (String(e.message).includes('insufficient_coins')) {
        return res.status(402).json({ error: 'Not enough coins.', balance: user.coins, needed: gift.price });
      }
      console.error('[GIFT] send failed:', e.message);
      return dbBusy(res);
    }

    if (result.duplicate) { // a retry of a gift that already went through: never charge or send twice
      return res.json({ success: true, duplicate: true, newBalance: result.newBalance, giftEventId: result.giftEventId });
    }

    // The call may have ended while the coins were being deducted: give them back.
    const recipientSocket = activeCalls.has(roomId) ? io.sockets.sockets.get(other.socketId) : null;
    if (!recipientSocket) {
      try {
        const bal = await db.addCoins(user.userId, gift.price, 'gift_refund', giftId, result.giftEventId);
        user.coins = bal !== null ? bal : user.coins + gift.price;
      } catch (e) {
        console.error('[GIFT] REFUND FAILED for', user.userId, result.giftEventId, e.message);
      }
      pushLedger({ transactionId: 'tx_' + uuidv4(), userId: user.userId, entryType: 'credit', coinDelta: gift.price,
        source: 'gift_refund', productId: giftId, reference: result.giftEventId, timestamp: Date.now() });
      return res.status(409).json({ error: 'The call ended before the gift arrived. Your coins were returned.', newBalance: user.coins });
    }

    lastGiftAt.set(user.userId, Date.now());
    pushLedger({ transactionId: 'tx_' + uuidv4(), userId: user.userId, entryType: 'debit', coinDelta: -gift.price,
      source: 'gift_sent', productId: giftId, reference: result.giftEventId, timestamp: Date.now() });
    recipientSocket.emit('gift-received', {
      giftEventId: result.giftEventId, giftId: gift.id, name: gift.name, animation: gift.animation,
      fromName: cleanText(user.displayName, 30) || 'Stranger', ts: Date.now(),
    });
    res.json({ success: true, newBalance: user.coins, giftEventId: result.giftEventId, gift: { id: gift.id, name: gift.name } });
  } finally {
    giftInFlight.delete(user.userId);
  }
});

// ---------------- Matching preferences + Premium Filters ----------------
// Profile fields (languages / interests / region) are free: they describe the person.
// USING them as a filter is the premium part: one-time unlock, permanent, server-enforced.
// Language + region are hard filters. Interests only rank candidates (a match is never guaranteed).
const FILTER_UNLOCK_PRICE = 20;
const LANGUAGE_OPTIONS = [
  { id: 'en', name: 'English' }, { id: 'hi', name: 'Hindi' }, { id: 'es', name: 'Spanish' }, { id: 'fr', name: 'French' },
  { id: 'ar', name: 'Arabic' }, { id: 'pt', name: 'Portuguese' }, { id: 'bn', name: 'Bengali' }, { id: 'ta', name: 'Tamil' },
  { id: 'te', name: 'Telugu' }, { id: 'mr', name: 'Marathi' }, { id: 'ur', name: 'Urdu' }, { id: 'pa', name: 'Punjabi' },
  { id: 'gu', name: 'Gujarati' }, { id: 'kn', name: 'Kannada' }, { id: 'ml', name: 'Malayalam' },
];
const INTEREST_OPTIONS = [
  { id: 'music', name: 'Music' }, { id: 'sports', name: 'Sports' }, { id: 'travel', name: 'Travel' }, { id: 'gaming', name: 'Gaming' },
  { id: 'movies', name: 'Movies' }, { id: 'technology', name: 'Technology' }, { id: 'books', name: 'Books' }, { id: 'food', name: 'Food' },
  { id: 'fitness', name: 'Fitness' }, { id: 'art', name: 'Art' },
];
const REGION_OPTIONS = [
  { id: 'any', name: 'Any region' }, { id: 'IN', name: 'India' }, { id: 'US', name: 'United States' }, { id: 'GB', name: 'United Kingdom' },
  { id: 'CA', name: 'Canada' }, { id: 'AU', name: 'Australia' }, { id: 'AE', name: 'UAE' }, { id: 'PK', name: 'Pakistan' },
  { id: 'BD', name: 'Bangladesh' }, { id: 'NP', name: 'Nepal' }, { id: 'LK', name: 'Sri Lanka' }, { id: 'ID', name: 'Indonesia' },
  { id: 'PH', name: 'Philippines' }, { id: 'DE', name: 'Germany' }, { id: 'FR', name: 'France' }, { id: 'ES', name: 'Spain' },
  { id: 'BR', name: 'Brazil' }, { id: 'MX', name: 'Mexico' },
];
const LANG_IDS = new Set(LANGUAGE_OPTIONS.map((o) => o.id));
const INTEREST_IDS = new Set(INTEREST_OPTIONS.map((o) => o.id));
const REGION_IDS = new Set(REGION_OPTIONS.map((o) => o.id));
const MAX_LANGUAGES = 5;
const MAX_INTERESTS = 8;

const prefs = new Map();              // userId -> { languages, interests, region, filtersOn, unlocked }
const unlockInFlight = new Set();     // userId: one unlock request at a time per person
const prefsLimiter = rateLimit({ windowMs: 60 * 1000, max: 40, name: 'prefs' });
const emptyPrefs = () => ({ languages: [], interests: [], region: 'any', filtersOn: true, unlocked: false });
const prefsOf = (userId) => prefs.get(userId) || emptyPrefs();

// Strict validation: only allowed ids, no duplicates, size limits. Returns { value } or { error }.
function validatePrefs(body) {
  const b = body && typeof body === 'object' ? body : {};
  const list = (v, allowed, max, label) => {
    if (v === undefined) return { value: [] };
    if (!Array.isArray(v) || v.length > max) return { error: `Choose up to ${max} ${label}.` };
    const out = [];
    for (const x of v) {
      if (typeof x !== 'string' || !allowed.has(x)) return { error: `Unknown ${label.replace(/s$/, '')}.` };
      if (!out.includes(x)) out.push(x);
    }
    return { value: out };
  };
  const languages = list(b.languages, LANG_IDS, MAX_LANGUAGES, 'languages');
  if (languages.error) return { error: languages.error };
  const interests = list(b.interests, INTEREST_IDS, MAX_INTERESTS, 'interests');
  if (interests.error) return { error: interests.error };
  const region = b.region === undefined ? 'any' : b.region;
  if (typeof region !== 'string' || !REGION_IDS.has(region)) return { error: 'Unknown region.' };
  if (b.filtersOn !== undefined && typeof b.filtersOn !== 'boolean') return { error: 'Invalid filter switch.' };
  return { value: { languages: languages.value, interests: interests.value, region, filtersOn: b.filtersOn !== false } };
}

const prefsPayload = (userId, isGuest) => {
  const p = prefsOf(userId);
  return {
    preferences: { languages: p.languages, interests: p.interests, region: p.region, filtersOn: p.filtersOn },
    filtersUnlocked: !isGuest && p.unlocked,
    unlockCost: FILTER_UNLOCK_PRICE,
    options: { languages: LANGUAGE_OPTIONS, interests: INTEREST_OPTIONS, regions: REGION_OPTIONS },
  };
};

app.get('/api/matching/preferences', requireAuth({ allowGuest: true }), (req, res) => {
  res.json(prefsPayload(req.auth.userId, req.auth.isGuest));
});

app.post('/api/matching/preferences', requireAuth(), requireTerms, prefsLimiter, async (req, res) => {
  const v = validatePrefs(req.body);
  if (v.error) return res.status(400).json({ error: v.error });
  const userId = req.auth.userId;
  const next = { ...prefsOf(userId), ...v.value };
  try {
    await db.savePreferences(userId, next);
  } catch (e) {
    console.error('[PREFS] save failed:', e.message);
    return dbBusy(res);
  }
  prefs.set(userId, next);
  res.json({ success: true, ...prefsPayload(userId, false) });
});

app.post('/api/matching/unlock-filter', requireAuth(), requireTerms, prefsLimiter, async (req, res) => {
  const user = req.auth.record;
  const cur = prefsOf(user.userId);
  if (cur.unlocked) return res.json({ success: true, already: true, newBalance: user.coins });
  if (unlockInFlight.has(user.userId)) return res.status(429).json({ error: 'Please wait a moment.' });

  unlockInFlight.add(user.userId);
  try {
    let result;
    try {
      result = await db.unlockFilters(user.userId, FILTER_UNLOCK_PRICE);
      if (!result) { // memory-only mode
        if (user.coins < FILTER_UNLOCK_PRICE) throw new Error('insufficient_coins');
        user.coins -= FILTER_UNLOCK_PRICE;
        result = { already: false, newBalance: user.coins };
      }
    } catch (e) {
      if (String(e.message).includes('insufficient_coins')) {
        return res.status(402).json({ error: 'Not enough coins.', balance: user.coins, needed: FILTER_UNLOCK_PRICE - user.coins });
      }
      console.error('[FILTERS] unlock failed:', e.message);
      return dbBusy(res);
    }
    user.coins = result.newBalance;
    prefs.set(user.userId, { ...cur, unlocked: true });
    if (!result.already) {
      pushLedger({ transactionId: 'tx_' + uuidv4(), userId: user.userId, entryType: 'debit', coinDelta: -FILTER_UNLOCK_PRICE,
        source: 'filter_unlock', productId: 'advanced_filters', reference: null, timestamp: Date.now() });
    }
    res.json({ success: true, already: result.already, newBalance: user.coins });
  } finally {
    unlockInFlight.delete(user.userId);
  }
});

// A hint only (never a promise): how many people are searching in this mode right now.
app.get('/api/matching/availability', requireAuth({ allowGuest: true }), (req, res) => {
  const mode = CALL_MODES.has(req.query.mode) ? req.query.mode : 'audio';
  const searching = matchQueue.filter((q) => q.connected && q.queueMode === mode && q.userId !== req.auth.userId).length;
  res.json({ mode, searching });
});

// Does `owner`'s active hard filter accept `other`'s profile? (language + region)
function acceptsProfile(ownerId, otherId, ownerBroadened) {
  const f = prefs.get(ownerId);
  if (!f || !f.unlocked || !f.filtersOn || ownerBroadened) return true;
  const o = prefsOf(otherId);
  if (f.languages.length && !o.languages.some((l) => f.languages.includes(l))) return false;
  if (f.region !== 'any' && o.region !== f.region) return false;
  return true;
}
const hasActiveFilters = (userId) => {
  const f = prefs.get(userId);
  return !!(f && f.unlocked && f.filtersOn && (f.languages.length || f.region !== 'any' || f.interests.length));
};
// Interest overlap only ranks candidates; it never excludes anyone.
const interestScore = (aId, bId) => {
  const a = prefsOf(aId);
  if (!a.unlocked || !a.filtersOn) return 0;
  const b = prefsOf(bId);
  return a.interests.filter((i) => b.interests.includes(i)).length;
};

// ---------------- Rewarded ads: AdMob Server-Side Verification ----------------
const REWARD_COINS = 10; // fixed server-side; never trust the client
const REWARD_NONCE_TTL_MS = 15 * 60 * 1000;
const REWARD_MIN_INTERVAL_MS = 20 * 1000;
const REWARD_DAILY_CAP = 10;
const ADMOB_REWARDED_AD_UNIT = process.env.ADMOB_REWARDED_AD_UNIT || '';
const rewardNonces = new Map();

app.post('/api/ads/reward-nonce', requireAuth(), requireTerms, (req, res) => {
  const userId = req.auth.userId;
  const now = Date.now();
  for (const [n, r] of rewardNonces) if (now - r.createdAt > 24 * 3600 * 1000) rewardNonces.delete(n);
  const mine = [...rewardNonces.values()].filter((r) => r.userId === userId);
  if (mine.length >= REWARD_DAILY_CAP) return res.status(429).json({ success: false, error: 'Daily reward limit reached. Try again tomorrow.' });
  if (mine.length && now - Math.max(...mine.map((r) => r.createdAt)) < REWARD_MIN_INTERVAL_MS) {
    return res.status(429).json({ success: false, error: 'Please wait a moment before the next reward.' });
  }
  const nonce = 'rw_' + uuidv4().replace(/-/g, '');
  rewardNonces.set(nonce, { userId, createdAt: now, credited: false, balance: null });
  res.json({ success: true, nonce, coins: REWARD_COINS });
});

// Called by Google AdMob, not by the app. Signature-verified.
app.get('/api/ads/ssv', async (req, res) => {
  const rawQuery = req.originalUrl.split('?')[1] || '';
  let params;
  try {
    params = await verifySsvQuery(rawQuery);
  } catch (e) {
    return res.status(400).json({ success: false, error: e.message });
  }
  if (ADMOB_REWARDED_AD_UNIT && params.ad_unit !== ADMOB_REWARDED_AD_UNIT) {
    return res.status(400).json({ success: false, error: 'unexpected ad unit' });
  }
  const txId = params.transaction_id;
  try {
    if (await db.adTxExists(txId)) return res.json({ success: true, duplicate: true });
  } catch (e) {
    console.error('[DB] adTxExists failed:', e.message);
    return res.status(503).json({ success: false, error: 'temporarily unavailable' }); // AdMob retries
  }
  const rec = rewardNonces.get(params.custom_data);
  if (!rec || rec.credited || rec.userId !== params.user_id || Date.now() - rec.createdAt > REWARD_NONCE_TTL_MS) {
    return res.status(400).json({ success: false, error: 'invalid or expired reward' });
  }
  const user = users.get(rec.userId);
  if (!user) return res.status(404).json({ success: false, error: 'user not found' });
  try {
    if (!(await db.claimAdTx(txId, rec.userId))) return res.json({ success: true, duplicate: true });
    const dbBalance = await db.addCoins(rec.userId, REWARD_COINS, 'admob_rewarded_ssv', null, txId);
    user.coins = dbBalance !== null ? dbBalance : user.coins + REWARD_COINS;
  } catch (e) {
    console.error('[DB] reward credit failed:', e.message);
    return res.status(503).json({ success: false, error: 'temporarily unavailable' }); // AdMob retries
  }
  rec.credited = true;
  rec.balance = user.coins;
  pushLedger({
    transactionId: 'tx_' + uuidv4(), userId: rec.userId, entryType: 'credit', coinDelta: REWARD_COINS,
    source: 'admob_rewarded_ssv', reference: txId, timestamp: Date.now(),
  });
  res.json({ success: true });
});

app.post('/api/ads/reward-status', requireAuth(), (req, res) => {
  const rec = rewardNonces.get((req.body || {}).nonce);
  if (!rec || rec.userId !== req.auth.userId) return res.status(404).json({ success: false, error: 'Unknown reward.' });
  res.json({ success: true, credited: rec.credited, newBalance: rec.balance, coinsEarned: rec.credited ? REWARD_COINS : 0 });
});

// ---------------- ICE / TURN servers (credentials are short-lived) ----------------
app.get('/api/ice-servers', requireAuth({ allowGuest: true }), (req, res) => {
  const servers = [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun1.l.google.com:19302' }];
  const urls = (process.env.TURN_URLS || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (urls.length) {
    if (process.env.TURN_SECRET) {
      // coturn "use-auth-secret" ephemeral credentials
      const username = `${Math.floor(Date.now() / 1000) + 3600}:${req.auth.userId}`;
      const credential = crypto.createHmac('sha1', process.env.TURN_SECRET).update(username).digest('base64');
      servers.push({ urls, username, credential });
    } else if (process.env.TURN_USERNAME && process.env.TURN_CREDENTIAL) {
      servers.push({ urls, username: process.env.TURN_USERNAME, credential: process.env.TURN_CREDENTIAL });
    }
  }
  res.json({ iceServers: servers, hasTurn: servers.length > 2 });
});

// ---------------- Safety: report / block ----------------
function hadCallWith(userId, otherId) {
  const h = partnerHistory.get(userId);
  const t = h && h.get(otherId);
  return !!t && Date.now() - t < PARTNER_HISTORY_MS;
}

app.post('/api/safety/report', requireAuth({ allowGuest: true }), safetyLimiter, async (req, res) => {
  const { reportedUserId, category, description, callId } = req.body || {};
  const reporterId = req.auth.userId;
  if (!isId(reportedUserId) || reportedUserId === reporterId) return res.status(400).json({ error: 'Invalid report.' });
  if (!hadCallWith(reporterId, reportedUserId)) {
    return res.status(403).json({ error: 'You can only report someone you recently talked to.' });
  }
  if (reportQueue.some((r) => r.reporterId === reporterId && r.reportedUserId === reportedUserId && r.callId === (callId || null))) {
    return res.json({ success: true, duplicate: true });
  }
  const report = {
    reportId: 'rep_' + uuidv4().slice(0, 8),
    reporterId, reportedUserId,
    category: REPORT_CATEGORIES.has(category) ? category : 'other',
    description: cleanText(description, 500),
    callId: typeof callId === 'string' && /^room_[0-9a-f-]{36}$/.test(callId) ? callId : null,
    status: 'pending_review', createdAt: Date.now(),
  };
  try {
    await db.insertReport(report);
  } catch (e) {
    console.error('[DB] insertReport failed:', e.message);
    return dbBusy(res);
  }
  reportQueue.push(report);
  if (reportQueue.length > 5000) reportQueue.shift();
  console.log(`[SAFETY] report ${report.reportId} filed (${report.category})`);
  res.json({ success: true, reportId: report.reportId });
});

app.post('/api/safety/block', requireAuth({ allowGuest: true }), safetyLimiter, async (req, res) => {
  const { blockedUserId } = req.body || {};
  const blockerId = req.auth.userId;
  if (!isId(blockedUserId) || blockedUserId === blockerId) return res.status(400).json({ error: 'Invalid block.' });
  if (!blockedPairs.has(getBlockKey(blockerId, blockedUserId))) {
    const n = blocksByUser.get(blockerId) || 0;
    if (n >= 500) return res.status(429).json({ error: 'Block list is full.' });
    try {
      await db.insertBlock(blockerId, blockedUserId);
    } catch (e) {
      console.error('[DB] insertBlock failed:', e.message);
      return dbBusy(res);
    }
    blocksByUser.set(blockerId, n + 1);
    blockedPairs.add(getBlockKey(blockerId, blockedUserId));
  }
  // If they are in a call with the blocked user right now, end it.
  const room = activeCalls.get(sockets.get(blockerId)?.currentRoomId);
  if (room && (room.user1.id === blockedUserId || room.user2.id === blockedUserId)) endRoom(room.roomId, blockerId, 'Stranger left the call');
  res.json({ success: true });
});

// ---------------- Admin ----------------
app.get('/api/admin/data', adminLimiter, requireAdmin, (req, res) => {
  res.json({
    usersCount: users.size,
    guestsCount: guestSessions.size,
    activeCallsCount: activeCalls.size,
    reports: reportQueue.slice(-200),
    recentLedger: walletLedgers.slice(-20),
    activeCallsList: Array.from(activeCalls.entries()).map(([id, call]) => ({
      id, user1: call.user1.displayName, user2: call.user2.displayName,
      duration: Math.floor((Date.now() - call.startedAt) / 1000), mode: call.mode,
    })),
  });
});


// ---------------- Account deletion (required by Google Play) ----------------
const accountLimiter = rateLimit({ windowMs: 3600 * 1000, max: 5, name: 'account' });

/** Stops whatever the person is doing right now and closes their connection. */
function kickUser(userId, reason) {
  matchQueue = matchQueue.filter((q) => q.userId !== userId);
  const s = sockets.get(userId);
  if (!s) return;
  if (s.currentRoomId) endRoom(s.currentRoomId, userId, 'Stranger disconnected');
  s.emit('account-notice', { reason: reason || 'Disconnected' });
  s.disconnect(true);
  sockets.delete(userId);
}

function removeUserFromMemory(user) {
  const id = user.userId;
  users.delete(id);
  normalizedUsernames.delete(user.normalizedUsername);
  if (user.googleSub) googleSubs.delete(user.googleSub);
  if (user.email && emailToUser.get(user.email) === id) emailToUser.delete(user.email);
  if (user.phone && phoneToUser.get(user.phone) === id) phoneToUser.delete(user.phone);
  partnerHistory.delete(id);
  prefs.delete(id);
  blocksByUser.delete(id);
  for (const key of Array.from(blockedPairs)) {
    if (key.split(':::').includes(id)) blockedPairs.delete(key);
  }
  for (let i = walletLedgers.length - 1; i >= 0; i--) if (walletLedgers[i].userId === id) walletLedgers.splice(i, 1);
}

app.delete('/api/account', requireAuth({ allowGuest: true }), accountLimiter, async (req, res) => {
  if ((req.body || {}).confirm !== 'DELETE') return res.status(400).json({ error: 'Confirmation required.' });
  // A guest has nothing stored except a temporary session (and the device allowance, which must survive).
  if (req.auth.isGuest) return res.json({ success: true, guest: true });
  const user = req.auth.record;
  try {
    await db.deleteUser(user.userId);
  } catch (e) {
    console.error('[DB] deleteUser failed:', e.message);
    return dbBusy(res);
  }
  kickUser(user.userId, 'Account deleted');
  removeUserFromMemory(user);
  console.log(`[ACCOUNT] ${user.userId} deleted by the user`);
  res.json({ success: true });
});

// ---------------- Terms and Conditions ----------------
const termsLimiter = rateLimit({ windowMs: 3600 * 1000, max: 30, name: 'terms' });
app.post('/api/terms/accept', requireAuth({ allowGuest: true }), termsLimiter, async (req, res) => {
  const version = (req.body || {}).version;
  if (version !== TERMS_VERSION) {
    return res.status(409).json({ error: 'These terms were updated. Please update the app and try again.', currentVersion: TERMS_VERSION });
  }
  const rec = req.auth.record;
  if (!req.auth.isGuest) {
    try {
      await db.setTermsAccepted(rec.userId, TERMS_VERSION);
    } catch (e) {
      console.error('[DB] setTermsAccepted failed:', e.message);
      return dbBusy(res);
    }
  }
  rec.termsVersion = TERMS_VERSION; // guests: remembered for their session
  res.json({ success: true, termsVersion: TERMS_VERSION });
});

// Fresh copy of the signed-in member's own profile (coins can change on the server).
app.get('/api/me', requireAuth(), (req, res) => {
  res.json({ success: true, user: publicUserOf(req.auth.record) });
});

// ---------------- Admin tools (X-Admin-Password header) ----------------
const maskEmail = (e) => (e && e.includes('@') ? e.slice(0, 2) + '***@' + e.split('@')[1] : '');
const nameOf = (id) => users.get(id)?.username || guestSessions.get(id)?.displayName || id;
function findUser(idOrName) {
  if (typeof idOrName !== 'string' || idOrName.length > 64) return null;
  const v = idOrName.trim();
  return users.get(v) || users.get(normalizedUsernames.get(v.toLowerCase())) || null;
}
const adminLog = (msg) => console.log('[ADMIN] ' + msg);

app.get('/api/admin/overview', adminLimiter, requireAdmin, (req, res) => {
  const recentUsers = Array.from(users.values()).sort((a, b) => b.createdAt - a.createdAt).slice(0, 30).map((u) => ({
    userId: u.userId, username: u.username, displayName: u.displayName, status: u.status, coins: u.coins,
    joined: new Date(u.createdAt).toISOString(), email: maskEmail(u.email), online: sockets.has(u.userId),
  }));
  res.json({
    totalUsers: users.size, guests: guestSessions.size, onlineNow: sockets.size, searching: matchQueue.length,
    inCall: activeCalls.size * 2, activeCallsCount: activeCalls.size,
    openReports: reportQueue.filter((r) => r.status === 'pending_review').length,
    activeCalls: Array.from(activeCalls.entries()).map(([id, c]) => ({
      id, users: [c.user1.displayName, c.user2.displayName], mode: c.mode, seconds: Math.floor((Date.now() - c.startedAt) / 1000),
    })),
    reports: reportQueue.slice(-100).reverse().map((r) => ({
      ...r, reporterName: nameOf(r.reporterId), reportedName: nameOf(r.reportedUserId),
    })),
    recentUsers,
    recentLedger: walletLedgers.slice(-20).reverse(),
  });
});

app.post('/api/admin/gift-coins', adminLimiter, requireAdmin, async (req, res) => {
  const { userId, amount } = req.body || {};
  const n = Number(amount);
  if (!Number.isInteger(n) || n === 0 || Math.abs(n) > 100000) {
    return res.status(400).json({ error: 'Amount must be a whole number (not 0), at most 100000 either way.' });
  }
  const user = findUser(userId);
  if (!user) return res.status(404).json({ error: 'User not found.' });
  if (user.coins + n < 0) return res.status(400).json({ error: 'That would make the balance negative.' });
  try {
    const bal = await db.addCoins(user.userId, n, n > 0 ? 'admin_gift' : 'admin_adjust');
    user.coins = bal !== null ? bal : user.coins + n;
  } catch (e) {
    console.error('[DB] admin gift failed:', e.message);
    return dbBusy(res);
  }
  pushLedger({ transactionId: 'tx_' + uuidv4(), userId: user.userId, entryType: n > 0 ? 'credit' : 'debit', coinDelta: n,
    source: n > 0 ? 'admin_gift' : 'admin_adjust', timestamp: Date.now() });
  sockets.get(user.userId)?.emit('wallet-updated', { coins: user.coins });
  adminLog(`coins ${n > 0 ? '+' : ''}${n} -> ${user.userId}`);
  res.json({ success: true, newBalance: user.coins });
});

app.post('/api/admin/broadcast', adminLimiter, requireAdmin, (req, res) => {
  const message = cleanText((req.body || {}).message, 200);
  if (!message) return res.status(400).json({ error: 'Message is empty.' });
  io.emit('admin-broadcast', { message });
  adminLog(`broadcast to ${sockets.size} users`);
  res.json({ success: true, delivered: sockets.size });
});

app.post('/api/admin/kill-call', adminLimiter, requireAdmin, (req, res) => {
  const roomId = (req.body || {}).roomId;
  if (typeof roomId !== 'string' || !activeCalls.has(roomId)) return res.status(404).json({ error: 'That call is not active.' });
  endRoom(roomId, null, 'The conversation was ended by a moderator.');
  adminLog(`call ${roomId} ended`);
  res.json({ success: true });
});

app.post('/api/admin/suspend', adminLimiter, requireAdmin, async (req, res) => {
  const { userId, suspended } = req.body || {};
  const user = findUser(userId);
  if (!user) return res.status(404).json({ error: 'User not found.' });
  const status = suspended === false ? 'active' : 'suspended';
  try {
    await db.setUserStatus(user.userId, status);
  } catch (e) {
    console.error('[DB] setUserStatus failed:', e.message);
    return dbBusy(res);
  }
  user.status = status;
  if (status === 'suspended') kickUser(user.userId, 'Account suspended');
  adminLog(`${user.userId} -> ${status}`);
  res.json({ success: true, status });
});

app.post('/api/admin/report-status', adminLimiter, requireAdmin, async (req, res) => {
  const { reportId, status } = req.body || {};
  if (!['resolved', 'dismissed', 'pending_review'].includes(status)) return res.status(400).json({ error: 'Bad status.' });
  const report = reportQueue.find((r) => r.reportId === reportId);
  if (!report) return res.status(404).json({ error: 'Report not found.' });
  try {
    await db.updateReportStatus(report.reportId, status);
  } catch (e) {
    console.error('[DB] updateReportStatus failed:', e.message);
    return dbBusy(res);
  }
  report.status = status;
  adminLog(`report ${report.reportId} -> ${status}`);
  res.json({ success: true });
});

// Disabled legacy endpoint: kept only to return a clear error to old clients.
app.post('/api/wallet/reward-ad', (req, res) => res.status(410).json({ error: 'Disabled. Use /api/ads/reward-nonce with AdMob SSV.' }));

// Bad JSON etc. -> clean JSON error, no stack traces
app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  res.status(err.status && err.status < 500 ? err.status : 400).json({ error: 'Bad request' });
});

// ======================== REAL-TIME: MATCHMAKING & WEBRTC ========================
const sockets = new Map(); // userId -> socket (latest connection)

function recordPartners(a, b) {
  const now = Date.now();
  for (const [x, y] of [[a, b], [b, a]]) {
    let m = partnerHistory.get(x);
    if (!m) { m = new Map(); partnerHistory.set(x, m); }
    m.set(y, now);
    for (const [k, t] of m) if (now - t > PARTNER_HISTORY_MS) m.delete(k);
  }
}

function recentlyMatched(a, b) {
  const t = partnerHistory.get(a)?.get(b);
  return !!t && Date.now() - t < REMATCH_COOLDOWN_MS;
}

/** Ends a call for both sides and tells the other participant. */
function endRoom(roomId, byUserId, reason) {
  const call = activeCalls.get(roomId);
  if (!call) return;
  activeCalls.delete(roomId);
  for (const p of [call.user1, call.user2]) {
    const s = io.sockets.sockets.get(p.socketId);
    if (!s) continue;
    s.currentRoomId = null;
    s.leave(roomId);
    if (p.id !== byUserId) s.emit('call-ended', { reason: reason || 'Stranger ended the call' });
  }
}

function guestExpired(socket) {
  return socket.isGuest && (guestSessions.get(socket.userId)?.expiresAt ?? 0) <= Date.now();
}

function validSdp(sdp) {
  return sdp && typeof sdp === 'object' && typeof sdp.sdp === 'string' && sdp.sdp.length <= 30000 &&
    (sdp.type === 'offer' || sdp.type === 'answer');
}

function validCandidate(c) {
  return c && typeof c === 'object' && typeof c.candidate === 'string' && c.candidate.length <= 2000 &&
    (c.sdpMid == null || typeof c.sdpMid === 'string') &&
    (c.sdpMLineIndex == null || Number.isInteger(c.sdpMLineIndex));
}

// Authenticate every socket from its token. userId can't be spoofed by payloads.
io.use((socket, next) => {
  const token = socket.handshake.auth && socket.handshake.auth.token;
  const acct = accountFromToken(token);
  if (!acct) return next(new Error('unauthorized'));
  if (!acct.isGuest && acct.record.status === 'suspended') return next(new Error('suspended'));
  socket.userId = acct.userId;
  socket.isGuest = acct.isGuest;
  socket.displayName = cleanText(acct.record.displayName, 30) || 'Anonymous';
  socket.avatarUrl = acct.record.avatarUrl || '';
  next();
});

io.on('connection', (socket) => {
  // One live connection per account: a newer one replaces the older.
  const old = sockets.get(socket.userId);
  if (old && old.id !== socket.id) { endRoom(old.currentRoomId, socket.userId, 'Stranger disconnected'); old.disconnect(true); }
  sockets.set(socket.userId, socket);
  socket.currentRoomId = null;

  // Flood protection: too many events in a short window -> disconnect.
  let windowStart = Date.now(); let count = 0;
  socket.use((packet, next) => {
    const now = Date.now();
    if (now - windowStart > 10000) { windowStart = now; count = 0; }
    if (++count > 200) { socket.disconnect(true); return; }
    next();
  });

  // Every handler is validated and wrapped: a bad packet can never crash the server.
  const on = (event, handler) => socket.on(event, (...args) => {
    try {
      const data = args[0] && typeof args[0] === 'object' && !Array.isArray(args[0]) ? args[0] : {};
      handler(data);
    } catch (e) {
      console.error(`[SOCKET] ${event} handler error:`, e.message);
    }
  });

  on('register-client', () => {
    if (guestExpired(socket)) return socket.emit('guest-expired', { message: 'Guest session expired. Please sign in.' });
    if (socket.isGuest) {
      const s = guestSessions.get(socket.userId);
      socket.emit('guest-status', { remainingSeconds: Math.max(0, Math.floor((s.expiresAt - Date.now()) / 1000)) });
    }
  });

  on('join-queue', ({ mode, broaden }) => {
    if (mustAcceptTerms(socket.userId)) return socket.emit('terms-required', { version: TERMS_VERSION });
    const callMode = CALL_MODES.has(mode) ? mode : 'audio'; // old app versions send no mode
    if (guestExpired(socket)) return socket.emit('guest-expired', { message: 'Guest access limit reached.' });
    if (socket.currentRoomId) endRoom(socket.currentRoomId, socket.userId, 'Stranger left the call');
    matchQueue = matchQueue.filter((s) => s.id !== socket.id && s.userId !== socket.userId && s.connected);
    socket.queueMode = callMode;
    socket.broaden = broaden === true; // "broaden preferences": ignore MY filters for this search
    const filtered = !socket.broaden && hasActiveFilters(socket.userId);

    // Everyone eligible by the basic rules AND by both people's filters; best interest overlap first, then FIFO.
    let idx = -1; let best = -1;
    matchQueue.forEach((c, i) => {
      if (c.queueMode !== callMode || c.userId === socket.userId || isBlocked(socket.userId, c.userId) ||
          recentlyMatched(socket.userId, c.userId) || guestExpired(c)) return;
      if (!acceptsProfile(socket.userId, c.userId, socket.broaden) || !acceptsProfile(c.userId, socket.userId, c.broaden)) return;
      const score = filtered ? interestScore(socket.userId, c.userId) : 0;
      if (score > best) { best = score; idx = i; }
    });

    if (idx === -1) {
      matchQueue.push(socket);
      return socket.emit('queue-status', { status: 'searching', queuePosition: matchQueue.length, filtered });
    }
    const [partner] = matchQueue.splice(idx, 1);
    const roomId = 'room_' + uuidv4();
    socket.join(roomId);
    partner.join(roomId);
    socket.currentRoomId = roomId;
    partner.currentRoomId = roomId;
    recordPartners(socket.userId, partner.userId);
    activeCalls.set(roomId, {
      roomId, startedAt: Date.now(), mode: callMode,
      user1: { id: socket.userId, socketId: socket.id, displayName: socket.displayName },
      user2: { id: partner.userId, socketId: partner.id, displayName: partner.displayName },
    });
    socket.emit('matched', { roomId, mode: callMode, isInitiator: true, stranger: { id: partner.userId, displayName: partner.displayName, avatarUrl: partner.avatarUrl } });
    partner.emit('matched', { roomId, mode: callMode, isInitiator: false, stranger: { id: socket.userId, displayName: socket.displayName, avatarUrl: socket.avatarUrl } });
  });

  on('leave-queue', () => {
    matchQueue = matchQueue.filter((s) => s.id !== socket.id);
    socket.emit('queue-status', { status: 'idle' });
  });

  const inRoom = (roomId) => typeof roomId === 'string' && socket.currentRoomId === roomId && activeCalls.has(roomId);
  const hasMedia = (roomId) => activeCalls.get(roomId)?.mode !== 'text'; // text rooms carry no WebRTC

  on('webrtc-offer', ({ roomId, sdp }) => {
    if (inRoom(roomId) && hasMedia(roomId) && validSdp(sdp)) socket.to(roomId).emit('webrtc-offer', { sdp, senderId: socket.userId });
  });
  on('webrtc-answer', ({ roomId, sdp }) => {
    if (inRoom(roomId) && hasMedia(roomId) && validSdp(sdp)) socket.to(roomId).emit('webrtc-answer', { sdp, senderId: socket.userId });
  });
  on('webrtc-ice-candidate', ({ roomId, candidate }) => {
    if (inRoom(roomId) && hasMedia(roomId) && validCandidate(candidate)) socket.to(roomId).emit('webrtc-ice-candidate', { candidate });
  });
  // Text chat: used by text-chat rooms AND during audio/video calls. Messages are relayed
  // only (never stored). Plain text, length limited, and throttled per sender.
  on('chat-message', ({ roomId, text }) => {
    if (!inRoom(roomId) || typeof text !== 'string') return;
    const clean = text.replace(/[\u0000-\u001F\u007F]/g, ' ').trim().slice(0, CHAT_MAX_LEN);
    if (!clean) return;
    const now = Date.now();
    if (now - (socket.lastChatAt || 0) < 250) return;
    socket.lastChatAt = now;
    socket.to(roomId).emit('chat-message', { text: clean, ts: now });
  });
  on('end-call', ({ roomId }) => { if (inRoom(roomId)) endRoom(roomId, socket.userId, 'Stranger ended the call'); });
  on('skip-call', ({ roomId }) => { if (inRoom(roomId)) endRoom(roomId, socket.userId, 'Stranger skipped to next call'); });

  socket.on('disconnect', () => {
    matchQueue = matchQueue.filter((s) => s.id !== socket.id);
    if (socket.currentRoomId) endRoom(socket.currentRoomId, socket.userId, 'Stranger disconnected');
    if (sockets.get(socket.userId) === socket) sockets.delete(socket.userId);
  });
});

// Server-side guest time enforcement for calls already in progress.
setInterval(() => {
  for (const [roomId, call] of activeCalls) {
    const expired = [call.user1, call.user2].filter((p) => {
      const s = io.sockets.sockets.get(p.socketId);
      return s && guestExpired(s);
    });
    if (!expired.length) continue;
    for (const p of expired) io.sockets.sockets.get(p.socketId).emit('guest-expired', { message: 'Guest access limit reached.' });
    endRoom(roomId, expired[0].id, 'Stranger ended the call');
  }
}, GUEST_SWEEP_MS).unref();

process.on('unhandledRejection', (e) => console.error('[UNHANDLED REJECTION]', e && e.message));

// Reload everything saved in Supabase, then start accepting connections.
async function loadFromDb() {
  const d = await db.loadAll();
  for (const u of d.users) {
    users.set(u.userId, u);
    normalizedUsernames.set(u.normalizedUsername, u.userId);
    if (u.googleSub) googleSubs.set(u.googleSub, u.userId);
    if (u.emailVerified && u.email && !emailToUser.has(u.email)) emailToUser.set(u.email, u.userId);
    if (u.phone) phoneToUser.set(u.phone, u.userId);
  }
  for (const g of d.guests) { guestSessions.set(g.sessionId, g); guestByDevice.set(g.deviceId, g.sessionId); }
  for (const b of d.blocks) {
    const key = getBlockKey(b.blockerId, b.blockedId);
    if (!blockedPairs.has(key)) blockedPairs.add(key);
    blocksByUser.set(b.blockerId, (blocksByUser.get(b.blockerId) || 0) + 1);
  }
  reportQueue.push(...d.reports);
  walletLedgers.push(...d.ledger);
  try {
    for (const p of await db.loadPreferences()) prefs.set(p.userId, { languages: p.languages, interests: p.interests, region: p.region, filtersOn: p.filtersOn, unlocked: p.unlocked });
  } catch (e) {
    console.warn('[FILTERS] user_preferences not readable (run supabase_migration_matching_filters.sql). Filters are off until then:', e.message);
  }
  try {
    const cat = await db.loadGiftCatalog();
    if (cat && cat.length) giftCatalog = cat;
  } catch (e) {
    console.warn('[GIFTS] gift_catalog not readable (run supabase_migration_wallet_gifts.sql). Using built-in prices:', e.message);
  }
  if (IS_PROD && !db.enabled) console.warn('[WARN] Running in PRODUCTION without Supabase: all data is lost on every restart!');
  console.log(`[DB] ${db.enabled ? 'Supabase connected' : 'memory-only mode'}: ` +
    `${d.users.length} users, ${d.guests.length} guests, ${d.blocks.length} blocks, ${d.reports.length} reports loaded`);
}

loadFromDb()
  .then(() => {
    server.listen(PORT, '0.0.0.0', () => {
      console.log(`ECHO server online on port ${PORT}`);
    });
  })
  .catch((e) => {
    console.error('[DB] Could not load data from Supabase:', e.message);
    console.error('Check SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in .env and that supabase_schema.sql was run.');
    process.exit(1);
  });

// Stop cleanly when the host restarts / redeploys the service.
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`[SHUTDOWN] ${sig} received, closing...`);
    io.close();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 8000).unref();
  });
}

// Exposed for the test-suite only (nothing else imports server.js).
module.exports = { app, server, otp };
