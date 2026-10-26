/**
 * Supabase persistence layer for ECHO.
 *
 * Design: server.js keeps fast in-memory copies (needed for real-time matchmaking),
 * and every change is written to Supabase. On startup everything is loaded back.
 * Coins are changed ONLY through the add_coins() SQL function (atomic + ledger row).
 *
 * If SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are missing (or DB_DISABLED=1),
 * this module runs in memory-only mode, so local dev and `npm test` still work.
 */
require('dotenv').config();

const disabled = process.env.DB_DISABLED === '1';
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const enabled = !disabled && !!(url && key);

let supabase = null;
if (enabled) {
  const { createClient } = require('@supabase/supabase-js');
  supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
} else if (!disabled) {
  console.warn('[DB] SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set: MEMORY-ONLY mode (data is lost on restart).');
}

// Memory fallbacks (only used when Supabase is not configured)
const memPurchases = new Map();
const memAdTx = new Set();

const ok = ({ data, error }) => {
  if (error) throw new Error(error.message);
  return data;
};
const ms = (t) => new Date(t).getTime();

// Supabase returns max 1000 rows per request, so read in pages.
async function fetchAll(table, build = (q) => q, pageSize = 1000, maxRows = 100000) {
  const rows = [];
  for (let from = 0; from < maxRows; from += pageSize) {
    const q = build(supabase.from(table).select('*')).range(from, from + pageSize - 1);
    const page = ok(await q);
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}

// ---------- Startup load ----------
async function loadAll() {
  if (!enabled) return { users: [], guests: [], blocks: [], reports: [], ledger: [] };

  const users = (await fetchAll('users')).map((r) => ({
    userId: r.user_id, username: r.username, normalizedUsername: r.username_norm,
    displayName: r.display_name, email: r.email || '', googleSub: r.google_sub || null,
    avatarUrl: r.avatar_url || '', phone: r.phone || null, emailVerified: !!r.email_verified, coins: r.coins, createdAt: ms(r.created_at),
    isGuest: false, status: r.status, termsVersion: r.terms_version || '',
  }));

  const guests = (await fetchAll('guest_sessions')).map((r) => ({
    sessionId: r.session_id, deviceId: r.device_id, displayName: r.display_name,
    createdAt: ms(r.created_at), expiresAt: ms(r.expires_at), isGuest: true,
  }));

  const blocks = (await fetchAll('blocks')).map((r) => ({ blockerId: r.blocker_id, blockedId: r.blocked_id }));

  // newest 5000 reports (oldest first, like the in-memory queue)
  const rep = ok(await supabase.from('reports').select('*').order('created_at', { ascending: false }).limit(5000));
  const reports = rep.reverse().map((r) => ({
    reportId: r.report_id, reporterId: r.reporter_id, reportedUserId: r.reported_user_id,
    category: r.category, description: r.description || '', callId: r.call_id || null,
    status: r.status, createdAt: ms(r.created_at),
  }));

  const led = ok(await supabase.from('wallet_ledger').select('*').order('created_at', { ascending: false }).limit(200));
  const ledger = led.reverse().map((r) => ({
    transactionId: r.transaction_id, userId: r.user_id, entryType: r.entry_type, coinDelta: r.coin_delta,
    source: r.source, productId: r.product_id || undefined, reference: r.reference || null, timestamp: ms(r.created_at),
  }));

  return { users, guests, blocks, reports, ledger };
}

// ---------- Users ----------
async function insertUser(u, welcomeLedgerId) {
  if (!enabled) return;
  ok(await supabase.from('users').insert({
    user_id: u.userId, username: u.username, username_norm: u.normalizedUsername,
    display_name: u.displayName, email: u.email || '', google_sub: u.googleSub || null, phone: u.phone || null, email_verified: !!u.emailVerified,
    avatar_url: u.avatarUrl, coins: u.coins, status: u.status, created_at: new Date(u.createdAt).toISOString(),
  }));
  ok(await supabase.from('wallet_ledger').insert({
    transaction_id: welcomeLedgerId, user_id: u.userId, entry_type: 'credit',
    coin_delta: u.coins, source: 'welcome_bonus',
  }));
}

// ---------- Coins: atomic, returns the new balance ----------
async function addCoins(userId, delta, source, productId = null, reference = null) {
  if (!enabled) return null; // caller falls back to memory
  return ok(await supabase.rpc('add_coins', {
    p_user_id: userId, p_delta: delta, p_source: source, p_product_id: productId, p_reference: reference,
  }));
}

// ---------- Account deletion / moderation ----------
const safeId = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{3,64}$/.test(v);

// Removes the person's data. Purchase tokens and ledger rows stay (they hold no personal
// data once the users row is gone) so a deleted account can never replay an old purchase.
async function deleteUser(userId) {
  if (!enabled) return;
  if (!safeId(userId)) throw new Error('bad user id');
  ok(await supabase.from('blocks').delete().or(`blocker_id.eq.${userId},blocked_id.eq.${userId}`));
  ok(await supabase.from('users').delete().eq('user_id', userId));
}

async function setTermsAccepted(userId, version) {
  if (!enabled) return;
  ok(await supabase.from('users').update({ terms_version: version, terms_accepted_at: new Date().toISOString() }).eq('user_id', userId));
}

async function setUserStatus(userId, status) {
  if (!enabled) return;
  ok(await supabase.from('users').update({ status }).eq('user_id', userId));
}

async function updateReportStatus(reportId, status) {
  if (!enabled) return;
  ok(await supabase.from('reports').update({ status }).eq('report_id', reportId));
}

// ---------- Guests ----------
async function insertGuest(s) {
  if (!enabled) return;
  ok(await supabase.from('guest_sessions').insert({
    session_id: s.sessionId, device_id: s.deviceId, display_name: s.displayName,
    created_at: new Date(s.createdAt).toISOString(), expires_at: new Date(s.expiresAt).toISOString(),
  }));
}

// ---------- Safety ----------
async function insertBlock(blockerId, blockedId) {
  if (!enabled) return;
  ok(await supabase.from('blocks').upsert({ blocker_id: blockerId, blocked_id: blockedId }));
}

async function insertReport(r) {
  if (!enabled) return;
  ok(await supabase.from('reports').insert({
    report_id: r.reportId, reporter_id: r.reporterId, reported_user_id: r.reportedUserId,
    category: r.category, description: r.description, call_id: r.callId, status: r.status,
  }));
}

// ---------- Google Play purchases ----------
// Returns true if this call "owns" the token, false if it already existed.
async function claimPurchase(token, userId, productId) {
  if (!enabled) {
    if (memPurchases.has(token)) return false;
    memPurchases.set(token, { purchase_token: token, user_id: userId, product_id: productId, state: 'pending' });
    return true;
  }
  const { error } = await supabase.from('purchases').insert({ purchase_token: token, user_id: userId, product_id: productId });
  if (!error) return true;
  if (error.code === '23505') return false; // unique violation = already exists
  throw new Error(error.message);
}
async function getPurchase(token) {
  if (!enabled) return memPurchases.get(token) || null;
  return ok(await supabase.from('purchases').select('*').eq('purchase_token', token).maybeSingle());
}
async function markPurchaseCredited(token) {
  if (!enabled) { const p = memPurchases.get(token); if (p) p.state = 'credited'; return; }
  ok(await supabase.from('purchases').update({ state: 'credited' }).eq('purchase_token', token));
}
async function deletePurchase(token) {
  if (!enabled) { memPurchases.delete(token); return; }
  ok(await supabase.from('purchases').delete().eq('purchase_token', token));
}

// ---------- AdMob rewarded-ad transactions ----------
async function adTxExists(txId) {
  if (!enabled) return memAdTx.has(txId);
  const { count, error } = await supabase.from('ad_rewards').select('transaction_id', { count: 'exact', head: true }).eq('transaction_id', txId);
  if (error) throw new Error(error.message);
  return count > 0;
}
async function claimAdTx(txId, userId) {
  if (!enabled) { if (memAdTx.has(txId)) return false; memAdTx.add(txId); return true; }
  const { error } = await supabase.from('ad_rewards').insert({ transaction_id: txId, user_id: userId });
  if (!error) return true;
  if (error.code === '23505') return false;
  throw new Error(error.message);
}


// ---------- Virtual gifts + wallet history ----------
async function loadGiftCatalog() {
  if (!enabled) return null;
  const rows = ok(await supabase.from('gift_catalog').select('*').eq('enabled', true).order('sort_order'));
  return rows.map((g) => ({ id: g.gift_id, name: g.name, price: g.coin_price, animation: g.animation_key, popular: !!g.popular }));
}

// Atomic: price check + balance check + debit + ledger + gift event. Idempotent per requestId.
// Throws Error('insufficient_coins' | 'gift_unavailable' | 'price_mismatch') on business failures.
async function sendGift({ senderId, recipientId, callId, giftId, price, requestId }) {
  if (!enabled) return null; // caller falls back to memory
  const out = ok(await supabase.rpc('send_gift', {
    p_sender: senderId, p_recipient: recipientId, p_call_id: callId, p_gift_id: giftId, p_price: price, p_request_id: requestId,
  }));
  return { duplicate: !!out.duplicate, giftEventId: out.gift_event_id, newBalance: out.new_balance, price: out.coin_price };
}

async function getLedger(userId, limit = 30) {
  if (!enabled) return null;
  const rows = ok(await supabase.from('wallet_ledger')
    .select('transaction_id, coin_delta, source, product_id, created_at')
    .eq('user_id', userId).order('created_at', { ascending: false }).limit(limit));
  return rows.map((r) => ({ id: r.transaction_id, delta: r.coin_delta, source: r.source, productId: r.product_id, createdAt: ms(r.created_at) }));
}

module.exports = {
  enabled, supabase, loadAll, insertUser, addCoins, insertGuest, insertBlock, insertReport,
  claimPurchase, getPurchase, markPurchaseCredited, deletePurchase, adTxExists, claimAdTx,
  deleteUser, setUserStatus, updateReportStatus, setTermsAccepted,
  loadGiftCatalog, sendGift, getLedger,
};
