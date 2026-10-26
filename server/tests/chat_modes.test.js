process.env.TERMS_ENFORCE = '0'; // these suites do not test the terms gate
process.env.DB_DISABLED = '1';
process.env.NODE_ENV = 'test';
process.env.SERVER_SECRET = 'test-secret-chat'; process.env.PORT = '3932';
process.env.REMATCH_COOLDOWN_MS = '100';
const { io } = require('socket.io-client');
process.chdir(require('path').join(__dirname, '..'));
require('../server.js');

const base = 'http://127.0.0.1:3932';
const call = (m, p, body) => fetch(base + p, { method: m, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined })
  .then(async (r) => { let j = {}; try { j = await r.json(); } catch (_) {} return { s: r.status, j }; });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sock = (token) => new Promise((res) => { const s = io(base, { transports: ['websocket'], auth: { token }, reconnection: false }); s.on('connect', () => res(s)); s.on('connect_error', (e) => res({ error: e.message })); });
const wait = (s, ev, ms = 700) => new Promise((r) => { const t = setTimeout(() => r(null), ms); s.once(ev, (d) => { clearTimeout(t); r(d === undefined ? true : d); }); });
let pass = 0, fail = 0;
const ok = (name, c, note) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + '[chat/modes] ' + name + (note && !c ? '  -> ' + JSON.stringify(note) : '')); };
const mk = async (n) => { const r = await call('POST', '/api/auth/register', { username: n, displayName: n }); return sock(r.j.token); };

(async () => {
  await sleep(500);
  const [A, B, C, D, E, F] = await Promise.all(['user_aaa', 'user_bbb', 'user_ccc', 'user_ddd', 'user_eee', 'user_fff'].map(mk));

  // audio waiting; a video user must NOT be matched with it
  A.emit('join-queue', { mode: 'audio' }); await wait(A, 'queue-status');
  B.emit('join-queue', { mode: 'video' });
  ok('video user is not matched with audio user', (await wait(B, 'matched', 500)) === null);

  // second video user -> matched as video
  const mB = wait(B, 'matched'); const mC = wait(C, 'matched');
  C.emit('join-queue', { mode: 'video' });
  const [b, c] = await Promise.all([mB, mC]);
  ok('two video users match with mode=video', b && c && b.mode === 'video' && c.mode === 'video', { b, c });
  const room = b.roomId;

  // chat inside a video call
  let got = wait(C, 'chat-message'); B.emit('chat-message', { roomId: room, text: '  hello <3  ' });
  let m = await got; ok('chat message relayed in a video call (trimmed, < > kept as text)', m && m.text === 'hello <3' && typeof m.ts === 'number', m);
  await sleep(300);
  got = wait(C, 'chat-message'); B.emit('chat-message', { roomId: room, text: 'x'.repeat(900) });
  m = await got; ok('long message cut to 500 chars', m && m.text.length === 500, m && m.text.length);
  await sleep(300);
  got = wait(C, 'chat-message', 400); B.emit('chat-message', { roomId: room, text: '   ' });
  ok('empty message ignored', (await got) === null);
  await sleep(300);
  got = wait(C, 'chat-message'); B.emit('chat-message', { roomId: room, text: 'line1\u0000\u0007line2' });
  m = await got; ok('control characters removed', m && !/[\u0000-\u001F]/.test(m.text), m);
  await sleep(300);
  const seen = []; C.on('chat-message', (d) => seen.push(d.text));
  B.emit('chat-message', { roomId: room, text: 'one' }); B.emit('chat-message', { roomId: room, text: 'two' });
  await sleep(400); ok('rapid second message throttled', seen.length === 1 && seen[0] === 'one', seen);
  C.removeAllListeners('chat-message');

  // outsider cannot inject into someone else's room
  got = wait(C, 'chat-message', 400); A.emit('chat-message', { roomId: room, text: 'intruder' });
  ok('outsider cannot post into another room', (await got) === null);
  got = wait(C, 'chat-message', 400); B.emit('chat-message', { roomId: room, text: { $ne: 1 } });
  ok('non-string payload ignored', (await got) === null);

  // video WebRTC signalling still relays
  const off = wait(C, 'webrtc-offer');
  B.emit('webrtc-offer', { roomId: room, sdp: { type: 'offer', sdp: 'v=0\r\nm=video' } });
  ok('video room relays WebRTC offer', !!(await off));

  // old app (no payload) lands in the audio queue and matches the waiting audio user
  const mA = wait(A, 'matched');
  F.emit('join-queue', {});
  const a = await mA; ok('join-queue with no mode defaults to audio', a && a.mode === 'audio', a);

  // text mode
  const mD = wait(D, 'matched'); const mE = wait(E, 'matched');
  D.emit('join-queue', { mode: 'text' }); await sleep(100); E.emit('join-queue', { mode: 'text' });
  const [d, e] = await Promise.all([mD, mE]);
  ok('two text users match with mode=text', d && e && d.mode === 'text' && e.mode === 'text', { d, e });
  got = wait(E, 'chat-message'); D.emit('chat-message', { roomId: d.roomId, text: 'hi stranger' });
  m = await got; ok('text chat message delivered', m && m.text === 'hi stranger', m);
  const noRtc = wait(E, 'webrtc-offer', 400);
  D.emit('webrtc-offer', { roomId: d.roomId, sdp: { type: 'offer', sdp: 'v=0' } });
  ok('text room does not relay WebRTC', (await noRtc) === null);
  const ended = wait(D, 'call-ended'); E.emit('skip-call', { roomId: e.roomId });
  ok('skipping a text chat ends it for the other person', !!(await ended));

  console.log(`\nCHAT/MODES SUMMARY: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
