/**
 * Google Sign-In: verifies a Google ID token (JWT, RS256) on the server.
 * The app sends the ID token; we check Google's signature, audience, issuer and expiry.
 * Docs: https://developers.google.com/identity/sign-in/web/backend-auth
 */
const crypto = require('crypto');

const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const CERTS_TTL_MS = 60 * 60 * 1000;
const VALID_ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);

const cache = { fetchedAt: 0, keys: new Map() };

async function fetchGoogleCerts() {
  const res = await fetch(GOOGLE_CERTS_URL);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const body = await res.json();
  return new Map(body.keys.map((k) => [k.kid, k]));
}

async function getKey(kid, fetcher) {
  if (Date.now() - cache.fetchedAt > CERTS_TTL_MS || !cache.keys.has(kid)) {
    try {
      cache.keys = await fetcher();
      cache.fetchedAt = Date.now();
    } catch (e) {
      if (!cache.keys.has(kid)) throw new Error('could not load Google keys: ' + e.message);
    }
  }
  const jwk = cache.keys.get(kid);
  if (!jwk) throw new Error('unknown signing key');
  return crypto.createPublicKey({ key: jwk, format: 'jwk' });
}

/**
 * @param {string} idToken
 * @param {string[]} audiences  allowed OAuth client IDs (the Web client ID)
 * @returns {{sub:string,email:string,name:string,picture:string}}
 */
async function verifyGoogleIdToken(idToken, audiences, fetcher = fetchGoogleCerts) {
  if (typeof idToken !== 'string' || idToken.length > 4096) throw new Error('bad token');
  const parts = idToken.split('.');
  if (parts.length !== 3) throw new Error('bad token');

  let header, payload;
  try {
    header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch (_) {
    throw new Error('bad token');
  }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new Error('bad algorithm');

  const key = await getKey(header.kid, fetcher);
  const valid = crypto.verify('RSA-SHA256', Buffer.from(parts[0] + '.' + parts[1]), key, Buffer.from(parts[2], 'base64url'));
  if (!valid) throw new Error('bad signature');

  const now = Math.floor(Date.now() / 1000);
  if (!VALID_ISSUERS.has(payload.iss)) throw new Error('bad issuer');
  if (!audiences.includes(payload.aud)) throw new Error('bad audience');
  if (typeof payload.exp !== 'number' || payload.exp < now - 30) throw new Error('token expired');
  if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('no subject');
  if (typeof payload.email !== 'string' || !(payload.email_verified === true || payload.email_verified === 'true')) {
    throw new Error('email not verified');
  }
  return {
    sub: payload.sub,
    email: payload.email,
    name: typeof payload.name === 'string' ? payload.name : '',
    picture: typeof payload.picture === 'string' ? payload.picture : '',
  };
}

function resetCacheForTests() {
  cache.fetchedAt = 0;
  cache.keys = new Map();
}

module.exports = { verifyGoogleIdToken, resetCacheForTests };
