# 📱 Google Play Store Publishing Guide for ECHO

This guide walks you step-by-step through packaging, signing, and submitting **Echo – Talk to Strangers** to the Google Play Console to ensure **100% policy compliance** and avoid app rejections.

---

## 🔑 Phase 1: Generate Release Keystore (Sign your App)

Open your terminal and run:

```bash
keytool -genkey -v -keystore echo-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias echo
```
*You will be prompted to enter a password and your organization details. Keep this `.jks` file and passwords safe.*

### Add `key.properties`
Inside `client/android/`:
Create a file named `key.properties` with:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=echo
storeFile=../echo-release-key.jks
```

---

## 📦 Phase 2: Build the Android App Bundle (.aab)

In your VS Code terminal:
```bash
cd client
flutter build appbundle --release
```
The output file will be generated at:
`client/build/app/outputs/bundle/release/app-release.aab`
*This `.aab` file is what you upload directly to the Google Play Console.*

---

## 🛡️ Phase 3: Critical Google Play Policy Requirements

Because **Echo** is a stranger audio chat application, Google Play enforces strict **User Generated Content (UGC)** policies:

### 1. In-App User Reporting and Blocking (Already Built-in ✅)
- Google requires users to be able to immediately block and report offensive users. Echo provides this directly on the active call screen (`ReportBlockDialog`).
- Google requires a 24-hour moderation workflow. Echo provides the Web Moderation Dashboard at `/admin.html`.

### 2. Privacy Policy & Account Deletion URL (Already Built-in ✅)
- Enter your hosted Privacy Policy URL: `https://your-domain.com/privacy_policy.html`
- Google Play strictly requires an **Account Deletion** link. Echo provides both an in-app button in Profile and an account deletion email path in the Privacy Policy.

### 3. Content Rating Questionnaire
When completing the IARC content rating in Play Console:
- *Does the app allow users to interact or exchange content?* -> **YES**
- *Does the app share the user's location?* -> **NO**
- *Does the app allow digital goods purchases?* -> **YES**
- Expected rating: **18+ / Mature** due to open stranger conversations.

### 4. App Access & Reviewer Instructions
In the Play Console under **App access**:
- Provide Google reviewers with a note: *"Reviewers can tap 'Continue as Guest' to immediately access the app without registration."*

---

## 💰 Phase 4: Configure Google Play Billing & In-App Coins

1. In the Google Play Console, go to **Monetize > Products > In-app products**.
2. Create the 3 products matching the blueprint:
   - **Product ID:** `coins_starter_49`
     - Name: Starter Pack (50 Coins)
     - Price: ₹49
   - **Product ID:** `coins_popular_149`
     - Name: Popular Pack (200 Coins)
     - Price: ₹149
   - **Product ID:** `coins_value_299`
     - Name: Value Pack (500 Coins)
     - Price: ₹299
3. Activate all three products.

---

## 📢 Phase 5: Google AdMob Production Setup

1. Create an account at [Google AdMob](https://admob.google.com).
2. Create an App named **Echo (Android)**.
3. Replace the test Application ID in `client/android/app/src/main/AndroidManifest.xml`:
   ```xml
   <meta-data
       android:name="com.google.android.gms.ads.APPLICATION_ID"
       android:value="YOUR_ACTUAL_ADMOB_APP_ID"/>
   ```
4. Replace the test Ad Unit IDs in `client/lib/services/ad_service.dart` with your real Banner, Interstitial, and Rewarded Ad Unit IDs.

---

## 🚀 Phase 6: Submitting to Google Play Closed Testing

1. Go to **Testing > Closed testing** in Google Play Console.
2. Create a new release and upload `app-release.aab`.
3. Add at least 20 testers (Google Play requirement for personal accounts).
4. Run the closed test for 14 days, address any feedback, and apply for **Production** release!
