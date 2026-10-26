process.env.TERMS_ENFORCE = '0'; // these suites do not test the terms gate
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-otp'; process.env.PORT = '3931';
process.env.OTP_RESEND_MS = '400'; process.env.OTP_MAX_PER_HOUR = '4';
process.env.SMTP_HOST = 'smtp.test'; process.env.SMTP_USER = 'u'; process.env.SMTP_PASS = 'p';
process.env.TWILIO_ACCOUNT_SID = 'AC1'; process.env.TWILIO_AUTH_TOKEN = 't'; process.env.TWILIO_VERIFY_SERVICE_SID = 'VA1';
const { io } = require('socket.io-client');
process.chdir(require('path').join(__dirname, '..'));
const srv = require('../server.js');

let lastEmail = null; const phoneCodes = new Map();
srv.otp.setSenders({
  email: async (to, code) => { lastEmail = { to, code }; },
  phoneStart: async (to) => { phoneCodes.set(to, '654321'); },
  phoneCheck: async (to, code) => phoneCodes.get(to) === code,
});

const base = 'http://127.0.0.1:3931';
const call = (m, p, body) => fetch(base + p, { method: m, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined })
  .then(async (r) => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', (e) => res({ error: e.message })); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[otp] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };

(async () => {
  await sleep(500);
  const req = (channel, target) => call('POST', '/api/auth/otp/request', { channel, target });
  const ver = (channel, target, code) => call('POST', '/api/auth/otp/verify', { channel, target, code });

  // ---- validation
  ok('bad email rejected', (await req('email', 'not-an-email')).s === 400);
  ok('phone without country code rejected', (await req('phone', '9876543210')).s === 400);
  ok('unknown channel rejected', (await req('fax', 'x')).s === 400);

  // ---- email: new account
  let r = await req('email', 'Alice@Example.com');
  ok('email code sent', r.s === 200 && r.j.success && lastEmail && lastEmail.to === 'alice@example.com', r);
  const code1 = lastEmail.code;
  ok('code is 6 digits', /^\d{6}$/.test(code1));
  ok('immediate resend is rate-limited', (await req('email', 'alice@example.com')).s === 429);
  ok('wrong code rejected', (await ver('email', 'alice@example.com', code1 === '000000' ? '111111' : '000000')).s === 400);
  r = await ver('email', 'alice@example.com', code1);
  ok('right code -> needsUsername + ticket', r.s === 200 && r.j.needsUsername && typeof r.j.ticket === 'string', r);
  const ticket = r.j.ticket;
  ok('code is single-use', (await ver('email', 'alice@example.com', code1)).s === 400);
  ok('bad username rejected', (await call('POST', '/api/auth/otp/complete', { ticket, username: 'a b' })).s === 400);
  ok('tampered ticket rejected', (await call('POST', '/api/auth/otp/complete', { ticket: ticket.slice(0, -3) + 'abc', username: 'alice_one' })).s === 400);
  r = await call('POST', '/api/auth/otp/complete', { ticket, username: 'alice_one', displayName: 'Alice' });
  ok('account created from ticket', r.s === 200 && r.j.isNewUser && r.j.token && r.j.user.username === 'alice_one', r);
  ok('email/phone not leaked in public user', r.j.user.email === undefined && r.j.user.phone === undefined && r.j.user.emailVerified === undefined);
  ok('new account has 50 welcome coins', r.j.user.coins === 50);
  const aliceId = r.j.user.userId; const aliceToken = r.j.token;
  const s1 = await sock(aliceToken); ok('token from OTP login works on the socket', !s1.error); s1.close && s1.close();
  const st = await sock(ticket); ok('ticket cannot be used as a login token', !!st.error);

  // ---- email: existing account logs in (case-insensitive)
  await sleep(450);
  await req('email', 'ALICE@example.com');
  r = await ver('email', 'alice@example.com', lastEmail.code);
  ok('second sign-in logs into same account', r.s === 200 && r.j.isNewUser === false && r.j.user.userId === aliceId && r.j.token, r);

  // ---- brute force: 5 wrong guesses burn the code
  await sleep(450);
  await req('email', 'bob@example.com');
  const real = lastEmail.code; const wrong = real === '123456' ? '654321' : '123456';
  for (let i = 0; i < 5; i++) await ver('email', 'bob@example.com', wrong);
  r = await ver('email', 'bob@example.com', real);
  ok('code is locked after 5 wrong attempts', r.s !== 200, r);

  // ---- hourly cap (OTP_MAX_PER_HOUR=4): bob has used 1, alice 2 -> use carol
  let blocked = false;
  for (let i = 0; i < 6; i++) { await sleep(420); const x = await req('email', 'carol@example.com'); if (x.s === 429) { blocked = true; break; } }
  ok('per-address hourly cap enforced', blocked);

  // ---- phone
  r = await req('phone', '+91 98765-43210');
  ok('phone code requested (number normalised)', r.s === 200 && phoneCodes.has('+919876543210'), r);
  ok('wrong phone code rejected', (await ver('phone', '+919876543210', '111111')).s === 400);
  r = await ver('phone', '+919876543210', '654321');
  ok('phone code -> needsUsername', r.s === 200 && r.j.needsUsername, r);
  r = await call('POST', '/api/auth/otp/complete', { ticket: r.j.ticket, username: 'phone_user1' });
  ok('phone account created', r.s === 200 && r.j.isNewUser && r.j.user.username === 'phone_user1', r);
  const phoneId = r.j.user.userId;
  await sleep(450);
  await req('phone', '+919876543210');
  r = await ver('phone', '+919876543210', '654321');
  ok('phone sign-in logs into same account', r.s === 200 && r.j.isNewUser === false && r.j.user.userId === phoneId, r);

  // ---- email and phone are separate identities; unverified /register email is NOT an identity
  const reg = await call('POST', '/api/auth/register', { username: 'mallory1', email: 'victim@example.com' });
  await sleep(450);
  await req('email', 'victim@example.com');
  r = await ver('email', 'victim@example.com', lastEmail.code);
  ok('unverified email on /register cannot capture a real owner', r.s === 200 && r.j.needsUsername === true, r);

  // ---- provider not configured
  const saved = process.env.SMTP_HOST; delete process.env.SMTP_HOST;
  ok('email sign-in reports 503 when SMTP is not configured', (await req('email', 'zed@example.com')).s === 503);
  process.env.SMTP_HOST = saved;

  console.log(`\nOTP SUMMARY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
