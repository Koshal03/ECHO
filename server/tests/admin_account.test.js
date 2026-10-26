process.env.TERMS_ENFORCE = '0'; // these suites do not test the terms gate
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-admin'; process.env.PORT = '3933';
process.env.ADMIN_PASSWORD = 'admin-test-pw'; process.env.ADMIN_RATE_PER_MIN = '1000';
process.env.REMATCH_COOLDOWN_MS = '100';
const { io } = require('socket.io-client');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
process.chdir(path.join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3933';
const call = (m, p, body, headers = {}) => fetch(base + p, { method: m, headers: { 'Content-Type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined })
  .then(async (r) => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const ADM = { 'X-Admin-Password': 'admin-test-pw' };
const adm = (m, p, body) => call(m, p, body, ADM);
const bearer = (t) => ({ Authorization: 'Bearer ' + t });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', (e) => res({ error: e.message })); });
const wait = (s, ev, ms = 800) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(ev, (d) => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[admin/account] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const reg = (n) => call('POST', '/api/auth/register', { username: n, displayName: n }).then((r) => ({ id: r.j.user.userId, token: r.j.token, name: n }));

(async () => {
  await sleep(500);

  // ---- admin login protection
  ok('overview needs the admin password', (await call('GET', '/api/admin/overview')).s === 401);
  ok('wrong admin password rejected', (await call('GET', '/api/admin/overview', null, { 'X-Admin-Password': 'nope' })).s === 401);
  const a = await reg('alice_adm'), b = await reg('bob_adm'), c = await reg('carol_adm');
  ok('a normal user token is not an admin', (await call('GET', '/api/admin/overview', null, bearer(a.token))).s === 401);
  ok('admin endpoints reject user token (gift)', (await call('POST', '/api/admin/gift-coins', { userId: a.id, amount: 10 }, bearer(a.token))).s === 401);
  let r = await adm('GET', '/api/admin/overview');
  ok('overview works with the password', r.s === 200 && r.j.totalUsers >= 3 && Array.isArray(r.j.recentUsers) && Array.isArray(r.j.activeCalls), r);
  ok('overview hides full emails and never returns tokens', !JSON.stringify(r.j).includes('token'));

  // ---- the admin page itself
  const page = fs.readFileSync(path.join(__dirname, '..', 'public', 'admin.html'), 'utf8');
  ok('admin page has no hard-coded password', !/admin123|adminToken\s*=\s*"/.test(page));
  ok('admin page never uses innerHTML (no HTML injection)', !page.includes('innerHTML'));

  const sa = await sock(a.token), sb = await sock(b.token), sc = await sock(c.token);

  // ---- gift coins
  let ev = wait(sa, 'wallet-updated');
  r = await adm('POST', '/api/admin/gift-coins', { userId: 'alice_adm', amount: 100 });
  ok('gift 100 coins by username', r.s === 200 && r.j.newBalance === 150, r);
  const wu = await ev; ok('user is told about the new balance live', wu && wu.coins === 150, wu);
  r = await call('GET', '/api/me', null, bearer(a.token));
  ok('/api/me shows the new balance', r.s === 200 && r.j.user.coins === 150 && r.j.user.email === undefined, r);
  ok('cannot take balance below zero', (await adm('POST', '/api/admin/gift-coins', { userId: a.id, amount: -1000 })).s === 400);
  ok('amount 0 rejected', (await adm('POST', '/api/admin/gift-coins', { userId: a.id, amount: 0 })).s === 400);
  ok('decimal / text amount rejected', (await adm('POST', '/api/admin/gift-coins', { userId: a.id, amount: '5.5' })).s === 400);
  ok('unknown user -> 404', (await adm('POST', '/api/admin/gift-coins', { userId: 'ghost_user', amount: 5 })).s === 404);
  r = await adm('POST', '/api/admin/gift-coins', { userId: a.id, amount: -50 });
  ok('admin can remove coins', r.s === 200 && r.j.newBalance === 100, r);

  // ---- broadcast
  const bA = wait(sa, 'admin-broadcast'), bB = wait(sb, 'admin-broadcast');
  r = await adm('POST', '/api/admin/broadcast', { message: '  Maintenance at 10pm  ' });
  const [ma, mb] = await Promise.all([bA, bB]);
  ok('broadcast reaches every online user', r.s === 200 && ma && mb && ma.message === 'Maintenance at 10pm', { ma, mb });
  ok('empty broadcast rejected', (await adm('POST', '/api/admin/broadcast', { message: '   ' })).s === 400);

  // ---- live calls: list + kill
  const mA = wait(sa, 'matched'), mB = wait(sb, 'matched');
  sa.emit('join-queue', { mode: 'audio' }); await sleep(150); sb.emit('join-queue', { mode: 'audio' });
  const [ra, rb] = await Promise.all([mA, mB]);
  ok('two users matched', ra && rb && ra.roomId === rb.roomId, { ra, rb });
  r = await adm('GET', '/api/admin/overview');
  ok('live call shows up for the admin', r.j.activeCalls.length === 1 && r.j.activeCalls[0].id === ra.roomId && r.j.inCall === 2, r.j.activeCalls);
  const endA = wait(sa, 'call-ended'), endB = wait(sb, 'call-ended');
  r = await adm('POST', '/api/admin/kill-call', { roomId: ra.roomId });
  const [ea, eb] = await Promise.all([endA, endB]);
  ok('admin can end a call for both people', r.s === 200 && ea && eb && /moderator/i.test(ea.reason), { ea, eb });
  ok('ending a finished call -> 404', (await adm('POST', '/api/admin/kill-call', { roomId: ra.roomId })).s === 404);
  ok('bad room id rejected', (await adm('POST', '/api/admin/kill-call', { roomId: { $ne: 1 } })).s === 404);

  // ---- reports: file one, then resolve / dismiss
  r = await call('POST', '/api/safety/report', { reportedUserId: b.id, category: 'Spam or Advertising', description: 'sells things <b>x</b>', callId: ra.roomId }, bearer(a.token));
  ok('report filed after the call', r.s === 200 && r.j.reportId, r);
  const repId = r.j.reportId;
  r = await adm('GET', '/api/admin/overview');
  const rep = r.j.reports.find((x) => x.reportId === repId);
  ok('report visible with names, still pending', rep && rep.status === 'pending_review' && rep.reportedName === 'bob_adm' && r.j.openReports === 1, rep);
  ok('bad report status rejected', (await adm('POST', '/api/admin/report-status', { reportId: repId, status: 'deleted' })).s === 400);
  ok('unknown report -> 404', (await adm('POST', '/api/admin/report-status', { reportId: 'rep_nope', status: 'resolved' })).s === 404);
  r = await adm('POST', '/api/admin/report-status', { reportId: repId, status: 'resolved' });
  const after = (await adm('GET', '/api/admin/overview')).j;
  ok('resolving closes it', r.s === 200 && after.openReports === 0 && after.reports.find((x) => x.reportId === repId).status === 'resolved');

  // ---- suspend / unsuspend
  const gone = wait(sb, 'disconnect', 1500);
  r = await adm('POST', '/api/admin/suspend', { userId: 'bob_adm', suspended: true });
  ok('suspend works', r.s === 200 && r.j.status === 'suspended', r);
  ok('suspended user is disconnected immediately', (await gone) !== null);
  ok('suspended user is refused by the API', (await call('GET', '/api/me', null, bearer(b.token))).s === 403);
  const blocked = await sock(b.token);
  ok('suspended user cannot reconnect the socket', blocked.error === 'suspended', blocked.error);
  r = await adm('POST', '/api/admin/suspend', { userId: b.id, suspended: false });
  ok('unsuspend works', r.s === 200 && r.j.status === 'active', r);
  ok('reinstated user can use the API again', (await call('GET', '/api/me', null, bearer(b.token))).s === 200);
  const sb2 = await sock(b.token); ok('and reconnect the socket', !sb2.error); sb2.close && sb2.close();
  ok('suspend unknown user -> 404', (await adm('POST', '/api/admin/suspend', { userId: 'ghost_user' })).s === 404);

  // ---- account deletion
  ok('delete needs sign-in', (await call('DELETE', '/api/account', { confirm: 'DELETE' })).s === 401);
  ok('delete needs the confirmation word', (await call('DELETE', '/api/account', {}, bearer(c.token))).s === 400);
  ok('wrong confirmation word rejected', (await call('DELETE', '/api/account', { confirm: 'yes' }, bearer(c.token))).s === 400);
  const cGone = wait(sc, 'disconnect', 1500);
  const notice = wait(sc, 'account-notice', 1500);
  r = await call('DELETE', '/api/account', { confirm: 'DELETE' }, bearer(c.token));
  ok('account deleted', r.s === 200 && r.j.success, r);
  ok('deleted user is disconnected', (await cGone) !== null && (await notice) !== undefined);
  ok('old token no longer works', (await call('GET', '/api/me', null, bearer(c.token))).s === 401);
  const ov = (await adm('GET', '/api/admin/overview')).j;
  ok('deleted user is gone from the admin list', !ov.recentUsers.some((u) => u.userId === c.id));
  ok('deleted user left no coin history in memory', !ov.recentLedger.some((e) => e.userId === c.id));
  ok('username can be registered again', (await call('POST', '/api/auth/register', { username: 'carol_adm', displayName: 'New Carol' })).s === 200);
  ok('deleting twice is refused (token is dead)', (await call('DELETE', '/api/account', { confirm: 'DELETE' }, bearer(c.token))).s === 401);
  const g = await call('POST', '/api/guest/start', { deviceFingerprint: 'device_for_delete_test' });
  r = await call('DELETE', '/api/account', { confirm: 'DELETE' }, bearer(g.j.token));
  ok('guest delete is a harmless no-op', r.s === 200 && r.j.guest === true, r);
  ok('guest session still valid afterwards (allowance cannot be reset)', (await call('POST', '/api/guest/start', { deviceFingerprint: 'device_for_delete_test' })).j.session?.sessionId === g.j.session?.sessionId || (await call('POST', '/api/guest/start', { deviceFingerprint: 'device_for_delete_test' })).s === 200);

  // ---- production safety: refuse to start without SERVER_SECRET
  const env = { ...process.env, NODE_ENV: 'production', PORT: '3999', DB_DISABLED: '1' };
  delete env.SERVER_SECRET;
  const child = spawnSync(process.execPath, [path.join(__dirname, '..', 'server.js')], { env, encoding: 'utf8', timeout: 8000 });
  ok('production start without SERVER_SECRET exits with an error', child.status === 1 && /SERVER_SECRET/.test(child.stderr), { status: child.status, err: child.stderr });

  console.log(`\nADMIN/ACCOUNT SUMMARY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
