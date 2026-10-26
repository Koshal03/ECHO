/**
 * One-time passwords for sign-in: email (SMTP) and phone (SMS).
 *
 *  Email : we generate a 6-digit code and send it through SMTP (nodemailer).
 *  Phone : Twilio Verify sends + checks the SMS code (works with Indian numbers once
 *          your Twilio account is set up for India / DLT).
 *  Dev   : OTP_DEV_LOG=1 prints the code in the server console instead of sending
 *          (ignored when NODE_ENV=production).
 *
 * Codes are never stored in plain text, expire after 10 minutes, allow 5 wrong
 * attempts, and sending is rate limited per address.
 */
const crypto = require('crypto');

const TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const HOUR_MS = 60 * 60 * 1000;

function create({ secret }) {
  const resendMs = Number(process.env.OTP_RESEND_MS) || 45000;
  const maxPerHour = Number(process.env.OTP_MAX_PER_HOUR) || 5;
  const store = new Map(); // "channel:target" -> { hash, expires, attempts, sentAt, sends: [ts] }

  const devLog = () => process.env.OTP_DEV_LOG === '1' && process.env.NODE_ENV !== 'production';
  const smtpReady = () => !!(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);

  // Email can go out through SMTP (Gmail etc.) or an HTTPS email API. Many hosts (Render free,
  // Railway free/hobby) block SMTP ports, so the API providers are the fallback that always works.
  //   MAIL_PROVIDER=smtp | brevo | resend   (default: smtp if configured, else brevo, else resend)
  const apiMailFrom = () => ({ email: process.env.MAIL_FROM_EMAIL, name: process.env.MAIL_FROM_NAME || 'Echo' });
  const brevoReady = () => !!(process.env.BREVO_API_KEY && process.env.MAIL_FROM_EMAIL);
  const resendReady = () => !!(process.env.RESEND_API_KEY && process.env.MAIL_FROM_EMAIL);
  function emailProvider() {
    const forced = (process.env.MAIL_PROVIDER || '').toLowerCase();
    if (forced === 'smtp' || forced === 'brevo' || forced === 'resend') return forced;
    if (smtpReady()) return 'smtp';
    if (brevoReady()) return 'brevo';
    if (resendReady()) return 'resend';
    return 'smtp';
  }
  const emailReady = () => {
    const p = emailProvider();
    return p === 'smtp' ? smtpReady() : p === 'brevo' ? brevoReady() : resendReady();
  };
  const mailParts = (code) => ({
    subject: 'Your Echo verification code',
    text: `Your Echo verification code is ${code}.\nIt expires in 10 minutes. If you did not request it, you can ignore this email.`,
    html: `<div style="font-family:Arial,sans-serif;max-width:420px;margin:auto">` +
      `<h2 style="margin:0 0 12px">Echo</h2><p>Your verification code is</p>` +
      `<p style="font-size:32px;font-weight:700;letter-spacing:6px;margin:8px 0">${code}</p>` +
      `<p style="color:#666">It expires in 10 minutes. If you did not request it, ignore this email.</p></div>`,
  });
  async function postJson(url, headers, body, label) {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...headers },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    if (!r.ok) throw new Error(label + ' HTTP ' + r.status); // never include the API key in errors
  }
  const twilioReady = () => !!(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_VERIFY_SERVICE_SID);

  // ---------- senders (replaceable in tests) ----------
  let transporter = null;
  const senders = {
    async email(to, code) {
      const provider = emailProvider();
      const m = mailParts(code);
      if (provider === 'brevo') {
        const from = apiMailFrom();
        return postJson('https://api.brevo.com/v3/smtp/email', { 'api-key': process.env.BREVO_API_KEY },
          { sender: { name: from.name, email: from.email }, to: [{ email: to }], subject: m.subject, htmlContent: m.html, textContent: m.text }, 'Brevo');
      }
      if (provider === 'resend') {
        const from = apiMailFrom();
        return postJson('https://api.resend.com/emails', { Authorization: 'Bearer ' + process.env.RESEND_API_KEY },
          { from: `${from.name} <${from.email}>`, to: [to], subject: m.subject, html: m.html, text: m.text }, 'Resend');
      }
      if (!transporter) {
        const nodemailer = require('nodemailer');
        const port = Number(process.env.SMTP_PORT) || 587;
        transporter = nodemailer.createTransport({
          host: process.env.SMTP_HOST,
          port,
          secure: process.env.SMTP_SECURE === 'true' || port === 465,
          auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
        });
      }
      await transporter.sendMail({
        from: process.env.SMTP_FROM || process.env.SMTP_USER,
        to,
        subject: m.subject,
        text: m.text,
        html: m.html,
      });
    },
    async phoneStart(to) {
      const r = await fetch(`https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SERVICE_SID}/Verifications`, {
        method: 'POST',
        headers: { Authorization: twilioAuth(), 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ To: to, Channel: 'sms' }).toString(),
      });
      if (!r.ok) throw new Error('Twilio start HTTP ' + r.status);
    },
    async phoneCheck(to, code) {
      const r = await fetch(`https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SERVICE_SID}/VerificationCheck`, {
        method: 'POST',
        headers: { Authorization: twilioAuth(), 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ To: to, Code: code }).toString(),
      });
      if (r.status === 404) return false; // expired / never sent
      if (!r.ok) throw new Error('Twilio check HTTP ' + r.status);
      const j = await r.json();
      return j.status === 'approved';
    },
  };
  const twilioAuth = () =>
    'Basic ' + Buffer.from(`${process.env.TWILIO_ACCOUNT_SID}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');

  // ---------- helpers ----------
  function normalize(channel, target) {
    if (typeof target !== 'string') return { error: 'Invalid address.' };
    if (channel === 'email') {
      const v = target.trim().toLowerCase();
      if (v.length > 100 || !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(v)) return { error: 'Enter a valid email address.' };
      return { value: v };
    }
    if (channel === 'phone') {
      const v = target.replace(/[\s\-()]/g, '');
      if (!/^\+[1-9]\d{7,14}$/.test(v)) return { error: 'Enter your phone number with country code, e.g. +919876543210.' };
      return { value: v };
    }
    return { error: 'Unknown sign-in method.' };
  }

  const hashOf = (key, code) => crypto.createHmac('sha256', secret).update(key + '|' + code).digest('hex');
  const safeEqual = (a, b) => {
    const x = Buffer.from(a); const y = Buffer.from(b);
    return x.length === y.length && crypto.timingSafeEqual(x, y);
  };

  // In dev-log mode both channels use our own code and print it.
  const usesOwnCode = (channel) => channel === 'email' || devLog();

  function available(channel) {
    if (devLog()) return true;
    return channel === 'email' ? emailReady() : twilioReady();
  }

  function sweep() {
    const now = Date.now();
    for (const [k, v] of store) if (v.expires < now && now - v.sentAt > HOUR_MS) store.delete(k);
  }
  setInterval(sweep, 10 * 60 * 1000).unref();

  // ---------- public API ----------
  async function request(channel, target) {
    const n = normalize(channel, target);
    if (n.error) return { status: 400, error: n.error };
    if (!available(channel)) {
      return { status: 503, error: channel === 'email' ? 'Email sign-in is not available right now.' : 'Phone sign-in is not available right now.' };
    }
    const key = channel + ':' + n.value;
    const now = Date.now();
    const rec = store.get(key) || { hash: null, expires: 0, attempts: 0, sentAt: 0, sends: [] };
    rec.sends = rec.sends.filter((t) => now - t < HOUR_MS);
    if (now - rec.sentAt < resendMs) {
      return { status: 429, error: 'Please wait before requesting another code.', retryAfter: Math.ceil((resendMs - (now - rec.sentAt)) / 1000) };
    }
    if (rec.sends.length >= maxPerHour) {
      return { status: 429, error: 'Too many codes requested. Try again later.', retryAfter: 3600 };
    }
    try {
      if (usesOwnCode(channel)) {
        const code = String(crypto.randomInt(100000, 1000000));
        if (devLog()) console.log(`[OTP DEV] ${channel} code for ${n.value}: ${code}`);
        else await senders.email(n.value, code);
        rec.hash = hashOf(key, code);
      } else {
        await senders.phoneStart(n.value);
        rec.hash = null; // Twilio holds the code
      }
    } catch (e) {
      console.error(`[OTP] sending ${channel} code failed:`, e.message);
      return { status: 502, error: 'Could not send the code. Please try again.' };
    }
    rec.expires = now + TTL_MS;
    rec.attempts = 0;
    rec.sentAt = now;
    rec.sends.push(now);
    store.set(key, rec);
    return { ok: true, cooldownSeconds: Math.ceil(resendMs / 1000) };
  }

  async function verify(channel, target, code) {
    const n = normalize(channel, target);
    if (n.error) return { status: 400, error: n.error };
    if (typeof code !== 'string' || !/^\d{4,8}$/.test(code)) return { status: 400, error: 'Enter the 6-digit code.' };
    const key = channel + ':' + n.value;
    const rec = store.get(key);
    if (!rec || rec.expires < Date.now()) return { status: 400, error: 'Code expired. Request a new one.' };
    if (rec.attempts >= MAX_ATTEMPTS) { store.delete(key); return { status: 429, error: 'Too many wrong attempts. Request a new code.' }; }
    rec.attempts++;
    let good = false;
    try {
      if (usesOwnCode(channel)) good = rec.hash !== null && safeEqual(rec.hash, hashOf(key, code));
      else good = await senders.phoneCheck(n.value, code);
    } catch (e) {
      console.error(`[OTP] checking ${channel} code failed:`, e.message);
      return { status: 502, error: 'Could not verify the code. Please try again.' };
    }
    if (!good) return { status: 400, error: 'Wrong code.' };
    store.delete(key); // single use
    return { ok: true, value: n.value };
  }

  return { request, verify, normalize, available, setSenders: (s) => Object.assign(senders, s) };
}

module.exports = { create };
