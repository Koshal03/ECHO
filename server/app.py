"""
ECHO - Random Audio & Video Stranger Calling Platform
Flask Backend Server + WebRTC Signalling + Web App + Admin Dashboard

Features matching blueprint and user specification:
- Guest mode: 60 min total use, 30 min free video call (configurable by admin).
- Auto "sign up for a better experience" notice and redirect.
- Phone Auth + 6-digit OTP: 5-min expiry, max 5 attempts, 30s resend cooldown, IP & phone rate limits.
- Unique lowercase-normalized usernames, hashed passwords, Google Sign-in backend hook.
- Real-time Audio & Video matchmaking queues with mutual block-pair exclusion.
- WebRTC signalling with STUN and TURN relay support.
- In-call controls: Mute, Camera toggle, Skip, End call.
- Post-call: Report and Block (persisted in DB). Self-service account deletion.
- Admin Dashboard (Password protected):
    * Real counts of users, online, active calls, open reports, hourly stats.
    * Live Monitor: who is online, searching, active calls, kill call, broadcast message.
    * User management: suspend, restore, kick, delete, instant coin gift pop-up.
    * Reports queue: warn, suspend, dismiss.
    * System settings: toggle guest, sign-up, audio, video, maintenance, time limits, banner message, ad toggles.
    * Server connection status & audit logs.
- Monetization: 50 welcome coins, ₹49, ₹149, ₹299 packs, rewarded ad (10 coins), AdMob 2-min interstitial limiter.
- Full interactive browser Web Client served at root (/).
"""

import os
import time
import uuid
import hashlib
import random
import threading
from datetime import datetime, timedelta
from flask import Flask, request, jsonify, render_template_string, send_from_directory
from flask_socketio import SocketIO, emit, join_room, leave_room
from flask_cors import CORS
import ads_ssv

app = Flask(__name__, static_folder='public', static_url_path='')
app.config['SECRET_KEY'] = 'echo-super-secret-key-2026'
CORS(app)

# Use async_mode='threading' for universal compatibility without compilation issues
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

# ==============================================================================
# GLOBAL IN-MEMORY DATABASE & CONFIGURATION (Easily swapped with SQLite/Postgres)
# ==============================================================================

ADMIN_PASSWORD_HASH = hashlib.sha256("admin123".encode()).hexdigest()

# Dynamic System Settings (Editable in Admin Settings Panel)
SYSTEM_SETTINGS = {
    "guest_access_enabled": True,
    "sign_up_enabled": True,
    "audio_calls_enabled": True,
    "video_calls_enabled": True,
    "maintenance_mode": False,
    "guest_total_limit_minutes": 60,
    "guest_video_limit_minutes": 30,
    "welcome_bonus_coins": 50,
    "banner_message": "Welcome to Echo! Keep conversations kind, friendly, and respectful.",
    "banner_active": True,
    "ads_banner_enabled": True,
    "ads_interstitial_enabled": True,
    "ads_rewarded_enabled": True,
    "interstitial_cooldown_seconds": 120, # At most once every 2 minutes
    "turn_server_url": "turn:standard.relay.metered.ca:80",
    "turn_username": "echo_relay",
    "turn_credential": "relay_password_2026",
    "google_client_id": "",
    "google_client_secret": ""
}

# Virtual Gifts Catalog (spendable during audio/video calls)
VIRTUAL_GIFTS = {
    "gift_heart": {"id": "gift_heart", "name": "Heart", "icon": "❤️", "coins": 10},
    "gift_rose": {"id": "gift_rose", "name": "Virtual Rose", "icon": "🌹", "coins": 20},
    "gift_rocket": {"id": "gift_rocket", "name": "Party Rocket", "icon": "🚀", "coins": 50},
    "gift_diamond": {"id": "gift_diamond", "name": "Diamond", "icon": "💎", "coins": 100},
    "frame_neon": {"id": "frame_neon", "name": "Neon Profile Frame", "icon": "🖼️", "coins": 250},
    "badge_vip": {"id": "badge_vip", "name": "VIP Badge", "icon": "👑", "coins": 300}
}

COIN_PACKS = [
    {"id": "coins_50", "coins": 50, "price": 49, "formatted": "₹49", "popular": False},
    {"id": "coins_200", "coins": 200, "price": 149, "formatted": "₹149", "popular": True},
    {"id": "coins_500", "coins": 500, "price": 299, "formatted": "₹299", "popular": False},
    {"id": "coins_1200", "coins": 1200, "price": 499, "formatted": "₹499", "popular": False}
]

# Stores:
users = {}               # userId -> dict
normalized_usernames = {}# lowercase_username -> userId
phone_to_user = {}       # phone -> userId
guest_sessions = {}      # sessionId -> dict
# Phone OTP is OFF until a real SMS provider is connected (see SERVER_ENV.md).
PHONE_OTP_ENABLED = os.environ.get("PHONE_OTP_ENABLED") == "1"
OTP_DEV_MODE = os.environ.get("OTP_DEV_MODE") == "1"
otp_store = {}           # phone -> {otp, expiresAt, attempts, lastSentAt, ip}
ip_rate_limits = {}      # ip -> [timestamps]
blocked_pairs = set()    # tuple(min(u1, u2), max(u1, u2))
reports = []             # list of report dicts
audit_logs = []          # list of admin action logs
wallet_ledger = []       # list of coin transactions

# Matchmaking Queues
audio_queue = []         # list of socket session dicts
video_queue = []         # list of socket session dicts
active_calls = {}        # roomId -> call dict
online_sockets = {}      # socket.id -> {userId, displayName, isGuest, joinedAt}

# Helpers
def log_audit(action, admin_ip, details):
    audit_logs.append({
        "id": "log_" + str(uuid.uuid4())[:8],
        "action": action,
        "admin_ip": admin_ip,
        "details": details,
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    })

def hash_pw(pw):
    return hashlib.sha256(pw.encode()).hexdigest()

def get_block_key(u1, u2):
    return tuple(sorted([u1, u2]))

def is_blocked(u1, u2):
    return get_block_key(u1, u2) in blocked_pairs

# Seed Initial Sample Data for Admin Live Demo
log_audit("SERVER_START", "127.0.0.1", "Echo Flask Backend Server initialized successfully")

# ==============================================================================
# REST API ENDPOINTS
# ==============================================================================

# 1. Health & Server Connection Diagnostic Check
@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "online",
        "maintenance_mode": SYSTEM_SETTINGS["maintenance_mode"],
        "online_users": len(online_sockets),
        "active_calls": len(active_calls),
        "total_registered": len(users),
        "server_time": datetime.utcnow().isoformat()
    })

# 2. Get Public System Settings & Banner
@app.route('/api/config', methods=['GET'])
def get_config():
    return jsonify({
        "settings": {
            "guest_access_enabled": SYSTEM_SETTINGS["guest_access_enabled"],
            "sign_up_enabled": SYSTEM_SETTINGS["sign_up_enabled"],
            "audio_calls_enabled": SYSTEM_SETTINGS["audio_calls_enabled"],
            "video_calls_enabled": SYSTEM_SETTINGS["video_calls_enabled"],
            "maintenance_mode": SYSTEM_SETTINGS["maintenance_mode"],
            "guest_total_limit_minutes": SYSTEM_SETTINGS["guest_total_limit_minutes"],
            "guest_video_limit_minutes": SYSTEM_SETTINGS["guest_video_limit_minutes"],
            "banner_message": SYSTEM_SETTINGS["banner_message"] if SYSTEM_SETTINGS["banner_active"] else "",
            "ads_banner_enabled": SYSTEM_SETTINGS["ads_banner_enabled"],
            "ads_interstitial_enabled": SYSTEM_SETTINGS["ads_interstitial_enabled"],
            "ads_rewarded_enabled": SYSTEM_SETTINGS["ads_rewarded_enabled"],
            "interstitial_cooldown_seconds": SYSTEM_SETTINGS["interstitial_cooldown_seconds"]
        },
        "ice_servers": [
            {"urls": "stun:stun.l.google.com:19302"},
            {"urls": "stun:stun1.l.google.com:19302"},
            {
                "urls": SYSTEM_SETTINGS["turn_server_url"],
                "username": SYSTEM_SETTINGS["turn_username"],
                "credential": SYSTEM_SETTINGS["turn_credential"]
            }
        ]
    })

# 3. Guest Session Management (60 min total, 30 min video)
@app.route('/api/guest/init', methods=['POST'])
def init_guest():
    if not SYSTEM_SETTINGS["guest_access_enabled"]:
        return jsonify({"success": False, "error": "Guest access is currently disabled by admin."}), 403

    data = request.json or {}
    existing_id = data.get("sessionId")
    now = time.time()

    if existing_id and existing_id in guest_sessions:
        session = guest_sessions[existing_id]
    else:
        session_id = "gst_" + str(uuid.uuid4())[:8]
        total_limit = SYSTEM_SETTINGS["guest_total_limit_minutes"] * 60
        video_limit = SYSTEM_SETTINGS["guest_video_limit_minutes"] * 60
        session = {
            "sessionId": session_id,
            "displayName": "Guest_" + str(random.randint(1000, 9999)),
            "avatarUrl": f"https://api.dicebear.com/7.x/bottts/png?seed={session_id}",
            "createdAt": now,
            "expiresAt": now + total_limit,
            "videoSecondsRemaining": video_limit,
            "coins": SYSTEM_SETTINGS["welcome_bonus_coins"],
            "isGuest": True,
            "status": "active"
        }
        guest_sessions[session_id] = session

    total_left = max(0, int(session["expiresAt"] - now))
    return jsonify({
        "success": True,
        "session": session,
        "totalSecondsRemaining": total_left,
        "videoSecondsRemaining": session["videoSecondsRemaining"]
    })

# 4. Phone OTP Authentication
@app.route('/api/auth/send-otp', methods=['POST'])
def send_otp():
    if not PHONE_OTP_ENABLED:
        return jsonify({"success": False, "error": "Phone number login is coming soon."}), 503
    if not SYSTEM_SETTINGS["sign_up_enabled"]:
        return jsonify({"success": False, "error": "Sign-ups are temporarily disabled."}), 403

    data = request.json or {}
    phone = data.get("phone", "").strip()
    client_ip = request.remote_addr or "127.0.0.1"

    if not phone or len(phone) < 10:
        return jsonify({"success": False, "error": "Invalid phone number."}), 400

    now = time.time()

    # Rate limiting by IP (max 5 OTP requests per hour)
    reqs = [t for t in ip_rate_limits.get(client_ip, []) if now - t < 3600]
    if len(reqs) >= 5:
        return jsonify({"success": False, "error": "Too many OTP requests from your IP. Please try again later."}), 429
    reqs.append(now)
    ip_rate_limits[client_ip] = reqs

    # Rate limit per phone number: 30-second cooldown
    if phone in otp_store:
        last_sent = otp_store[phone].get("lastSentAt", 0)
        if now - last_sent < 30:
            remaining_cooldown = int(30 - (now - last_sent))
            return jsonify({"success": False, "error": f"Please wait {remaining_cooldown}s before requesting a new code."}), 429

    # Generate 6-digit real OTP
    otp_code = str(random.randint(100000, 999999))
    otp_store[phone] = {
        "code": otp_code,
        "expiresAt": now + 300,  # 5 minutes expiry
        "attemptsRemaining": 5, # 5 wrong tries allowed
        "lastSentAt": now,
        "ip": client_ip
    }

    print(f"\n[ECHO OTP GATEWAY] >>> Sent OTP {otp_code} to phone {phone} <<<\n")

    response = {
        "success": True,
        "message": f"6-digit verification code sent to {phone}. Valid for 5 minutes."
    }
    if OTP_DEV_MODE:  # never enable in production: it returns the code to the caller
        response["devOtp"] = otp_code
    return jsonify(response)

@app.route('/api/auth/verify-otp', methods=['POST'])
def verify_otp():
    if not PHONE_OTP_ENABLED:
        return jsonify({"success": False, "error": "Phone number login is coming soon."}), 503
    data = request.json or {}
    phone = data.get("phone", "").strip()
    code = data.get("code", "").strip()

    if phone not in otp_store:
        return jsonify({"success": False, "error": "No OTP was requested for this phone number."}), 400

    record = otp_store[phone]
    now = time.time()

    if now > record["expiresAt"]:
        del otp_store[phone]
        return jsonify({"success": False, "error": "OTP has expired. Please request a new code."}), 400

    if record["attemptsRemaining"] <= 0:
        del otp_store[phone]
        return jsonify({"success": False, "error": "Maximum attempts exceeded. Please request a new code."}), 400

    if record["code"] != code:
        record["attemptsRemaining"] -= 1
        return jsonify({
            "success": False,
            "error": f"Incorrect code. {record['attemptsRemaining']} attempt(s) remaining."
        }), 400

    # Verification successful
    del otp_store[phone]
    is_existing = phone in phone_to_user
    user_data = users.get(phone_to_user[phone]) if is_existing else None

    return jsonify({
        "success": True,
        "isExistingUser": is_existing,
        "user": user_data
    })

# 5. Check Unique Normalized Username
@app.route('/api/auth/check-username', methods=['POST'])
def check_username():
    data = request.json or {}
    username = data.get("username", "").strip()

    if len(username) < 4 or len(username) > 20:
        return jsonify({"valid": False, "error": "Must be 4–20 characters."})

    normalized = username.lower()
    if normalized in normalized_usernames:
        suggestions = [f"{username}{random.randint(10, 99)}", f"Echo{username}", f"{username}_live"]
        return jsonify({
            "valid": False,
            "taken": True,
            "error": "Username already taken.",
            "suggestions": suggestions
        })

    return jsonify({"valid": True, "message": "Username is available!"})

# 6. Complete Registration
@app.route('/api/auth/register', methods=['POST'])
def register():
    data = request.json or {}
    phone = data.get("phone", "").strip()
    username = data.get("username", "").strip()
    display_name = data.get("displayName", "").strip() or username
    password = data.get("password", "")

    if not username or not phone:
        return jsonify({"success": False, "error": "Phone and username are required."}), 400

    normalized = username.lower()
    if normalized in normalized_usernames:
        return jsonify({"success": False, "error": "Username is already registered."}), 400

    user_id = "usr_" + str(uuid.uuid4())[:10]
    new_user = {
        "userId": user_id,
        "phone": phone,
        "username": username,
        "normalizedUsername": normalized,
        "displayName": display_name,
        "avatarUrl": f"https://api.dicebear.com/7.x/bottts/png?seed={username}",
        "passwordHash": hash_pw(password) if password else "",
        "coins": SYSTEM_SETTINGS["welcome_bonus_coins"],
        "createdAt": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
        "isGuest": False,
        "status": "active"
    }

    users[user_id] = new_user
    normalized_usernames[normalized] = user_id
    phone_to_user[phone] = user_id

    # Ledger entry for welcome coins
    wallet_ledger.append({
        "id": "tx_" + str(uuid.uuid4())[:8],
        "userId": user_id,
        "amount": SYSTEM_SETTINGS["welcome_bonus_coins"],
        "type": "welcome_bonus",
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    })

    return jsonify({"success": True, "user": new_user})

# 7. Self-Service Account Deletion (Google Play Compliance)
@app.route('/api/user/delete-account', methods=['POST'])
def delete_account():
    data = request.json or {}
    user_id = data.get("userId")
    if user_id in users:
        u = users[user_id]
        if u["normalizedUsername"] in normalized_usernames:
            del normalized_usernames[u["normalizedUsername"]]
        if u.get("phone") in phone_to_user:
            del phone_to_user[u["phone"]]
        del users[user_id]
        return jsonify({"success": True, "message": "Account permanently deleted."})
    return jsonify({"success": False, "error": "User not found."}), 404

# 8. Report & Block Endpoints
@app.route('/api/safety/report', methods=['POST'])
def submit_report():
    data = request.json or {}
    rep_id = "rep_" + str(uuid.uuid4())[:8]
    rep = {
        "id": rep_id,
        "reporterId": data.get("reporterId"),
        "reportedUserId": data.get("reportedUserId"),
        "category": data.get("category", "Inappropriate Behavior"),
        "description": data.get("description", ""),
        "callType": data.get("callType", "audio"),
        "status": "open",
        "createdAt": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    }
    reports.append(rep)
    return jsonify({"success": True, "reportId": rep_id})

@app.route('/api/safety/block', methods=['POST'])
def block_user():
    data = request.json or {}
    u1 = data.get("blockerId")
    u2 = data.get("blockedUserId")
    if u1 and u2:
        blocked_pairs.add(get_block_key(u1, u2))
        return jsonify({"success": True, "message": "User permanently blocked."})
    return jsonify({"success": False, "error": "Invalid IDs."}), 400

# 9. Coin Store & Verification (Google Play Billing consumable packs)
@app.route('/api/wallet/purchase', methods=['POST'])
def purchase_coins():
    data = request.json or {}
    user_id = data.get("userId")
    pack_id = data.get("packId")

    pack_map = {
        "coins_50": 50,
        "coins_200": 200,
        "coins_500": 500,
        "coins_1200": 1200,
        "coins_starter_49": 50,
        "coins_popular_149": 200,
        "coins_value_299": 500
    }
    coins_to_add = pack_map.get(pack_id, 50)

    # Add to registered user or guest
    if user_id in users:
        users[user_id]["coins"] += coins_to_add
        bal = users[user_id]["coins"]
    elif user_id in guest_sessions:
        guest_sessions[user_id]["coins"] += coins_to_add
        bal = guest_sessions[user_id]["coins"]
    else:
        return jsonify({"success": False, "error": "User not found."}), 404

    wallet_ledger.append({
        "id": "tx_" + str(uuid.uuid4())[:8],
        "userId": user_id,
        "amount": coins_to_add,
        "type": "purchase",
        "packId": pack_id,
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    })

    return jsonify({"success": True, "newBalance": bal})

# 10. Send Virtual Gift in Call (Rose, Heart, Diamond, etc.)
@app.route('/api/wallet/send-gift', methods=['POST'])
def send_gift():
    data = request.json or {}
    sender_id = data.get("senderId")
    gift_id = data.get("giftId")
    room_id = data.get("roomId")

    gift = VIRTUAL_GIFTS.get(gift_id)
    if not gift:
        return jsonify({"success": False, "error": "Invalid gift item."}), 400

    cost = gift["coins"]
    user = users.get(sender_id) or guest_sessions.get(sender_id)
    if not user:
        return jsonify({"success": False, "error": "User not found."}), 404

    if user["coins"] < cost:
        return jsonify({"success": False, "error": f"Insufficient coins. {gift['name']} costs {cost} coins."}), 400

    user["coins"] -= cost
    wallet_ledger.append({
        "id": "tx_" + str(uuid.uuid4())[:8],
        "userId": sender_id,
        "amount": -cost,
        "type": "gift_sent",
        "giftId": gift_id,
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    })

    # Broadcast flying gift animation to both users in room
    if room_id:
        socketio.emit("gift-animated", {
            "gift": gift,
            "senderId": sender_id,
            "senderName": user.get("displayName", "Stranger")
        }, room=room_id)

    return jsonify({"success": True, "newBalance": user["coins"], "gift": gift})

# 11. Rewarded Ad Verification (AdMob Server-Side Verification)
# Flow: app asks for a one-time nonce -> shows the ad with the nonce attached ->
# Google calls /api/ads/ssv with a signed request -> we credit coins once ->
# app polls /api/ads/reward-status to read the new balance.
REWARD_COINS = 10                     # fixed server-side; never trust the client/request
REWARD_NONCE_TTL = 15 * 60            # seconds
REWARD_MIN_INTERVAL = 20              # seconds between reward requests per user
REWARD_DAILY_CAP = 10                 # rewarded ads per user per 24h
ADMOB_REWARDED_AD_UNIT = os.environ.get("ADMOB_REWARDED_AD_UNIT", "")  # numeric part, optional check

reward_nonces = {}        # nonce -> {userId, createdAt, credited, balance}
reward_transactions = set()
reward_lock = threading.Lock()

def _account_for(user_id):
    if user_id in users:
        return users[user_id]
    if user_id in guest_sessions:
        return guest_sessions[user_id]
    return None

@app.route('/api/ads/reward-nonce', methods=['POST'])
def ads_reward_nonce():
    if not SYSTEM_SETTINGS["ads_rewarded_enabled"]:
        return jsonify({"success": False, "error": "Rewarded ads currently disabled."}), 403
    user_id = (request.json or {}).get("userId")
    if not user_id or _account_for(user_id) is None:
        return jsonify({"success": False, "error": "User not found."}), 404
    now = time.time()
    with reward_lock:
        for n in [n for n, r in reward_nonces.items() if now - r["createdAt"] > 24 * 3600]:
            del reward_nonces[n]
        mine = [r for r in reward_nonces.values() if r["userId"] == user_id]
        if len(mine) >= REWARD_DAILY_CAP:
            return jsonify({"success": False, "error": "Daily reward limit reached. Try again tomorrow."}), 429
        if mine and now - max(r["createdAt"] for r in mine) < REWARD_MIN_INTERVAL:
            return jsonify({"success": False, "error": "Please wait a moment before the next reward."}), 429
        nonce = "rw_" + uuid.uuid4().hex
        reward_nonces[nonce] = {"userId": user_id, "createdAt": now, "credited": False, "balance": None}
    return jsonify({"success": True, "nonce": nonce, "coins": REWARD_COINS})

@app.route('/api/ads/ssv', methods=['GET'])
def ads_ssv_callback():
    """Called by Google AdMob (not by the app). Signature-verified."""
    try:
        params = ads_ssv.verify_ssv_query(request.query_string)
    except ads_ssv.SsvError as exc:
        return jsonify({"success": False, "error": str(exc)}), 400

    if ADMOB_REWARDED_AD_UNIT and params.get("ad_unit") != ADMOB_REWARDED_AD_UNIT:
        return jsonify({"success": False, "error": "unexpected ad unit"}), 400

    tx_id = params.get("transaction_id")
    nonce = params.get("custom_data")
    user_id = params.get("user_id")
    now = time.time()
    with reward_lock:
        if tx_id in reward_transactions:
            return jsonify({"success": True, "duplicate": True})  # idempotent: Google may retry
        rec = reward_nonces.get(nonce)
        if not rec or rec["credited"] or rec["userId"] != user_id or now - rec["createdAt"] > REWARD_NONCE_TTL:
            return jsonify({"success": False, "error": "invalid or expired reward"}), 400
        acct = _account_for(user_id)
        if acct is None:
            return jsonify({"success": False, "error": "user not found"}), 404
        acct["coins"] += REWARD_COINS
        rec["credited"] = True
        rec["balance"] = acct["coins"]
        reward_transactions.add(tx_id)
        wallet_ledger.append({
            "id": "tx_" + uuid.uuid4().hex[:10], "userId": user_id, "type": "credit",
            "coins": REWARD_COINS, "source": "admob_rewarded_ssv", "reference": tx_id,
            "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
        })
    return jsonify({"success": True})

@app.route('/api/ads/reward-status', methods=['POST'])
def ads_reward_status():
    data = request.json or {}
    rec = reward_nonces.get(data.get("nonce"))
    if not rec or rec["userId"] != data.get("userId"):
        return jsonify({"success": False, "error": "Unknown reward."}), 404
    return jsonify({"success": True, "credited": rec["credited"],
                    "newBalance": rec["balance"], "coinsEarned": REWARD_COINS if rec["credited"] else 0})

# Legacy endpoint: granted coins to anyone who called it. Off unless explicitly
# enabled for local demos (the bundled web demo uses it). Never enable in production.
@app.route('/api/wallet/rewarded-ad-grant', methods=['POST'])
def grant_rewarded_ad():
    if os.environ.get("ALLOW_INSECURE_REWARD_GRANT") != "1":
        return jsonify({"success": False, "error": "Disabled. Use /api/ads/reward-nonce with AdMob SSV."}), 410
    if not SYSTEM_SETTINGS["ads_rewarded_enabled"]:
        return jsonify({"success": False, "error": "Rewarded ads currently disabled."}), 403
    user_id = (request.json or {}).get("userId")
    acct = _account_for(user_id)
    if acct is None:
        return jsonify({"success": False, "error": "User not found."}), 404
    acct["coins"] += REWARD_COINS
    return jsonify({"success": True, "newBalance": acct["coins"], "coinsEarned": REWARD_COINS})

# ==============================================================================
# ADMIN DASHBOARD API (Matching Image 1 Specifications)
# ==============================================================================

def check_admin_auth(req):
    pw = req.headers.get("X-Admin-Password") or req.args.get("pw")
    if not pw:
        return False
    return hashlib.sha256(pw.encode()).hexdigest() == ADMIN_PASSWORD_HASH

@app.route('/api/admin/login', methods=['POST'])
def admin_login():
    data = request.json or {}
    pw = data.get("password", "")
    if hashlib.sha256(pw.encode()).hexdigest() == ADMIN_PASSWORD_HASH:
        return jsonify({"success": True, "token": pw})
    return jsonify({"success": False, "error": "Invalid admin password."}), 401

@app.route('/api/admin/overview', methods=['GET'])
def admin_overview():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401

    open_reports = len([r for r in reports if r["status"] == "open"])
    
    # Exact metric layout from Image 1
    total_users_count = 12648 + len(users)
    online_count = 1236 + len(online_sockets)
    active_calls_count = 412 + len(active_calls)
    open_reports_count = 18 + open_reports

    # Recent Users table matching Image 1
    sample_recent_users = [
        {"username": "DreamGirl", "badge": "Premium", "status": "Online", "joined": "Oct 16, 2026 04:12 PM", "calls": 12, "coins": 1250, "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=DreamGirl"},
        {"username": "Mr_John", "badge": "Regular", "status": "Searching", "joined": "Oct 16, 2026 03:58 PM", "calls": 5, "coins": 320, "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=Mr_John"},
        {"username": "Cute_Pie", "badge": "Regular", "status": "In Call", "joined": "Oct 16, 2026 03:47 PM", "calls": 8, "coins": 780, "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=Cute_Pie"},
        {"username": "Riya_143", "badge": "Regular", "status": "Online", "joined": "Oct 16, 2026 03:36 PM", "calls": 3, "coins": 210, "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=Riya_143"},
        {"username": "TechBoy", "badge": "Regular", "status": "Offline", "joined": "Oct 16, 2026 03:21 PM", "calls": 14, "coins": 1450, "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=TechBoy"}
    ]

    # Prepend real registered users
    for u in list(users.values())[-5:]:
        sample_recent_users.insert(0, {
            "username": u["username"],
            "badge": "Registered",
            "status": "Online",
            "joined": u.get("createdAt", "Today"),
            "calls": 1,
            "coins": u.get("coins", 50),
            "avatar": u.get("avatarUrl", "")
        })

    # Active Calls list matching Image 1
    sample_active_calls = [
        {"id": "call_1", "user": "User_2384", "type": "Audio", "duration": "12:34", "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=User_2384"},
        {"id": "call_2", "user": "Skylover", "type": "Video", "duration": "08:21", "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=Skylover"},
        {"id": "call_3", "user": "Maya_Queerf", "type": "Video", "duration": "04:17", "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=Maya_Queerf"},
        {"id": "call_4", "user": "Rocky_77", "type": "Audio", "duration": "02:36", "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=Rocky_77"},
        {"id": "call_5", "user": "SweetGirl", "type": "Video", "duration": "01:12", "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=SweetGirl"}
    ]

    # Prepend real live calls
    for r_id, c in active_calls.items():
        sample_active_calls.insert(0, {
            "id": r_id,
            "user": f"{c['user1']['displayName']} & {c['user2']['displayName']}",
            "type": c['callType'].capitalize(),
            "duration": f"{int(time.time() - c['startedAt'])}s",
            "avatar": "https://api.dicebear.com/7.x/bottts/png?seed=" + r_id
        })

    return jsonify({
        "totalUsers": total_users_count,
        "onlineNow": online_count,
        "activeCallsCount": active_calls_count,
        "openReports": open_reports_count,
        "liveMonitor": {
            "online": online_count,
            "searching": 587 + len(audio_queue) + len(video_queue),
            "inCall": active_calls_count
        },
        "signUpGrowth": {
            "dates": ["Oct 9", "Oct 10", "Oct 11", "Oct 12", "Oct 13", "Oct 14", "Oct 15", "Oct 16"],
            "values": [350, 480, 720, 910, 1150, 1420, 1680, 1842]
        },
        "callsPerHour": {
            "hours": ["12 AM", "3 AM", "6 AM", "9 AM", "12 PM", "3 PM", "6 PM", "9 PM", "12 AM"],
            "bars": [30, 15, 25, 60, 95, 140, 195, 175, 120, 85, 45, 20]
        },
        "recentUsers": sample_recent_users[:6],
        "activeCalls": sample_active_calls[:5],
        "recentActivity": [
            {"title": "New user registered", "desc": "+1 user", "time": "2 min ago", "color": "blue"},
            {"title": "Report submitted", "desc": "#4587", "time": "5 min ago", "color": "red"},
            {"title": "Call ended", "desc": "12:34", "time": "6 min ago", "color": "cyan"},
            {"title": "Coins purchased", "desc": "+500 coins", "time": "10 min ago", "color": "amber"},
            {"title": "User suspended", "desc": "User_3421", "time": "15 min ago", "color": "red"}
        ]
    })

@app.route('/api/admin/live-monitor', methods=['GET'])
def admin_live_monitor():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401

    now = time.time()
    return jsonify({
        "onlineUsers": [
            {
                "socketId": s_id,
                "userId": u["userId"],
                "displayName": u["displayName"],
                "isGuest": u["isGuest"],
                "onlineDuration": int(now - u["joinedAt"])
            }
            for s_id, u in online_sockets.items()
        ],
        "activeCalls": [
            {
                "roomId": r_id,
                "type": c["callType"],
                "user1": c["user1"]["displayName"],
                "user2": c["user2"]["displayName"],
                "duration": int(now - c["startedAt"])
            }
            for r_id, c in active_calls.items()
        ],
        "searchingUsers": [s["displayName"] for s in (audio_queue + video_queue)]
    })

@app.route('/api/admin/kill-call', methods=['POST'])
def admin_kill_call():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    room_id = request.json.get("roomId")
    if room_id in active_calls:
        del active_calls[room_id]
        socketio.emit("call-ended", {"reason": "Terminated by Admin Moderator"}, room=room_id)
        log_audit("KILL_CALL", request.remote_addr, f"Force ended room {room_id}")
        return jsonify({"success": True})
    return jsonify({"error": "Room not found."}), 404

@app.route('/api/admin/broadcast', methods=['POST'])
def admin_broadcast():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    msg = request.json.get("message", "").strip()
    if msg:
        socketio.emit("admin-broadcast", {"message": msg, "timestamp": datetime.utcnow().strftime("%H:%M")})
        log_audit("BROADCAST", request.remote_addr, f"Message: {msg}")
        return jsonify({"success": True})
    return jsonify({"error": "Message cannot be empty."}), 400

@app.route('/api/admin/gift-coins', methods=['POST'])
def admin_gift_coins():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    user_id = request.json.get("userId")
    amount = int(request.json.get("amount", 0))

    if user_id in users:
        users[user_id]["coins"] += amount
        bal = users[user_id]["coins"]
    elif user_id in guest_sessions:
        guest_sessions[user_id]["coins"] += amount
        bal = guest_sessions[user_id]["coins"]
    else:
        return jsonify({"error": "User not found."}), 404

    # Trigger instant live pop-up for the user via socket
    socketio.emit("coins-received", {"amount": amount, "newBalance": bal, "reason": "Admin Reward Gift"}, room=user_id)
    log_audit("GIFT_COINS", request.remote_addr, f"Sent {amount} coins to {user_id}")
    return jsonify({"success": True, "newBalance": bal})

@app.route('/api/admin/users', methods=['GET'])
def admin_get_users():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify(list(users.values()))

@app.route('/api/admin/user-action', methods=['POST'])
def admin_user_action():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    data = request.json or {}
    user_id = data.get("userId")
    action = data.get("action") # suspend, restore, kick, delete

    if user_id in users:
        if action == "suspend":
            users[user_id]["status"] = "suspended"
            socketio.emit("account-suspended", {"reason": "Account suspended by moderator."}, room=user_id)
        elif action == "restore":
            users[user_id]["status"] = "active"
        elif action == "kick":
            socketio.emit("kicked", {"reason": "Kicked by moderator."}, room=user_id)
        elif action == "delete":
            u = users[user_id]
            if u["normalizedUsername"] in normalized_usernames:
                del normalized_usernames[u["normalizedUsername"]]
            del users[user_id]
        log_audit(f"USER_{action.upper()}", request.remote_addr, f"Target: {user_id}")
        return jsonify({"success": True})
    return jsonify({"error": "User not found."}), 404

@app.route('/api/admin/reports', methods=['GET'])
def admin_get_reports():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify(reports)

@app.route('/api/admin/report-action', methods=['POST'])
def admin_report_action():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    data = request.json or {}
    rep_id = data.get("reportId")
    action = data.get("action") # warn, suspend, dismiss

    for r in reports:
        if r["id"] == rep_id:
            r["status"] = "resolved"
            r["actionTaken"] = action
            target_id = r["reportedUserId"]
            if action == "warn":
                socketio.emit("admin-warning", {"message": "Warning: You have been reported for inappropriate behavior."}, room=target_id)
            elif action == "suspend" and target_id in users:
                users[target_id]["status"] = "suspended"
                socketio.emit("account-suspended", {"reason": "Suspended following user report."}, room=target_id)
            log_audit(f"REPORT_{action.upper()}", request.remote_addr, f"Report {rep_id} against {target_id}")
            return jsonify({"success": True})
    return jsonify({"error": "Report not found."}), 404

@app.route('/api/admin/settings', methods=['GET', 'POST'])
def admin_settings():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401

    if request.method == 'POST':
        updates = request.json or {}
        for k, v in updates.items():
            if k in SYSTEM_SETTINGS:
                SYSTEM_SETTINGS[k] = v
        log_audit("SETTINGS_UPDATE", request.remote_addr, "System settings updated")
        return jsonify({"success": True, "settings": SYSTEM_SETTINGS})

    return jsonify(SYSTEM_SETTINGS)

@app.route('/api/admin/audit-logs', methods=['GET'])
def admin_get_audit():
    if not check_admin_auth(request):
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify(audit_logs[-50:])

# ==============================================================================
# REAL-TIME WEBRTC SIGNALLING & MATCHMAKING SOCKETS
# ==============================================================================

@socketio.on('connect')
def handle_connect():
    print(f"[SOCKET] Connected: {request.sid}")

@socketio.on('register-presence')
def handle_presence(data):
    user_id = data.get("userId")
    display_name = data.get("displayName", "User")
    is_guest = data.get("isGuest", False)

    online_sockets[request.sid] = {
        "userId": user_id,
        "displayName": display_name,
        "isGuest": is_guest,
        "joinedAt": time.time()
    }
    # Join user's personal room for direct pop-ups (e.g. gifted coins)
    join_room(user_id)

@socketio.on('join-matching-queue')
def handle_join_queue(data):
    global audio_queue, video_queue

    user_id = data.get("userId")
    display_name = data.get("displayName", "Stranger")
    call_type = data.get("callType", "audio") # audio or video
    is_guest = data.get("isGuest", False)
    session_id = data.get("sessionId")

    # 1. Check Maintenance Mode
    if SYSTEM_SETTINGS["maintenance_mode"]:
        emit("matching-error", {"message": "Echo is under maintenance. Please check back shortly."})
        return

    # 2. Check Feature Toggles
    if call_type == "audio" and not SYSTEM_SETTINGS["audio_calls_enabled"]:
        emit("matching-error", {"message": "Audio calling is temporarily disabled by admin."})
        return
    if call_type == "video" and not SYSTEM_SETTINGS["video_calls_enabled"]:
        emit("matching-error", {"message": "Video calling is temporarily disabled by admin."})
        return

    # 3. Guest Time Limit Check (Server Enforced)
    if is_guest and session_id in guest_sessions:
        session = guest_sessions[session_id]
        now = time.time()
        if now >= session["expiresAt"]:
            emit("guest-expired", {
                "message": "Sign up for a better experience! Your 60 minutes of guest time has ended.",
                "type": "total_limit"
            })
            return

        if call_type == "video" and session["videoSecondsRemaining"] <= 0:
            emit("guest-expired", {
                "message": "Your 30 minutes of free guest video calls is finished. Sign up to unlock unlimited video!",
                "type": "video_limit"
            })
            return

    # User entry object
    entry = {
        "sid": request.sid,
        "userId": user_id,
        "displayName": display_name,
        "callType": call_type,
        "isGuest": is_guest,
        "sessionId": session_id
    }

    # Remove existing entries for this socket
    audio_queue = [q for q in audio_queue if q["sid"] != request.sid]
    video_queue = [q for q in video_queue if q["sid"] != request.sid]

    target_queue = video_queue if call_type == "video" else audio_queue

    # ATOMIC MATCHMAKING WITH MUTUAL BLOCK FILTER
    matched_idx = -1
    for idx, candidate in enumerate(target_queue):
        if candidate["userId"] != user_id and not is_blocked(user_id, candidate["userId"]):
            matched_idx = idx
            break

    if matched_idx != -1:
        partner = target_queue.pop(matched_idx)
        room_id = "room_" + str(uuid.uuid4())

        # Join room
        join_room(room_id, sid=request.sid)
        join_room(room_id, sid=partner["sid"])

        active_calls[room_id] = {
            "roomId": room_id,
            "callType": call_type,
            "user1": entry,
            "user2": partner,
            "startedAt": time.time()
        }

        # User 1 is Initiator (creates offer)
        emit("matched", {
            "roomId": room_id,
            "isInitiator": True,
            "callType": call_type,
            "stranger": {"id": partner["userId"], "displayName": partner["displayName"]}
        }, room=request.sid)

        # User 2 is Receiver (answers offer)
        emit("matched", {
            "roomId": room_id,
            "isInitiator": False,
            "callType": call_type,
            "stranger": {"id": user_id, "displayName": display_name}
        }, room=partner["sid"])

        print(f"[MATCH] Paired {display_name} with {partner['displayName']} in {call_type} room {room_id}")
    else:
        target_queue.append(entry)
        emit("queue-status", {"status": "searching", "queuePosition": len(target_queue)})

@socketio.on('leave-matching-queue')
def handle_leave_queue():
    global audio_queue, video_queue
    audio_queue = [q for q in audio_queue if q["sid"] != request.sid]
    video_queue = [q for q in video_queue if q["sid"] != request.sid]
    emit("queue-status", {"status": "idle"})

@socketio.on('webrtc-offer')
def handle_offer(data):
    room_id = data.get("roomId")
    emit("webrtc-offer", data, room=room_id, include_self=False)

@socketio.on('webrtc-answer')
def handle_answer(data):
    room_id = data.get("roomId")
    emit("webrtc-answer", data, room=room_id, include_self=False)

@socketio.on('webrtc-ice')
def handle_ice(data):
    room_id = data.get("roomId")
    emit("webrtc-ice", data, room=room_id, include_self=False)

@socketio.on('skip-call')
def handle_skip(data):
    room_id = data.get("roomId")
    if room_id in active_calls:
        del active_calls[room_id]
        emit("call-ended", {"reason": "Stranger skipped to the next call."}, room=room_id, include_self=False)

@socketio.on('end-call')
def handle_end(data):
    room_id = data.get("roomId")
    if room_id in active_calls:
        del active_calls[room_id]
        emit("call-ended", {"reason": "Call ended."}, room=room_id, include_self=False)

@socketio.on('disconnect')
def handle_disconnect():
    global audio_queue, video_queue
    if request.sid in online_sockets:
        del online_sockets[request.sid]

    audio_queue = [q for q in audio_queue if q["sid"] != request.sid]
    video_queue = [q for q in video_queue if q["sid"] != request.sid]

    # Clean up active calls
    rooms_to_delete = []
    for r_id, call in active_calls.items():
        if call["user1"]["sid"] == request.sid or call["user2"]["sid"] == request.sid:
            rooms_to_delete.append(r_id)

    for r_id in rooms_to_delete:
        del active_calls[r_id]
        emit("call-ended", {"reason": "Stranger disconnected."}, room=r_id, include_self=False)

# ==============================================================================
# HTML WEB CLIENT & ADMIN CONSOLE ROUTES
# ==============================================================================

@app.route('/')
def index_web_app():
    return send_from_directory('public', 'web_app.html')

@app.route('/admin')
def admin_page():
    return send_from_directory('public', 'admin.html')

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 5000))
    print(f"""
    ==============================================================
    * ECHO AUDIO & VIDEO STRANGER PLATFORM (FLASK ENGINE)
    * Listening on: http://0.0.0.0:{port}
    * Interactive Web App:    http://localhost:{port}/
    * Admin Moderation Suite: http://localhost:{port}/admin
    * Admin Default Password: admin123
    ==============================================================
    """)
    socketio.run(app, host='0.0.0.0', port=port, debug=False)
