# 🎙️ ECHO – Random Audio & Video Stranger Calling Platform

Complete production implementation matching your exact specifications:
- **Android App**: Native Android written in **Kotlin with Jetpack Compose** (with WebRTC live audio & video, AdMob, Google Play Billing, and Phone OTP auth).
- **Backend Server**: **Python Flask** server with WebSockets, serving the **Interactive Web App Client** and the **Protected Master Admin Dashboard**.

---

## ⚡ System Architecture

```
GOOGLEANTYGRAVITY/
│
├── 🐍 server/                     # Python Flask + Socket.IO Backend
│   ├── app.py                     # Matchmaking queues, 60-min guest timer, WebRTC signalling, OTP gateway
│   ├── requirements.txt           # Python dependencies (Flask, SocketIO, CORS)
│   └── public/
│       ├── web_app.html           # Full Interactive Browser Web Client (Live Audio & Video)
│       ├── admin.html             # Master Admin Moderation Suite (Password: admin123)
│       ├── privacy_policy.html    # Play Store required Privacy Policy
│       └── terms_of_service.html  # Play Store required Terms of Service
│
├── 🤖 android_compose/            # Native Android App (Kotlin + Jetpack Compose)
│   ├── app/
│   │   ├── build.gradle.kts       # WebRTC, Socket.IO, AdMob, Billing dependencies
│   │   └── src/main/
│   │       ├── AndroidManifest.xml # Camera, Mic, Bluetooth, Billing permissions
│   │       └── java/com/koshal/echotalk/
│   │           ├── MainActivity.kt # Compose navigation & runtime permissions
│   │           ├── data/model/     # User, GuestSession, CallSession, CoinPack models
│   │           ├── network/        # Retrofit API & SocketSignalingManager
│   │           ├── webrtc/         # WebRtcCallEngine (STUN/TURN, audio/video capture)
│   │           ├── viewmodel/      # EchoViewModel (guest timers, matchmaking, coins)
│   │           └── ui/screens/     # HomeScreen, CallScreen, AuthScreens, CoinStoreScreen
│   └── build.gradle.kts
│
├── 📱 client/                     # Cross-platform Flutter client alternative
├── 📄 PLAYSTORE_PUBLISH_GUIDE.md  # Step-by-step Google Play release manual
└── 📄 README.md
```

---

## 🚀 How to Run in VS Code

### 1. Start the Flask Backend Server & Web App:
Open a terminal in VS Code:
```bash
cd server
pip install -r requirements.txt
python app.py
```
* **Server runs at:** `http://localhost:5000`
* **Interactive Web Client:** Open `http://localhost:5000/` in your browser to test live audio & video calling right between two browser tabs or between phone and browser!
* **Admin Moderation Console:** Open `http://localhost:5000/admin` *(Default password: `admin123`)*

---

### 2. Admin Console Capabilities (Password: `admin123`)
* **Real-time Overview:** Live counts of online sockets, active calls, registered accounts, and open reports.
* **Live Monitor:** View everyone online, who is searching in queues, and all active calls in real time. **Kill any call** with one click.
* **Instant Broadcast Alert:** Push a live alert banner to all active phones & web clients simultaneously.
* **User Management:** Suspend, restore, kick, or delete users. **Gift coins to any specific user** (triggers an instant celebration pop-up on their screen).
* **Reports Queue:** Review user reports with context (Audio vs Video) and Warn, Suspend, or Dismiss.
* **System Settings & Feature Flags:**
  * Toggle Switches: Guest Access (ON/OFF), Phone Sign-ups (ON/OFF), Audio Calls (ON/OFF), Video Calls (ON/OFF), Maintenance Mode (ON/OFF).
  * Configurable Time Limits: Change the 60-minute guest total limit and 30-minute video limit anytime.
  * Welcome Coins: Adjust initial bonus coins (default 50).
  * Home Screen Banner: Update the global announcement banner in real time.
  * AdMob Placement Toggles: Switch Banner, Interstitial, and Rewarded ads ON or OFF individually.
* **Audit Trail:** Automatic timestamped logs of every action taken by the administrator.

---

## 📱 Features Implemented Exactly to Specification

1. **Guest Mode (Server Enforced)**:
   * 60 minutes of total use + 30 minutes of free video calling tracked by the server.
   * Auto warning and redirect: *"Sign up for a better experience"* notice shown when time expires.
   * Admin can adjust both limits dynamically from the dashboard.
2. **Phone Sign-Up & 6-Digit OTP**:
   * Valid for 5 minutes.
   * 5 wrong attempts allowed max.
   * 30-second resend gap cooldown.
   * Rate limited per phone and per IP address.
   * Unique usernames (case-insensitive normalized check).
   * Password hashing & Google Sign-In backend hook.
3. **Atomic Matchmaking & Calling (Audio + Video)**:
   * Separate queues for Audio and Video.
   * Mutual block-list filtering: blocked users can never rematch.
   * P2P WebRTC audio & video streaming with STUN and TURN relay support for strict firewall networks.
   * Controls: Mute, Camera toggle, Skip stranger, End call.
   * Post-call: Report and Block (persisted in DB).
   * Self-service Account Deletion (Google Play requirement).
4. **Coins & Monetization**:
   * 50 welcome coins default (admin configurable).
   * Pack options: Starter (₹49), Popular (₹149), Value (₹299).
   * Rewarded Video Ads: Grants +10 coins with server verification.
   * Interstitial Ads: Triggered at natural transitions after calls (at most once every 2 minutes frequency cap).
   * No ads during live calls; each ad type toggleable by admin.
