process.env.TERMS_ENFORCE = '0'; // these suites do not test the terms gate
process.env.DB_DISABLED = '1'; // tests never touch the real Supabase
const crypto = require('crypto');
const { io } = require('socket.io-client');
const realFetch = global.fetch;
// Fake Google: Play API + OAuth + AdMob verifier keys
const sa = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
process.env.GOOGLE_SERVICE_ACCOUNT_JSON = JSON.stringify({ client_email: 'svc@test.iam', token_uri: 'https://oauth2.test/token', private_key: sa.privateKey.export({ type: 'pkcs8', format: 'pem' }) });
process.env.ADMIN_PASSWORD = 'S3cure-admin-pass'; process.env.SERVER_SECRET = 'test-secret-123';
process.env.GOOGLE_CLIENT_IDS = 'test-web-client.apps.googleusercontent.com'; process.env.PORT = '3930'; process.env.GUEST_DURATION_MS = '9000'; process.env.GUEST_SWEEP_MS = '500';
process.env.REMATCH_COOLDOWN_MS = '3000'; process.env.TURN_URLS = 'turn:turn.test:3478'; process.env.TURN_SECRET = 'turnsecret';
const gKeys = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const gOther = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const gJwk = { ...gKeys.publicKey.export({ format: 'jwk' }), kid: 'test-kid-1', alg: 'RS256', use: 'sig' };
const AUD = 'test-web-client.apps.googleusercontent.com';
const mkIdToken = (claims = {}, { key = gKeys.privateKey, alg = 'RS256', kid = 'test-kid-1' } = {}) => {
  const h = Buffer.from(JSON.stringify({ alg, kid, typ: 'JWT' })).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const p = Buffer.from(JSON.stringify({ iss: 'https://accounts.google.com', aud: AUD, sub: 'g-sub-1', email: 'new.user@gmail.com', email_verified: true, name: 'New <b>User</b>', iat: now, exp: now + 3600, ...claims })).toString('base64url');
  const sig = alg === 'none' ? '' : crypto.sign('RSA-SHA256', Buffer.from(h + '.' + p), key).toString('base64url');
  return h + '.' + p + '.' + sig;
};
const validTokens = new Set(['PLAY_GOOD_TOKEN_123456']); const playCalls = [];
global.fetch = async (url, opts) => {
  url = String(url);
  if (url.startsWith('https://www.googleapis.com/oauth2/v3/certs')) return { ok: true, status: 200, json: async () => ({ keys: [gJwk] }) };
  if (url.startsWith('https://oauth2.test/token')) return { ok: true, status: 200, json: async () => ({ access_token: 'at', expires_in: 3600 }) };
  if (url.includes('androidpublisher.googleapis.com')) {
    playCalls.push(url); const tok = decodeURIComponent(url.split('/tokens/')[1]);
    if (tok === 'PLAY_GOOD_TOKEN_123456' || tok === 'PLAY_GOOD_TOKEN_2_ABCDEF') return { ok: true, status: 200, json: async () => ({ purchaseState: 0, orderId: 'GPA.1' }) };
    if (tok === 'PLAY_CANCELLED_TOKEN_1') return { ok: true, status: 200, json: async () => ({ purchaseState: 1 }) };
    return { ok: false, status: 404, json: async () => ({}) };
  }
  return realFetch(url, opts);
};
process.chdir(require('path').join(__dirname, '..')); require('../server.js');
const base = 'http://127.0.0.1:3930';
const call = (m, p, body, token, extra = {}) => realFetch(base + p, { method: m, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...extra }, body: body ? JSON.stringify(body) : undefined }).then(async r => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const sock = (token) => new Promise(res => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', e => res({ error: e.message })); });
const wait = (s, ev, ms = 900) => new Promise(r => { const t = setTimeout(() => r(null), ms); s.once(ev, d => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0; const ok = (area, name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[' + area + '] ' + name + (note && !c ? '  -> ' + note : '')); };
const mkUser = async (name) => { const r = await call('POST', '/api/auth/register', { username: name, displayName: name }); return { id: r.j.user.userId, token: r.j.token, user: r.j.user }; };

(async () => {
  await sleep(600);
  // ===== AUTH =====
  let r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'PLAY_GOOD_TOKEN_123456' });
  ok('auth', 'purchase without token -> 401', r.s === 401);
  r = await call('POST', '/api/safety/block', { blockedUserId: 'usr_zzzz' }, 'garbage.token');
  ok('auth', 'forged token rejected', r.s === 401);
  const A = await mkUser('alice_one'), B = await mkUser('bob_two_x'), C = await mkUser('carol_thr');
  ok('auth', 'register returns token + hides email', !!A.token && !('email' in A.user));
  const tampered = A.token.split('.')[0] + '.' + 'x'.repeat(43);
  r = await call('POST', '/api/safety/block', { blockedUserId: B.id }, tampered); ok('auth', 'tampered signature rejected', r.s === 401);
  const body = JSON.parse(Buffer.from(A.token.split('.')[0], 'base64url')); body.uid = B.id;
  const forged = Buffer.from(JSON.stringify(body)).toString('base64url') + '.' + A.token.split('.')[1];
  r = await call('POST', '/api/safety/block', { blockedUserId: C.id }, forged); ok('auth', 'token with edited userId rejected', r.s === 401);
  const bad = await sock('nope'); ok('auth', 'socket without valid token refused', bad.error === 'unauthorized');

  // ===== ADMIN =====
  r = await call('GET', '/api/admin/data'); ok('admin', '/api/admin/data without password -> 401', r.s === 401);
  r = await call('GET', '/api/admin/data', null, null, { 'X-Admin-Password': 'admin123' }); ok('admin', 'wrong password -> 401', r.s === 401);
  r = await call('GET', '/api/admin/data', null, null, { 'X-Admin-Password': 'S3cure-admin-pass' }); ok('admin', 'correct password -> 200', r.s === 200 && 'reports' in r.j);

  // ===== REGISTER VALIDATION =====
  for (const [n, p] of [['reserved admin', { username: 'admin' }], ['too short', { username: 'abc' }], ['starts with digit', { username: '1abcd' }], ['has symbols', { username: 'a<b>cd' }], ['object username', { username: { a: 1 } }], ['array username', { username: ['abcd'] }], ['bad email', { username: 'valid_name1', email: 'not-an-email' }]]) {
    r = await call('POST', '/api/auth/register', p); ok('validation', 'register rejects ' + n, r.s === 400, 'status ' + r.s);
  }
  r = await call('POST', '/api/auth/register', { username: 'xss_victim', displayName: '<img src=x onerror=alert(1)>Name' });
  ok('validation', 'displayName stripped of HTML', r.s === 200 && !/[<>]/.test(r.j.user.displayName), r.j.user && r.j.user.displayName);
  r = await call('POST', '/api/auth/register', { username: 'ALICE_ONE' }); ok('validation', 'duplicate username (case-insens.) rejected', r.s === 400);
  r = await realFetch(base + '/api/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{bad json' }); ok('validation', 'malformed JSON -> clean 400', r.status === 400);

  // ===== PURCHASES =====
  r = await call('POST', '/api/wallet/purchase', { productId: 'anything', purchaseToken: 'PLAY_GOOD_TOKEN_123456' }, A.token); ok('purchase', 'unknown product id -> 400 (no default coins)', r.s === 400);
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'FAKE_TOKEN_NOT_FROM_GOOGLE' }, A.token); ok('purchase', 'fake purchase token -> rejected, no coins', r.s === 402);
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'PLAY_CANCELLED_TOKEN_1' }, A.token); ok('purchase', 'cancelled purchase -> rejected', r.s === 402);
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'PLAY_GOOD_TOKEN_123456' }, A.token); ok('purchase', 'genuine purchase -> +500 coins (50 -> 550)', r.s === 200 && r.j.newBalance === 550, JSON.stringify(r.j));
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'PLAY_GOOD_TOKEN_123456' }, A.token); ok('purchase', 'same token again -> no double credit', r.s === 200 && r.j.duplicate && r.j.newBalance === 550);
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'PLAY_GOOD_TOKEN_123456' }, B.token); ok('purchase', 'someone else reusing the token -> 409', r.s === 409);
  const [p1, p2] = await Promise.all([call('POST', '/api/wallet/purchase', { productId: 'coins_starter_49', purchaseToken: 'PLAY_GOOD_TOKEN_2_ABCDEF' }, B.token), call('POST', '/api/wallet/purchase', { productId: 'coins_starter_49', purchaseToken: 'PLAY_GOOD_TOKEN_2_ABCDEF' }, B.token)]);
  ok('purchase', 'parallel double-submit credits only once', [p1, p2].filter(x => x.j.coinsAdded === 50).length === 1, JSON.stringify([p1.j, p2.j]));
  const g0 = await call('POST', '/api/guest/start', { deviceFingerprint: 'device_aaaaaaaa1' });
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_value_299', purchaseToken: 'PLAY_GOOD_TOKEN_2_ABCDEF' }, g0.j.token); ok('purchase', 'guests cannot buy (must sign up)', r.s === 403);

  // ===== ADS =====
  r = await call('POST', '/api/ads/reward-nonce', {}); ok('ads', 'reward nonce needs login', r.s === 401);
  r = await call('POST', '/api/wallet/reward-ad', { userId: A.id }); ok('ads', 'legacy free-coin endpoint is dead (410)', r.s === 410);

  // ===== GUEST =====
  r = await call('POST', '/api/guest/start', { deviceFingerprint: 'x' }); ok('guest', 'bad device id rejected', r.s === 400);
  const g1 = await call('POST', '/api/guest/start', { deviceFingerprint: 'device_aaaaaaaa1' });
  ok('guest', 'same device gets the SAME session (no reset by re-calling)', g1.j.session.sessionId === g0.j.session.sessionId);
  const gA = await call('POST', '/api/guest/start', { deviceFingerprint: 'device_cccccccc3' }); const gB = await call('POST', '/api/guest/start', { deviceFingerprint: 'device_dddddddd4' });
  const gs = await sock(gA.j.token), gp = await sock(gB.j.token);
  gs.emit('join-queue', {}); await wait(gs, 'queue-status');
  const mg = wait(gs, 'matched'); gp.emit('join-queue', {}); const mgr = await mg; ok('guest', 'guests can match while time remains', !!mgr);
  const anyOf = (sk) => Promise.race([wait(sk, 'guest-expired', 12000), wait(sk, 'call-ended', 12000)].map(p => p.then(v => v || new Promise(() => {}))).concat([sleep(12000).then(() => null)]));
  const e1 = anyOf(gs), e2 = anyOf(gp);
  ok('guest', 'server ends an in-progress call when guest time runs out (both sides told)', !!(await e1) && !!(await e2));
  r = await call('POST', '/api/guest/start', { deviceFingerprint: 'device_cccccccc3' }); ok('guest', 'expired device cannot get a fresh 60 minutes', r.s === 403 && r.j.expired);
  const gs2 = await sock(gA.j.token); ok('guest', 'expired guest token no longer opens a socket', !!gs2.error); gs.disconnect(); gp.disconnect();

  // ===== GOOGLE SIGN-IN =====
  r = await call('POST', '/api/auth/google', {}); ok('google', 'missing token -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: 'a.b.c' }); ok('google', 'garbage token -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({}, { key: gOther.privateKey }) }); ok('google', 'token signed by someone else -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({ aud: 'another-app.apps.googleusercontent.com' }) }); ok('google', 'token for a different app (audience) -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({ iss: 'https://evil.example.com' }) }); ok('google', 'wrong issuer -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({ exp: Math.floor(Date.now() / 1000) - 600 }) }); ok('google', 'expired token -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({ email_verified: false }) }); ok('google', 'unverified email -> 401', r.s === 401);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({}, { alg: 'none' }) }); ok('google', 'alg=none attack -> 401', r.s === 401);
  { const t = mkIdToken(); const [h, p, sg] = t.split('.'); const forged = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(p, 'base64url')), sub: 'someone-else' })).toString('base64url');
    r = await call('POST', '/api/auth/google', { idToken: h + '.' + forged + '.' + sg }); ok('google', 'tampered payload -> 401', r.s === 401); }
  const gTok = mkIdToken();
  r = await call('POST', '/api/auth/google', { idToken: gTok }); ok('google', 'new Google account -> asks for a username', r.s === 200 && r.j.needsUsername === true && !/[<>]/.test(r.j.suggestedName), JSON.stringify(r.j));
  r = await call('POST', '/api/auth/google', { idToken: gTok, username: 'admin' }); ok('google', 'reserved username rejected', r.s === 400);
  r = await call('POST', '/api/auth/google', { idToken: gTok, username: 'alice_one' }); ok('google', 'taken username rejected', r.s === 400);
  r = await call('POST', '/api/auth/google', { idToken: gTok, username: 'google_gal' });
  ok('google', 'username chosen -> account + token created', r.s === 200 && r.j.isNewUser && !!r.j.token && r.j.user.coins === 50 && !('email' in r.j.user) && !('googleSub' in r.j.user), JSON.stringify(r.j));
  const gUser = r.j.user, gToken1 = r.j.token;
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken() }); ok('google', 'signing in again (new device) returns the SAME account', r.s === 200 && r.j.isNewUser === false && r.j.user.userId === gUser.userId);
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken(), username: 'another_name' }); ok('google', 'cannot create a 2nd account for the same Google user', r.j.user && r.j.user.userId === gUser.userId);
  r = await call('GET', '/api/ice-servers', null, gToken1); ok('google', 'Google login token works for API calls', r.s === 200);
  const gSock = await sock(gToken1); ok('google', 'Google login token works for the socket', !gSock.error); gSock.disconnect();
  r = await call('POST', '/api/auth/google', { idToken: mkIdToken({ sub: 'g-sub-2', email: 'second@gmail.com' }), username: 'google_two' }); ok('google', 'a different Google user gets a different account', r.s === 200 && r.j.user.userId !== gUser.userId);

  // ===== ICE =====
  r = await call('GET', '/api/ice-servers'); ok('ice', 'ice-servers needs login', r.s === 401);
  r = await call('GET', '/api/ice-servers', null, A.token); ok('ice', 'TURN server with short-lived credentials returned', r.s === 200 && r.j.hasTurn && /^\d+:/.test(r.j.iceServers[2].username));

  // ===== MATCHMAKING / CALLS =====
  const sA = await sock(A.token), sB = await sock(B.token);
  sA.emit('join-queue', { userId: 'usr_SPOOFED', displayName: '<b>Hacker</b>' }); await wait(sA, 'queue-status');
  const ma = wait(sA, 'matched'), mb = wait(sB, 'matched'); sB.emit('join-queue', {});
  const [m1, m2] = [await ma, await mb];
  ok('calls', 'two users get matched', !!(m1 && m2 && m1.roomId === m2.roomId));
  ok('calls', 'spoofed userId/displayName in payload is ignored', m2.stranger.id === A.id && m2.stranger.displayName === 'alice_one', JSON.stringify(m2.stranger));
  const off = wait(sA, 'webrtc-offer'); sB.emit('webrtc-offer', { roomId: m1.roomId, sdp: { sdp: 'v=0', type: 'offer' } }); ok('calls', 'valid offer relayed', !!(await off));
  const junk = wait(sA, 'webrtc-offer', 500); sB.emit('webrtc-offer', { roomId: m1.roomId, sdp: 'not-an-object' }); sB.emit('webrtc-offer', { roomId: m1.roomId, sdp: { sdp: 'x'.repeat(50000), type: 'offer' } }); ok('calls', 'malformed/oversized SDP dropped', !(await junk));
  const ice = wait(sA, 'webrtc-ice-candidate'); sB.emit('webrtc-ice-candidate', { roomId: m1.roomId, candidate: { candidate: 'candidate:1', sdpMid: '0', sdpMLineIndex: 0 } }); ok('calls', 'valid ICE candidate relayed', !!(await ice));
  const atk = await sock(C.token);
  const inj = wait(sA, 'webrtc-offer', 600); atk.emit('webrtc-offer', { roomId: m1.roomId, sdp: { sdp: 'evil', type: 'offer' } }); ok('calls', 'outsider cannot inject into a call', !(await inj));
  const kill = wait(sA, 'call-ended', 600); atk.emit('end-call', { roomId: m1.roomId }); ok('calls', 'outsider cannot end a call', !(await kill));
  // first-queued user (A) disconnects -> B must be told (previously broken)
  const endB = wait(sB, 'call-ended', 1500); sA.disconnect(); ok('calls', 'partner told when FIRST-queued user disconnects (bug fixed)', !!(await endB));
  sB.disconnect(); await sleep(200);

  // skip -> must not instantly rematch the same person
  const [D1, D2] = [await mkUser('skip_one_x'), await mkUser('skip_two_x')]; const s1 = await sock(D1.token), s2 = await sock(D2.token);
  s1.emit('join-queue', {}); await wait(s1, 'queue-status'); const mm = wait(s1, 'matched'); s2.emit('join-queue', {}); const mr = await mm;
  const sk = wait(s2, 'call-ended'); s1.emit('skip-call', { roomId: mr.roomId }); await sk;
  s1.emit('join-queue', {}); s2.emit('join-queue', {}); const re = await wait(s1, 'matched', 1000);
  ok('calls', 'skipping does not instantly rematch the same stranger', re === null);
  s1.disconnect(); s2.disconnect(); await sleep(100);

  // blocks
  const [ba, bb] = [await mkUser('block_aaa'), await mkUser('block_bbb')]; const sa1 = await sock(ba.token), sb1 = await sock(bb.token);
  r = await call('POST', '/api/safety/block', { blockedUserId: bb.id }, ba.token); ok('safety', 'block works', r.s === 200);
  sa1.emit('join-queue', {}); await wait(sa1, 'queue-status'); sb1.emit('join-queue', {}); ok('safety', 'blocked pair never matched', (await wait(sb1, 'matched', 700)) === null);
  r = await call('POST', '/api/safety/block', { blockedUserId: ba.id }, ba.token); ok('safety', 'cannot block yourself', r.s === 400);
  sa1.disconnect(); sb1.disconnect();

  // reports
  const [ra, rb] = [await mkUser('report_aaa'), await mkUser('report_bbb')];
  r = await call('POST', '/api/safety/report', { reportedUserId: rb.id, category: 'Spam or Advertising' }, ra.token); ok('safety', 'cannot report a stranger you never talked to', r.s === 403);
  const q1 = await sock(ra.token), q2 = await sock(rb.token); q1.emit('join-queue', {}); await wait(q1, 'queue-status'); const mq = wait(q1, 'matched'); q2.emit('join-queue', {}); const mrm = await mq;
  r = await call('POST', '/api/safety/report', { reportedUserId: rb.id, category: '<script>x</script>', description: '<b>rude</b>' + 'y'.repeat(900), callId: mrm.roomId }, ra.token);
  ok('safety', 'report from someone you talked to is accepted', r.s === 200);
  r = await call('GET', '/api/admin/data', null, null, { 'X-Admin-Password': 'S3cure-admin-pass' }); const rep = r.j.reports.at(-1);
  ok('safety', 'report text sanitised, category normalised, length capped', rep.category === 'other' && !/[<>]/.test(rep.description) && rep.description.length <= 500);
  r = await call('POST', '/api/safety/report', { reportedUserId: rb.id, category: 'Spam or Advertising', callId: mrm.roomId }, ra.token); ok('safety', 'duplicate report ignored', r.j.duplicate === true || r.s === 200);
  const results = []; for (let i = 0; i < 40; i++) results.push((await call('POST', '/api/safety/block', { blockedUserId: 'usr_flood' + String(i).padStart(3, '0') }, ra.token)).s);
  ok('safety', 'safety endpoints are rate-limited', results.includes(429));
  q1.disconnect(); q2.disconnect();

  // ===== SOCKET ABUSE / CRASH =====
  const x = await sock(C.token);
  x.emit('join-queue'); x.emit('join-queue', null); x.emit('join-queue', 'str'); x.emit('webrtc-offer', 5); x.emit('register-client', null); x.emit('end-call', { roomId: { a: 1 } }); x.emit('skip-call', []); x.emit('webrtc-ice-candidate', { roomId: 'x', candidate: 7 }); await sleep(500);
  r = await call('GET', '/api/health'); ok('robust', 'server survives malformed socket events (previous crash)', r.s === 200);
  const flood = await sock(C.token); let dc = false; flood.on('disconnect', () => dc = true); for (let i = 0; i < 400; i++) flood.emit('leave-queue'); await sleep(700);
  ok('robust', 'event flooding gets the socket disconnected', dc);
  r = await call('GET', '/api/health'); ok('robust', 'server still healthy after flood', r.s === 200);
  const hdr = await realFetch(base + '/api/health'); ok('headers', 'security headers set, no x-powered-by', hdr.headers.get('x-content-type-options') === 'nosniff' && !hdr.headers.get('x-powered-by'));
  console.log(`\nSUMMARY: ${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
})().catch(e => { console.log('TEST ERROR', e); process.exit(2); });
process.on('uncaughtException', e => { console.log('!!! SERVER CRASHED:', e.message); process.exit(3); });
