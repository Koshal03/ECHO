/**
 * AdMob rewarded-ad server-side verification (SSV) for the Node backend.
 * Verifies Google's ECDSA signature so clients can't mint coins directly.
 * Docs: https://developers.google.com/admob/android/ssv
 */
const crypto = require('crypto');

const VERIFIER_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
const KEYS_TTL_MS = 24 * 3600 * 1000;

const cache = { fetchedAt: 0, keys: new Map() };

async function fetchVerifierKeys() {
  const res = await fetch(VERIFIER_KEYS_URL);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const data = await res.json();
  return new Map(data.keys.map((k) => [Number(k.keyId), k.pem]));
}

async function getPublicKey(keyId, fetcher) {
  const stale = Date.now() - cache.fetchedAt > KEYS_TTL_MS;
  if (stale || !cache.keys.has(keyId)) {
    try {
      cache.keys = await fetcher();
      cache.fetchedAt = Date.now();
    } catch (e) {
      if (!cache.keys.has(keyId)) throw new Error('could not load verifier keys: ' + e.message);
    }
  }
  const pem = cache.keys.get(keyId);
  if (!pem) throw new Error('unknown key_id');
  return crypto.createPublicKey(pem);
}

/** rawQuery: the query string WITHOUT the leading '?', exactly as received. */
async function verifySsvQuery(rawQuery, fetcher = fetchVerifierKeys) {
  const marker = '&signature=';
  const idx = rawQuery.indexOf(marker);
  if (idx < 0) throw new Error('missing signature');
  const message = Buffer.from(rawQuery.slice(0, idx), 'utf8');
  const params = Object.fromEntries(new URLSearchParams(rawQuery));
  if (!params.signature || !params.key_id) throw new Error('missing signature or key_id');
  const key = await getPublicKey(Number(params.key_id), fetcher);
  const sig = Buffer.from(params.signature.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  const ok = crypto.verify('sha256', message, key, sig); // DER-encoded ECDSA by default
  if (!ok) throw new Error('bad signature');
  return params;
}

function resetCacheForTests() {
  cache.fetchedAt = 0;
  cache.keys = new Map();
}

module.exports = { verifySsvQuery, resetCacheForTests };
