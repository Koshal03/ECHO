process.env.TERMS_ENFORCE = '0';
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-admin-gifts'; process.env.PORT = '3942';
process.env.ADMIN_PASSWORD = 'adminpw-test';
process.env.GIFT_ALERT_COUNT = '3';          // 3 gifts in 10 minutes raises the alert
process.env.GIFT_SPEND_ALERT_COINS = '25';   // 25+ coins in 24h raises the alert
process.env.ADMIN_ADJUST_ALERT_COINS = '500';
process.env.ADMIN_REPORT_CACHE_MS = '0';       // no caching in the test
const { io } = require('socket.io-client');
process.chdir(require('path').join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3942';
const call = (m, p, body, token, admin) => fetch(base + p, {
  method: m,
  headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(admin ? { 'X-Admin-Password': admin } : {}) },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); });
const wait = (s, ev, ms = 800) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(ev, (d) => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[admin-gifts] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const mk = async (n) => { const r = await call('POST', '/api/auth/register', { username: n, displayName: n }); return { token: r.j.token, sock: await sock(r.j.token) }; };

(async () => {
  await sleep(500);
  const ADMIN = 'adminpw-test';

  // report needs the admin password
  let r = await call('GET', '/api/admin/gifts');
  ok('no password -> 401', r.s === 401, r);
  r = await call('GET', '/api/admin/gifts', null, null, 'wrong');
  ok('wrong password -> 401', r.s === 401, r);

  // empty report first
  r = await call('GET', '/api/admin/gifts', null, null, ADMIN);
  ok('empty report is all zeros with no alerts', r.s === 200 && r.j.summary.gifts24h === 0 && r.j.alerts.length === 0 && r.j.recent.length === 0, r);

  const B = await mk('adm_bbb'); const C = await mk('adm_ccc');
  const mB = wait(B.sock, 'matched'); const mC = wait(C.sock, 'matched');
  B.sock.emit('join-queue', { mode: 'video' }); C.sock.emit('join-queue', { mode: 'video' });
  const [b] = await Promise.all([mB, mC]);
  const room = b.roomId;

  // admin gives B coins, then B sends 3 hearts
  r = await call('POST', '/api/admin/gift-coins', { userId: 'adm_bbb', amount: 600 }, null, ADMIN);
  ok('admin can add coins (test setup)', r.s === 200, r);
  for (let i = 1; i <= 3; i++) {
    r = await call('POST', '/api/gifts/send', { roomId: room, giftId: 'heart', requestId: 'req_admin_000' + i }, B.token);
    if (r.s !== 200) break;
    await sleep(1700);
  }
  ok('three gifts went through', r.s === 200, r);

  r = await call('GET', '/api/admin/gifts', null, null, ADMIN);
  const g = r.j;
  ok('summary counts 3 gifts / 30 coins / 1 sender', g.summary.gifts24h === 3 && g.summary.coins24h === 30 && g.summary.senders24h === 1, g.summary);
  ok('top sender is adm_bbb with 30 coins', g.topSenders[0] && g.topSenders[0].name === 'adm_bbb' && g.topSenders[0].coins === 30, g.topSenders);
  ok('recent list names sender, receiver and gift', g.recent.length === 3 && g.recent[0].from === 'adm_bbb' && g.recent[0].to === 'adm_ccc' && g.recent[0].gift === 'Heart' && g.recent[0].coins === 10, g.recent);
  ok('velocity alert (3 gifts in 10 minutes)', g.alerts.some((a) => a.title === 'Unusual gift activity' && a.detail.includes('adm_bbb')), g.alerts);
  ok('spending alert (30 coins >= 25)', g.alerts.some((a) => a.title === 'High gift spending'), g.alerts);
  ok('large admin coin change shows as a note (+600 >= 500)', g.alerts.some((a) => a.title === 'Large admin coin change' && a.level === 'info'), g.alerts);
  ok('filter unlocks are 0 and listed as empty', g.summary.filterUnlocks24h === 0 && g.unlocks.length === 0, g.unlocks);
  ok('the report never includes passwords or tokens', !JSON.stringify(g).includes('adminpw') && !JSON.stringify(g).includes(B.token), null);

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
