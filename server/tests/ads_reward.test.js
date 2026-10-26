process.env.TERMS_ENFORCE = '0'; // these suites do not test the terms gate
process.env.DB_DISABLED = '1'; // tests never touch the real Supabase
const crypto = require('crypto');
const realFetch = global.fetch;
const { publicKey, privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const pem = publicKey.export({ type: 'spki', format: 'pem' });
// Pretend to be Google's key endpoint; everything else goes to the real fetch.
global.fetch = async (url, opts) => String(url).includes('verifier-keys.json')
  ? { ok: true, json: async () => ({ keys: [{ keyId: 4444, pem }] }) }
  : realFetch(url, opts);
process.env.PORT = '3911'; process.env.SERVER_SECRET='x';
process.chdir(require('path').join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3911';
let TOKEN = ''; const post = (p, b) => realFetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(TOKEN ? { Authorization: 'Bearer ' + TOKEN } : {}) }, body: JSON.stringify(b) }).then(async r => ({ s: r.status, j: await r.json() }));
const sign = (msg) => crypto.sign('sha256', Buffer.from(msg), privateKey).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const ssv = (msg, tamper) => { const q = `${msg}&signature=${sign(msg)}&key_id=4444`; return realFetch(base + '/api/ads/ssv?' + (tamper ? q.replace('reward_amount=1','reward_amount=9') : q)).then(async r => ({ s: r.status, j: await r.json() })); };
const ok = (c, m) => { if (!c) { console.log('FAIL:', m); process.exit(1); } console.log('ok  -', m); };

setTimeout(async () => {
  const reg = await post('/api/auth/register', { username: 'tester_one', displayName: 'Tester', email: '' });
  const uid = reg.j.user.userId; const start = reg.j.user.coins; TOKEN = reg.j.token;
  ok(uid, 'registered user ' + uid + ' with ' + start + ' coins');

  let r = await post('/api/wallet/reward-ad', { userId: uid });
  ok(r.s === 410, 'legacy free-coin endpoint is disabled (410)');
  const saved = TOKEN; TOKEN = ''; r = await post('/api/ads/reward-nonce', {}); TOKEN = saved;
  ok(r.s === 401, 'no login -> no reward nonce');
  r = await post('/api/ads/reward-nonce', { userId: uid });
  const nonce = r.j.nonce; ok(r.s === 200 && nonce, 'nonce issued');
  r = await post('/api/ads/reward-nonce', { userId: uid });
  ok(r.s === 429, 'second request within 20s is rate-limited');

  const msg = `ad_network=1&ad_unit=999&custom_data=${nonce}&reward_amount=1&reward_item=coin&timestamp=1&transaction_id=TXA&user_id=${uid}`;
  r = await ssv(msg, true);  ok(r.s === 400, 'tampered SSV callback rejected');
  r = await realFetch(base + '/api/ads/ssv?custom_data=' + nonce + '&user_id=' + uid + '&transaction_id=TXA').then(x => x.status);
  ok(r === 400, 'unsigned callback rejected');
  r = await post('/api/ads/reward-status', { userId: uid, nonce }); ok(r.j.credited === false, 'not credited before valid callback');

  r = await ssv(msg); ok(r.s === 200 && !r.j.duplicate, 'valid signed callback accepted');
  r = await post('/api/ads/reward-status', { userId: uid, nonce });
  ok(r.j.credited === true && r.j.newBalance === start + 10, 'credited exactly 10 coins -> balance ' + r.j.newBalance);
  r = await ssv(msg); ok(r.s === 200 && r.j.duplicate === true, 'retried callback is idempotent');
  r = await post('/api/ads/reward-status', { userId: uid, nonce }); ok(r.j.newBalance === start + 10, 'no double credit');

  const msg2 = `ad_network=1&ad_unit=999&custom_data=${nonce}&reward_amount=1&reward_item=coin&timestamp=2&transaction_id=TXB&user_id=${uid}`;
  r = await ssv(msg2); ok(r.s === 400, 'replaying the same nonce with a new transaction is rejected');
  const cfg = await realFetch(base + '/api/config').then(x => x.json()); ok(cfg.settings.interstitial_cooldown_seconds === 120, '/api/config served');
  console.log('ALL NODE E2E TESTS PASSED'); process.exit(0);
}, 800);
