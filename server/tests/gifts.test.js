process.env.TERMS_ENFORCE = '0';
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-gifts'; process.env.PORT = '3941';
process.env.REMATCH_COOLDOWN_MS = '100';
const { io } = require('socket.io-client');
process.chdir(require('path').join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3941';
const call = (m, p, body, token) => fetch(base + p, {
  method: m,
  headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', (e) => res({ error: e.message })); });
const wait = (s, ev, ms = 700) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(ev, (d) => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[gifts] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const mk = async (n) => { const r = await call('POST', '/api/auth/register', { username: n, displayName: n }); return { token: r.j.token, sock: await sock(r.j.token) }; };

(async () => {
  await sleep(500);
  const B = await mk('gift_bbb'); const C = await mk('gift_ccc'); const A = await mk('gift_aaa');

  const cat = await call('GET', '/api/gifts', null, B.token);
  ok('catalogue has the 4 server-priced gifts', cat.s === 200 && cat.j.gifts.length === 4 &&
    cat.j.gifts.find((g) => g.id === 'golden_star').price === 50, cat);

  const mB = wait(B.sock, 'matched'); const mC = wait(C.sock, 'matched');
  B.sock.emit('join-queue', { mode: 'video' }); C.sock.emit('join-queue', { mode: 'video' });
  const [b] = await Promise.all([mB, mC]);
  const room = b.roomId;

  // 1) Golden Star: charged once, receiver gets the event
  let got = wait(C.sock, 'gift-received');
  let r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'golden_star', requestId: 'req_star_0001' }, B.token);
  const ev = await got;
  ok('gift accepted and sender charged 50', r.s === 200 && r.j.success && r.j.newBalance === 0, r);
  ok('receiver got gift-received with name + animation', ev && ev.giftId === 'golden_star' && ev.animation === 'burst' && ev.fromName === 'gift_bbb', ev);

  // 2) Retry with the same requestId: never charged or sent twice
  await sleep(1700);
  got = wait(C.sock, 'gift-received', 500);
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'golden_star', requestId: 'req_star_0001' }, B.token);
  ok('retry with same requestId is a duplicate (no second charge)', r.s === 200 && r.j.duplicate === true && r.j.newBalance === 0, r);
  ok('retry sends no second gift event', (await got) === null);

  // 3) Not enough coins
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'req_heart_0002' }, B.token);
  ok('not enough coins -> 402 and balance stays 0', r.s === 402 && r.j.balance === 0 && r.j.needed === 10, r);

  // 4) Client-edited price is ignored
  await sleep(1700);
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'req_heart_0003', price: 1, coinPrice: 1 }, C.token);
  ok('price from the client is ignored (heart costs 10)', r.s === 200 && r.j.newBalance === 40, r);

  // 5) Bad input / outsiders / guests
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'unicorn', requestId: 'req_bad_000004' }, C.token);
  ok('unknown gift -> 400', r.s === 400, r);
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'x' }, C.token);
  ok('invalid requestId -> 400', r.s === 400, r);
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'req_outsider_5' }, A.token);
  ok('someone outside the call cannot send into it', r.s === 409, r);
  const g = await call('POST', '/api/guest/start', { deviceFingerprint: 'dev_gift_guest_1234' });
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'req_guest_0006' }, g.j.token);
  ok('guests cannot send gifts', r.s === 403, r);

  // 6) Wallet history shows the debit
  const h = await call('GET', '/api/wallet/transactions?limit=10', null, C.token);
  ok('wallet history lists "Sent Heart" -10', h.s === 200 && h.j.balance === 40 &&
    h.j.transactions.some((t) => t.title === 'Sent Heart' && t.delta === -10) &&
    h.j.transactions.some((t) => t.title === 'Welcome bonus' && t.delta === 50), h.j);

  // 7) Call ended -> no charge
  B.sock.emit('end-call', { roomId: room });
  await sleep(400);
  await sleep(1700);
  r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'req_ended_0007' }, C.token);
  const me = await call('GET', '/api/me', null, C.token);
  ok('gift after the call ended -> 409 and no coins taken', r.s === 409 && (me.j.user ? me.j.user.coins : me.j.coins) === 40, { r, me: me.j });

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
