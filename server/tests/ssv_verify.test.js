const crypto = require('crypto');
const { verifySsvQuery, resetCacheForTests } = require('../ads_ssv.js');
(async () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = publicKey.export({ type: 'spki', format: 'pem' });
  const fetcher = async () => new Map([[4444, pem]]);
  const msg = 'ad_network=5450213213286189855&ad_unit=123&custom_data=nonce_abc&reward_amount=1&reward_item=coin&timestamp=1700000000000&transaction_id=TX1&user_id=user_1';
  const sig = crypto.sign('sha256', Buffer.from(msg), privateKey).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  const good = `${msg}&signature=${sig}&key_id=4444`;
  const p = await verifySsvQuery(good, fetcher);
  if (p.user_id !== 'user_1' || p.transaction_id !== 'TX1') throw new Error('param parse');
  console.log('valid signature accepted ->', p.transaction_id);
  const bads = { 'tampered reward': good.replace('reward_amount=1','reward_amount=999'), 'tampered user': good.replace('user_id=user_1','user_id=user_2'), 'no signature': msg, 'unknown key': good.replace('key_id=4444','key_id=1') };
  for (const [name, q] of Object.entries(bads)) {
    resetCacheForTests();
    try { await verifySsvQuery(q, fetcher); console.log('FAIL accepted:', name); process.exit(1); }
    catch (e) { console.log('rejected', name, '->', e.message); }
  }
  console.log('ALL NODE SSV TESTS PASSED');
})();
