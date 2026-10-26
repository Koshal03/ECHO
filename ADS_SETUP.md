# Ads setup (what you must do in AdMob / your build)

1. **AdMob account + app**: add your Android app in AdMob, then create 3 ad units: Banner, Interstitial, Rewarded.
2. **App ID**: already set in `client/android/gradle.properties` -> `admobAppId=ca-app-pub-2996217719964580~5609525602`.
3. **Ad unit IDs**: already set in `client/lib/config/ad_config.dart`.
   Release builds use your live units (echo_banner_home, echo_interstitial_aftercall, echo_rewarded_coins);
   debug builds automatically use Google test units. Just run `flutter build appbundle --release`.
4. **Rewarded SSV**: AdMob > your Rewarded ad unit > Server-side verification > enable, callback URL
   `https://YOUR-DOMAIN/api/ads/ssv` (must be public HTTPS). Use AdMob's "test URL" button to check it.
   Recommended hardening: set env `ADMOB_REWARDED_AD_UNIT=8634399335` on the server so only your rewarded unit can credit coins.
5. **Consent**: AdMob > Privacy & messaging > create the GDPR/UK message (the app already calls the consent form).
6. Server: `pip install -r requirements.txt` (adds `cryptography`) for Flask; Node needs nothing new.
   Legacy free-coin endpoints now return 410 (set ALLOW_INSECURE_REWARD_GRANT=1 only for local demos).
