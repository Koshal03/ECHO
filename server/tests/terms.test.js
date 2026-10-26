// Terms and Conditions gate: nobody can use Echo (calls, coins, ads) before accepting the current version.
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-terms'; process.env.PORT = '3935';
process.env.REMATCH_COOLDOWN_MS = '100';
delete process.env.TERMS_ENFORCE; // the gate must be ON (it is the default)
const { io } = require('socket.io-client');
const fs = require('fs');
const path = require('path');
process.chdir(path.join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3935';
const call = (m, p, body, headers = {}) => fetch(base + p, { method: m, headers: { 'Content-Type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined })
  .then(async (r) => { let j = {}; const text = await r.text(); try { j = JSON.parse(text); } catch (_) { j = { _text: text }; } return { s: r.status, j, h: r.headers }; });
const bearer = (t) => ({ Authorization: 'Bearer ' + t });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', (e) => res({ error: e.message })); });
const wait = (s, ev, ms = 700) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(ev, (d) => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[terms] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const reg = (n) => call('POST', '/api/auth/register', { username: n, displayName: n }).then((r) => ({ id: r.j.user.userId, token: r.j.token, user: r.j.user }));
const VERSION = (fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8').match(/TERMS_VERSION \|\| '([^']+)'/) || [])[1];

(async () => {
  await sleep(500);
  const cfg = await call('GET', '/api/config');
  ok('config tells the current terms version', cfg.j.termsVersion === VERSION && VERSION, cfg.j);

  // ---- a new member has not accepted
  const a = await reg('terms_a'), b = await reg('terms_b');
  ok('new member starts with termsAccepted = false', a.user.termsAccepted === false, a.user);
  ok('private fields (termsVersion) never leak', a.user.termsVersion === undefined && a.user.email === undefined);
  const guest = await call('POST', '/api/guest/start', { deviceFingerprint: 'terms_test_device_01' });
  ok('a guest has not accepted either', guest.j.session && guest.j.session.termsAccepted === false, guest.j);

  // ---- before accepting: no matchmaking
  const sa = await sock(a.token), sb = await sock(b.token);
  const blockedA = wait(sa, 'terms-required'), blockedB = wait(sb, 'terms-required');
  sa.emit('join-queue', { mode: 'audio' }); sb.emit('join-queue', { mode: 'audio' });
  const [ta, tb] = await Promise.all([blockedA, blockedB]);
  ok('joining the queue is refused until the terms are accepted', ta && tb && ta.version === VERSION, { ta, tb });
  const noMatch = await Promise.race([wait(sa, 'matched', 600), wait(sb, 'matched', 600)]);
  ok('and nobody gets matched', noMatch === null);

  // ---- before accepting: no purchases / reward ads
  let r = await call('POST', '/api/wallet/purchase', { productId: 'coins_starter_49', purchaseToken: 'tok_' + 'x'.repeat(30) }, bearer(a.token));
  ok('coin purchase is refused before accepting', r.s === 403 && r.j.code === 'terms_required', r);
  r = await call('POST', '/api/ads/reward-nonce', {}, bearer(a.token));
  ok('reward-ad request is refused before accepting', r.s === 403 && r.j.code === 'terms_required', r);

  // ---- accepting
  ok('accept needs a sign-in', (await call('POST', '/api/terms/accept', { version: VERSION })).s === 401);
  r = await call('POST', '/api/terms/accept', { version: '1999-01-01' }, bearer(a.token));
  ok('an old / unknown version is refused (409)', r.s === 409 && r.j.currentVersion === VERSION, r);
  ok('missing version is refused', (await call('POST', '/api/terms/accept', {}, bearer(a.token))).s === 409);
  r = await call('POST', '/api/terms/accept', { version: VERSION }, bearer(a.token));
  ok('member accepts the current version', r.s === 200 && r.j.success && r.j.termsVersion === VERSION, r);
  r = await call('GET', '/api/me', null, bearer(a.token));
  ok('/api/me now shows termsAccepted = true', r.s === 200 && r.j.user.termsAccepted === true, r);
  ok('the other member is still not accepted', (await call('GET', '/api/me', null, bearer(b.token))).j.user.termsAccepted === false);

  // purchase passes the terms check now (it then fails later for other reasons, but never with 403/terms_required)
  r = await call('POST', '/api/wallet/purchase', { productId: 'coins_starter_49', purchaseToken: 'tok_' + 'y'.repeat(30) }, bearer(a.token));
  ok('purchase is no longer blocked by the terms gate', r.j.code !== 'terms_required', r);
  r = await call('POST', '/api/ads/reward-nonce', {}, bearer(a.token));
  ok('reward-ad request is no longer blocked', r.s !== 403 || r.j.code !== 'terms_required', r);

  // ---- matching works once both accepted
  await call('POST', '/api/terms/accept', { version: VERSION }, bearer(b.token));
  const mA = wait(sa, 'matched', 1500), mB = wait(sb, 'matched', 1500);
  sa.emit('join-queue', { mode: 'audio' }); await sleep(150); sb.emit('join-queue', { mode: 'audio' });
  const [ma, mb] = await Promise.all([mA, mB]);
  ok('after both accepted the two users are matched', ma && mb && ma.roomId === mb.roomId, { ma, mb });

  // ---- acceptance survives a reconnect
  sa.close(); await sleep(200);
  const sa2 = await sock(a.token);
  const again = wait(sa2, 'terms-required', 600);
  const qs = wait(sa2, 'queue-status', 600);
  sa2.emit('join-queue', { mode: 'text' });
  ok('acceptance is remembered after reconnecting', (await again) === null);
  const q = await qs;
  ok('and the queue works', q && q.status === 'searching', q);

  // ---- guests
  const gs = await sock(guest.j.token);
  const gBlocked = wait(gs, 'terms-required');
  gs.emit('join-queue', { mode: 'audio' });
  ok('a guest is blocked before accepting', (await gBlocked) !== null);
  r = await call('POST', '/api/terms/accept', { version: VERSION }, bearer(guest.j.token));
  ok('a guest can accept', r.s === 200, r);
  const gAgain = await call('POST', '/api/guest/start', { deviceFingerprint: 'terms_test_device_01' });
  ok('the same guest session is already accepted next time', gAgain.j.session && gAgain.j.session.termsAccepted === true, gAgain.j);
  const gOk = wait(gs, 'queue-status', 800);
  gs.emit('join-queue', { mode: 'audio' });
  const gq = await gOk;
  ok('accepted guest can search', gq && gq.status === 'searching', gq);

  // ---- the pages
  const page = await call('GET', '/terms_and_conditions.html');
  ok('new Terms page is served', page.s === 200 && /Terms and Conditions/.test(page.j._text) && page.j._text.includes(VERSION), page.s);
  ok('Terms page covers the key topics', ['18', 'harass', 'Coins', 'Delete Account', 'Privacy Policy', 'support@echo-strangers.app'].every((w) => page.j._text.includes(w)));
  const old = await call('GET', '/terms_of_service.html');
  ok('old Terms address points to the new page', old.s === 200 && old.j._text.includes('terms_and_conditions.html'), old.j._text);
  const clientFile = path.join(__dirname, '..', '..', 'client', 'lib', 'constants', 'terms_text.dart');
  if (fs.existsSync(clientFile)) {
    const dart = fs.readFileSync(clientFile, 'utf8');
    ok('app and server use the SAME terms version', dart.includes('version = "' + VERSION + '"'), VERSION);
    const sections = (page.j._text.match(/<h2>\d+\./g) || []).length;
    ok('app text has the same number of sections as the web page', (dart.match(/TermsSection\(/g) || []).length - 1 === sections, sections);
  }

  console.log(`\nTERMS SUMMARY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
