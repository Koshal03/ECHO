// Email delivery providers: SMTP is the default; Brevo / Resend (HTTPS APIs) work on hosts that block SMTP.
process.env.NODE_ENV = 'test';
const path = require('path');
process.chdir(path.join(__dirname, '..'));
const { create } = require('../otp');

let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[mail] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const clean = () => ['MAIL_PROVIDER', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASS', 'BREVO_API_KEY', 'RESEND_API_KEY', 'MAIL_FROM_EMAIL', 'MAIL_FROM_NAME', 'OTP_DEV_LOG']
  .forEach((k) => delete process.env[k]);

const realFetch = global.fetch;
let seen = null; let respond = { ok: true, status: 202 };
global.fetch = async (url, opts) => { seen = { url, opts, body: JSON.parse(opts.body) }; return { ok: respond.ok, status: respond.status, json: async () => ({}) }; };

(async () => {
  // nothing configured
  clean();
  let otp = create({ secret: 's' });
  ok('no email provider configured -> 503', (await otp.request('email', 'a@b.com')).status === 503);
  ok('API key without a sender address is not "ready"', (process.env.BREVO_API_KEY = 'k', (await otp.request('email', 'a@b.com')).status === 503));

  // Brevo
  clean(); process.env.BREVO_API_KEY = 'brevo-secret-key'; process.env.MAIL_FROM_EMAIL = 'noreply@echo.app'; process.env.MAIL_FROM_NAME = 'Echo App';
  otp = create({ secret: 's' }); seen = null;
  let r = await otp.request('email', 'User@Example.com');
  ok('Brevo is chosen automatically and the request succeeds', r.ok === true && seen && seen.url === 'https://api.brevo.com/v3/smtp/email', { r, url: seen && seen.url });
  ok('Brevo gets the key in the api-key header', seen.opts.headers['api-key'] === 'brevo-secret-key');
  ok('Brevo body: sender, recipient (lower-case), subject, 6-digit code', seen.body.sender.email === 'noreply@echo.app' && seen.body.sender.name === 'Echo App'
    && seen.body.to[0].email === 'user@example.com' && /Echo verification code/.test(seen.body.subject) && /\b\d{6}\b/.test(seen.body.textContent), seen.body);
  const code = (seen.body.textContent.match(/\b(\d{6})\b/) || [])[1];
  const v = await otp.verify('email', 'user@example.com', code);
  ok('the code sent through Brevo verifies', v.ok === true, v);

  // Resend
  clean(); process.env.RESEND_API_KEY = 're_secret'; process.env.MAIL_FROM_EMAIL = 'hello@echo.app';
  otp = create({ secret: 's' }); seen = null;
  r = await otp.request('email', 'x@y.com');
  ok('Resend used when it is the only one configured', r.ok === true && seen.url === 'https://api.resend.com/emails', { r, url: seen && seen.url });
  ok('Resend uses a Bearer token and a "Name <email>" sender', seen.opts.headers.Authorization === 'Bearer re_secret' && seen.body.from === 'Echo <hello@echo.app>' && seen.body.to[0] === 'x@y.com', seen.body);

  // explicit choice beats auto
  clean(); process.env.BREVO_API_KEY = 'b'; process.env.RESEND_API_KEY = 'r'; process.env.MAIL_FROM_EMAIL = 'a@b.co'; process.env.MAIL_PROVIDER = 'resend';
  otp = create({ secret: 's' }); seen = null; await otp.request('email', 'q@w.com');
  ok('MAIL_PROVIDER forces the provider', seen && seen.url.includes('resend.com'));

  // failures are clean and never leak the key
  clean(); process.env.BREVO_API_KEY = 'super-secret-brevo'; process.env.MAIL_FROM_EMAIL = 'a@b.co';
  otp = create({ secret: 's' }); respond = { ok: false, status: 401 };
  const logged = []; const origErr = console.error; console.error = (...a) => logged.push(a.join(' '));
  r = await otp.request('email', 'fail@x.com');
  console.error = origErr;
  ok('provider error -> 502 with a friendly message', r.status === 502 && !/super-secret-brevo/.test(JSON.stringify(r)), r);
  ok('the API key is never written to the logs', !logged.join('\n').includes('super-secret-brevo'), logged);
  ok('a failed send does not use up the rate limit', (respond = { ok: true, status: 202 }, (await otp.request('email', 'fail@x.com')).ok === true));

  // SMTP stays the default when it is configured
  clean(); process.env.SMTP_HOST = 'smtp.test'; process.env.SMTP_USER = 'u'; process.env.SMTP_PASS = 'p';
  otp = create({ secret: 's' }); let smtpTo = null; otp.setSenders({ email: async (to) => { smtpTo = to; } });
  r = await otp.request('email', 's@m.tp');
  ok('SMTP configuration still works as before', r.ok === true && smtpTo === 's@m.tp');

  global.fetch = realFetch;
  console.log(`\nMAIL SUMMARY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
