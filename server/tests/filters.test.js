process.env.TERMS_ENFORCE = '0';
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-filters'; process.env.PORT = '3942';
process.env.REMATCH_COOLDOWN_MS = '100';
const { io } = require('socket.io-client');
process.chdir(require('path').join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3942';
const call = (m, p, body, token) => fetch(base + p, {
  method: m,
  headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', (e) => res({ error: e.message })); });
const wait = (s, ev, ms = 600) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(ev, (d) => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[filters] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const mk = async (n) => { const r = await call('POST', '/api/auth/register', { username: n, displayName: n }); return { name: n, token: r.j.token, sock: await sock(r.j.token) }; };
const save = (u, body) => call('POST', '/api/matching/preferences', body, u.token);
const unlock = (u) => call('POST', '/api/matching/unlock-filter', {}, u.token);
const join = (u, mode, extra = {}) => u.sock.emit('join-queue', { mode, ...extra });
const leave = (u) => u.sock.emit('leave-queue');

(async () => {
  await sleep(500);
  const [P, Q, R, P2, Y1, Y2, S, E, F, Z] = await Promise.all(['flt_p', 'flt_q', 'flt_r', 'flt_p2', 'flt_y1', 'flt_y2', 'flt_s', 'flt_e', 'flt_f', 'flt_z'].map(mk));

  // 1) Options + defaults
  let r = await call('GET', '/api/matching/preferences', null, Z.token);
  ok('options listed, cost 20, not unlocked', r.s === 200 && r.j.unlockCost === 20 && r.j.filtersUnlocked === false &&
    r.j.options.languages.some((l) => l.id === 'hi') && r.j.options.interests.length > 0 && r.j.options.regions[0].id === 'any', r);

  // 2) Saving the profile is free and strictly validated
  r = await save(Z, { languages: ['en', 'hi'], interests: ['music'], region: 'IN' });
  ok('profile saved without paying', r.s === 200 && r.j.preferences.languages.length === 2 && r.j.filtersUnlocked === false, r);
  r = await save(Z, { languages: ['klingon'] });
  ok('unknown language -> 400', r.s === 400, r);
  r = await save(Z, { languages: ['en', 'hi', 'es', 'fr', 'ar', 'pt'] });
  ok('more than 5 languages -> 400', r.s === 400, r);
  r = await save(Z, { region: 'ZZ' });
  ok('unknown region -> 400', r.s === 400, r);
  r = await save(Z, { interests: 'music' });
  ok('interests must be a list -> 400', r.s === 400, r);
  const g = await call('POST', '/api/guest/start', { deviceFingerprint: 'dev_filter_guest_1234' });
  r = await save({ token: g.j.token }, { languages: ['en'] });
  ok('guests cannot save preferences', r.s === 403, r);
  r = await unlock({ token: g.j.token });
  ok('guests cannot unlock filters', r.s === 403, r);

  // 3) Unlock: charged once, retry is free
  r = await unlock(Z);
  ok('unlock charges 20 (50 -> 30)', r.s === 200 && r.j.success && r.j.newBalance === 30 && r.j.already === false, r);
  r = await unlock(Z);
  ok('second unlock is free (still 30)', r.s === 200 && r.j.already === true && r.j.newBalance === 30, r);
  r = await call('GET', '/api/matching/preferences', null, Z.token);
  ok('unlock is remembered', r.j.filtersUnlocked === true, r);
  const h = await call('GET', '/api/wallet/transactions?limit=10', null, Z.token);
  ok('wallet history lists "Unlocked advanced filters" -20', h.j.transactions.some((t) => t.title === 'Unlocked advanced filters' && t.delta === -20), h.j);

  // 4) Not enough coins: spend everything on a gift first, then try to unlock
  const mE = wait(E.sock, 'matched'); const mF = wait(F.sock, 'matched');
  join(E, 'text'); join(F, 'text');
  const [me] = await Promise.all([mE, mF]);
  await call('POST', '/api/gifts/send', { roomId: me.roomId, giftId: 'golden_star', requestId: 'req_flt_star_01' }, E.token);
  r = await unlock(E);
  ok('not enough coins -> 402, balance stays 0', r.s === 402 && r.j.balance === 0 && r.j.needed === 20, r);
  E.sock.emit('end-call', { roomId: me.roomId });
  await sleep(300);

  // 5) A filter only applies once it is paid for
  await save(Q, { languages: ['en'] });
  await save(R, { languages: ['hi'] });
  await save(P, { languages: ['hi'] });
  await unlock(P);

  // P (filter: Hindi) waits. Q (English) must NOT be matched with P; R (Hindi) must be.
  let st = wait(P.sock, 'queue-status'); join(P, 'audio');
  let s1 = await st;
  ok('filtered search reports filtered=true', s1 && s1.status === 'searching' && s1.filtered === true, s1);
  let qs = wait(Q.sock, 'queue-status'); let qm = wait(Q.sock, 'matched', 500); join(Q, 'audio');
  ok('English user is NOT matched with a Hindi-only filter', (await qm) === null && (await qs).status === 'searching');
  const mp = wait(P.sock, 'matched'); const mr = wait(R.sock, 'matched'); const qm2 = wait(Q.sock, 'matched', 500);
  join(R, 'audio');
  const [pm, rm] = await Promise.all([mp, mr]);
  ok('Hindi user IS matched with the Hindi filter', pm && rm && pm.stranger.displayName === 'flt_r' && rm.stranger.displayName === 'flt_p', { pm, rm });
  ok('the unmatched English user keeps waiting', (await qm2) === null);

  // 6) "Broaden": ignore my own filter for this search
  await save(P2, { languages: ['hi'] }); await unlock(P2);
  const mp2 = wait(P2.sock, 'matched'); const mq = wait(Q.sock, 'matched');
  join(P2, 'audio', { broaden: true });
  const [p2m, qm3] = await Promise.all([mp2, mq]);
  ok('broaden=true matches an English user too', p2m && qm3 && p2m.stranger.displayName === 'flt_q', { p2m });

  // 7) A filter that was never paid for does nothing (profile alone never blocks anyone)
  const W1 = await mk('flt_w1'); const W2 = await mk('flt_w2');
  await save(W1, { languages: ['hi'] }); await save(W2, { languages: ['en'] });
  const w1m = wait(W1.sock, 'matched'); const w2m = wait(W2.sock, 'matched');
  join(W1, 'audio'); await sleep(100); join(W2, 'audio');
  const [a, b] = await Promise.all([w1m, w2m]);
  ok('without the unlock, languages never restrict matching', a && b, { a, b });

  // 8) Interests rank candidates: Y1 (waits first, no music) vs Y2 (music). Seeker S loves music.
  await save(Y1, { languages: ['es'], interests: ['gaming'] }); await unlock(Y1);
  await save(Y2, { languages: ['fr'], interests: ['music'] }); await unlock(Y2);
  await save(S, { languages: ['es', 'fr'], interests: ['music'] }); await unlock(S);
  join(Y1, 'video'); await sleep(100); join(Y2, 'video'); await sleep(150);
  const sm = wait(S.sock, 'matched');
  join(S, 'video');
  const smatch = await sm;
  ok('interest overlap wins over queue order', smatch && smatch.stranger.displayName === 'flt_y2', smatch);

  // 9) Availability hint
  r = await call('GET', '/api/matching/availability?mode=video', null, Z.token);
  ok('availability returns a count (a hint, no promise)', r.s === 200 && r.j.mode === 'video' && typeof r.j.searching === 'number' && r.j.searching >= 1, r);

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
