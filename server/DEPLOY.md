# Echo server: online kaise lagayein (DEPLOY.md)

Server ab taiyaar hai. Aap ko sirf neeche ki **details bharni** hain. Code mein kuch badalna nahi hai.

## 1. Server ko kya chahiye

| Cheez | Kya hai | Kahan se |
|---|---|---|
| Hosting | Node server chalane ki jagah | Render ya Railway (Netlify nahi chalega) |
| Database | Users, coins, reports | Supabase (aapka project pehle se hai) |
| Email | OTP code bhejna | Gmail SMTP ya email API (Brevo / Resend) |
| TURN (baad mein) | Alag networks par calls ke liye | coturn VPS ya hosted TURN |

## 2. Fill-in checklist (jo aap bharoge)

`.env.example` mein har variable ka comment hai. Hosting par ye "Environment" page mein jaate hain.

| Variable | Kahan se milega | Kab zaroori |
|---|---|---|
| `SUPABASE_URL` | Supabase > Project Settings > API | Pehle din |
| `SUPABASE_SERVICE_ROLE_KEY` | Wahi page, **Secret key** (`sb_secret_...`). Chat mein bheji purani key revoke karke nayi lo | Pehle din |
| `SERVER_SECRET` | `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` | Pehle din |
| `ADMIN_PASSWORD` | Aap khud mazboot password chuno | Pehle din |
| `NODE_ENV` | `production` | Pehle din |
| Email: `SMTP_*` **ya** `BREVO_API_KEY` / `RESEND_API_KEY` + `MAIL_FROM_EMAIL` | Gmail App password, ya Brevo / Resend dashboard | Email login chalane ke liye |
| `GOOGLE_CLIENT_IDS` | Google Cloud Console > Credentials > **Web** client ID | Google Sign-In ke liye |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Google Cloud service account ki JSON key (poora text) | Coin pack purchase ke liye |
| `ADMOB_REWARDED_AD_UNIT` | AdMob (abhi `8634399335` bhara hai) | Rewarded ads ke liye |
| `TURN_URLS`, `TURN_SECRET` | Apna coturn (`deploy/turnserver.conf`) ya hosted TURN | Asli users se pehle |

## 3. Supabase (ek baar)

SQL Editor mein ye chalao (agar pehle nahi chalaye):
1. `supabase_schema.sql` (agar naya project hai)
2. `supabase_migration_otp.sql` (email login aur account deletion ke liye zaroori)

## 4. Render par (meri salah)

Free plan mein server so jata hai aur email (SMTP) band hota hai, isliye **paid (Starter)** lo.

1. Project GitHub par daalo (`.gitignore` pehle se `.env` ko rok deta hai).
2. Render > **New > Blueprint** > apna repo chuno. Repo mein `render.yaml` root par hai.
3. "sync: false" wale variables ki values bharo (upar ka checklist).
4. Deploy. Phir `https://aapka-service.onrender.com/api/health` kholo: `{"status":"online"}` dikhna chahiye.

Agar sirf `server` folder upload kar rahe ho to `render.yaml` se `rootDir: server` wali line hata do.

## 5. Railway par (alternative)

Railway Free / Trial / Hobby par **SMTP band** hai, to ya Pro lo ya email API (Brevo / Resend) use karo.
1. New Project > GitHub repo. **Root Directory** = `server`.
2. Variables mein checklist bharo. `railway.json` pehle se hai (start command aur health check).
3. Settings > Networking > **Generate Domain**.

## 6. Email: kaun sa raasta

| Raasta | Kab | Dhyan |
|---|---|---|
| Gmail SMTP | Laptop par ya paid hosting par | App password chahiye, roz lagbhag 500 mail |
| Brevo API | Free hosting par bhi chalta hai | Sender address verify karna padta hai |
| Resend API | Free hosting par bhi chalta hai | Apna domain verify karna padta hai |

Server khud chunta hai: SMTP bhara ho to SMTP, warna Brevo, warna Resend. Zabardasti ke liye `MAIL_PROVIDER=smtp|brevo|resend`.

## 7. App ko server se jodna

Server ka https address milne par app ka build:
```
flutter build appbundle --release --dart-define=BACKEND_URL=https://aapka-server.com
```
Test ke liye APK: `flutter build apk --debug --dart-define=BACKEND_URL=https://aapka-server.com`

## 8. Admin page

`https://aapka-server.com/admin.html` kholo, `ADMIN_PASSWORD` daalo. Wahan se: reports (Resolve / Dismiss / Suspend), live calls (End), members (Suspend, coins), broadcast message.
Password sirf us browser tab mein rehta hai, page ke code mein nahi.

## 9. Deploy ke baad jaanch

1. `/api/health` chalta hai.
2. App mein Email se login: code aata hai.
3. Supabase Table Editor mein `users` mein naya user dikhe.
4. Server redeploy karo, phir login: user bacha rehna chahiye.
5. Do phones se call (alag networks par), TURN lagne ke baad.

## 10. Aam dikkatein

| Dikkat | Wajah / Hal |
|---|---|
| Server start hote hi band | `NODE_ENV=production` hai par `SERVER_SECRET` khaali. Bharo. |
| `[DB] Could not load data` | `SUPABASE_URL` ya key galat, ya SQL nahi chali. |
| Email nahi aata | Gmail App password galat; ya hosting SMTP block kar rahi hai (API provider lo). Logs mein `[OTP] sending email code failed` dekho. |
| Sab users ko "Too many requests" | Proxy ke peeche `TRUST_PROXY` nahi laga. Render / Railway par apne aap lagta hai, doosre host par `TRUST_PROXY=1`. |
| Alag network par call connect nahi | TURN nahi laga. |
| Free Supabase pause | Kuch din inactive rehne par. Dashboard se resume karo, ya paid plan. |

## 11. Terms and Conditions

- Nayi file: `public/terms_and_conditions.html` (web par `https://aapka-server.com/terms_and_conditions.html`). Purana `terms_of_service.html` ab isi par bhej deta hai.
- App mein sign-up / login ke baad Home par pehle Terms screen aati hai. User tick karke **Accept** kare tabhi app khulti hai. Server bhi rokta hai: accept kiye bina match, coin purchase aur reward ad nahi chalte.
- Kisne kaunsa version accept kiya, `users.terms_version` aur `users.terms_accepted_at` mein likha rehta hai (migration `supabase_migration_otp.sql` zaroor chalao).
- Terms badalne par: `public/terms_and_conditions.html`, `client/lib/constants/terms_text.dart` aur server ka `TERMS_VERSION` **teeno** badlo (version same rakho). Phir sab users se dobara accept karwaya jata hai.
- Play Store listing mein is page ka link do. Terms ek vakeel ko zaroor dikhao (company ka naam, governing law, contact emails sahi karwao).

## 12. Zaroori baatein

- Server **sirf ek instance** par chalana (call queue memory mein hai).
- Account delete karne par user ka data (email, naam, blocks) hat jata hai. Coin aur purchase ke records bina naam ke rehte hain, taaki purani purchase dobara use na ho sake. Ye baat Privacy Policy mein likhni chahiye.
- Reports delete nahi hote (safety record).
