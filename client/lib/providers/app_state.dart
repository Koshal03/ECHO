import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCPeerConnectionState, RTCIceConnectionState;
import '../models/user_model.dart';
import '../models/call_session.dart';
import '../models/chat_message.dart';
import '../constants/terms_text.dart';
import '../models/coin_pack.dart';
import '../models/gift.dart';
import '../services/socket_service.dart';
import '../services/webrtc_service.dart';
import '../services/guest_service.dart';
import '../services/ad_service.dart';
import '../services/billing_service.dart';
import '../config/ad_config.dart';
import '../config/auth_config.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum GoogleOutcome { signedIn, needsUsername, cancelled, error }

class GoogleSignInResult {
  final GoogleOutcome outcome;
  final String? message;
  final String? suggestedName;
  const GoogleSignInResult(this.outcome, {this.message, this.suggestedName});
}

enum OtpOutcome { sent, signedIn, needsUsername, error }

class OtpResult {
  final OtpOutcome outcome;
  final String? message;
  final int cooldownSeconds;
  const OtpResult(this.outcome, {this.message, this.cooldownSeconds = 45});
}

class AppState extends ChangeNotifier {
  UserModel? currentUser;
  CallSession? activeCall;
  bool isSearching = false;

  /// Which kind of stranger we are searching for / last talked to: 'audio' | 'video' | 'text'.
  String searchMode = 'audio';
  String lastMode = 'audio';

  // In-call / text chat (messages are only relayed by the server, never stored).
  final List<ChatMessage> chatMessages = [];
  int unreadChat = 0;
  bool chatOpen = false;
  int queuePosition = 0;
  bool show5MinWarning = false;
  int guestRemainingSeconds = 3600;

  // Ad settings (defaults; overridden by the server's /api/config when available)
  bool adsBannerEnabled = true;
  bool adsInterstitialEnabled = true;
  bool adsRewardedEnabled = true;
  int interstitialCooldownSeconds = AdConfig.defaultInterstitialCooldownSeconds;
  bool _rewardInProgress = false;
  bool get rewardInProgress => _rewardInProgress;

  final SocketService socketService = SocketService();
  final WebRtcService webrtcService = WebRtcService();
  final GuestService guestService = GuestService();
  final AdService adService = AdService();
  final BillingService billingService = BillingService();

  // Backend URL. For release builds pass your HTTPS server:
  //   flutter build appbundle --release --dart-define=BACKEND_URL=https://your-domain.com
  // (10.0.2.2 is only the Android emulator's address for your PC.)
  String backendUrl = const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://10.0.2.2:3000');

  /// Signed session token from the server. Sent with every request; the server
  /// decides who you are from it (never from the request body).
  String? authToken;
  bool sessionExpired = false;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  // Short messages for the UI (purchase results etc.)
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;
  void _say(String m) => _messageController.add(m);

  Future<void> initApp() async {
    await adService.init();
    await _loadRemoteAdConfig();
    await billingService.init();

    // Billing: coins are granted by the server after Google verifies the purchase.
    billingService.onPurchaseVerified = _verifyPurchaseWithServer;
    billingService.onMessage = _say;
    socketService.onAuthError = () {
      sessionExpired = true;
      notifyListeners();
    };

    // Socket Event listeners
    socketService.onMatched = _handleMatched;
    socketService.onChatMessage = _handleChatMessage;
    socketService.onQueueStatus = _handleQueueStatus;
    socketService.onCallEnded = _handleCallEnded;
    socketService.onGuestExpired = (msg) => _handleGuestExpired();
    socketService.onWebRtcOffer = _handleRemoteOffer;
    socketService.onWebRtcAnswer = _handleRemoteAnswer;
    socketService.onWebRtcIceCandidate = _handleRemoteCandidate;

    // WebRTC Candidate listener
    webrtcService.onIceCandidate = (candidate) {
      if (activeCall != null) {
        socketService.sendIceCandidate(activeCall!.roomId, candidate.toMap());
      }
    };

    // Is the call really connected / did it fail?
    webrtcService.onConnectionStateChange = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _failCall('The connection was lost. Please try again.');
      }
    };
    webrtcService.onIceConnectionStateChange = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _failCall('The connection was lost. Please try again.');
      }
    };

    // Messages from the server (admin tools, coins, forced sign-out)
    socketService.onAdminBroadcast = (message) {
      broadcastMessage = message;
      notifyListeners();
    };
    socketService.onWalletUpdated = (coins) {
      if (currentUser != null) {
        currentUser!.coins = coins;
        notifyListeners();
      }
    };
    socketService.onGiftReceived = _handleGiftReceived;
    socketService.onAccountNotice = _handleAccountNotice;
    socketService.onTermsRequired = () {
      // The server says the Terms were not accepted (or changed): show the Terms page again.
      if (currentUser != null) {
        currentUser!.termsAccepted = false;
        isSearching = false;
        notifyListeners();
      }
    };
  }

  Future<void> _loadRemoteAdConfig() async {
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/api/config'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final settings = (jsonDecode(res.body)['settings'] ?? {}) as Map<String, dynamic>;
      adsBannerEnabled = settings['ads_banner_enabled'] ?? adsBannerEnabled;
      adsInterstitialEnabled = settings['ads_interstitial_enabled'] ?? adsInterstitialEnabled;
      adsRewardedEnabled = settings['ads_rewarded_enabled'] ?? adsRewardedEnabled;
      interstitialCooldownSeconds =
          (settings['interstitial_cooldown_seconds'] ?? interstitialCooldownSeconds) as int;
      notifyListeners();
    } catch (_) {
      // Keep defaults if the server has no config endpoint or is unreachable.
    }
  }

  // 1. Enter as Guest. Returns null on success, or a message to show the user.
  Future<String?> loginAsGuest() async {
    final result = await guestService.startSession(backendUrl);
    if (result.expired) {
      return result.error ?? 'Your free guest time is used up. Please sign up to continue.';
    }
    if (!result.ok) return result.error ?? 'Could not start. Please try again.';

    authToken = result.token;
    sessionExpired = false;
    currentUser = UserModel.guest(result.sessionId!, result.expiresAt!, termsAccepted: result.termsAccepted);
    guestRemainingSeconds = currentUser!.guestRemainingSeconds;

    guestService.onTick = (remaining) {
      guestRemainingSeconds = remaining;
      notifyListeners();
    };
    guestService.onWarning5Min = () {
      show5MinWarning = true;
      notifyListeners();
    };
    guestService.onExpired = () {
      _handleGuestExpired();
    };
    guestService.startCountdown(result.expiresAt!);

    socketService.init(url: backendUrl, token: authToken!);
    socketService.registerClient(userId: currentUser!.userId, isGuest: true);
    unawaited(_refreshIceServers());

    notifyListeners();
    return null;
  }

  /// Switches the app to a signed-in (non-guest) session from a server login response.
  void _startRegisteredSession(Map<String, dynamic> data) {
    currentUser = UserModel.fromJson(data['user']);
    authToken = data['token'] as String?;
    sessionExpired = false;
    guestService.stop();
    show5MinWarning = false;

    socketService.init(url: backendUrl, token: authToken ?? '');
    socketService.registerClient(userId: currentUser!.userId, isGuest: false);
    unawaited(_refreshIceServers());
    unawaited(billingService.checkPendingPurchases()); // retry paid-but-uncredited purchases
    notifyListeners();
  }

  // ---------------- Google Sign-In ----------------
  GoogleSignIn? _googleSignIn;
  String? _pendingGoogleIdToken;

  GoogleSignIn get _gsi => _googleSignIn ??=
      GoogleSignIn(scopes: const ['email'], serverClientId: AuthConfig.googleWebClientId);

  /// Step 1: pick a Google account. Existing accounts are signed in directly
  /// (on any device); new ones must choose a username next.
  Future<GoogleSignInResult> signInWithGoogle() async {
    if (AuthConfig.googleWebClientId.isEmpty) {
      return const GoogleSignInResult(GoogleOutcome.error, message: 'Google Sign-In is not set up in this build yet.');
    }
    try {
      try {
        await _gsi.signOut(); // always show the account chooser
      } catch (_) {}
      final account = await _gsi.signIn();
      if (account == null) return const GoogleSignInResult(GoogleOutcome.cancelled);
      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        return const GoogleSignInResult(GoogleOutcome.error, message: 'Google did not return a sign-in token. Please try again.');
      }
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (data['needsUsername'] == true) {
          _pendingGoogleIdToken = idToken;
          return GoogleSignInResult(GoogleOutcome.needsUsername, suggestedName: data['suggestedName']?.toString());
        }
        _pendingGoogleIdToken = null;
        _startRegisteredSession(data);
        return const GoogleSignInResult(GoogleOutcome.signedIn);
      }
      return GoogleSignInResult(GoogleOutcome.error, message: data['error']?.toString() ?? 'Google sign-in failed.');
    } catch (e) {
      debugPrint('[GOOGLE] sign-in error: $e');
      return const GoogleSignInResult(GoogleOutcome.error,
          message: 'Google sign-in failed. Check your internet connection and try again.');
    }
  }

  /// Step 2 (new Google accounts only): create the account with the chosen username.
  Future<Map<String, dynamic>> completeGoogleSignUp({
    required String username,
    required String displayName,
  }) async {
    final idToken = _pendingGoogleIdToken;
    if (idToken == null) return {'success': false, 'message': 'Please sign in with Google again.'};
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken, 'username': username, 'displayName': displayName}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true && data['user'] != null) {
        _pendingGoogleIdToken = null;
        _startRegisteredSession(data);
        return {'success': true};
      }
      if (res.statusCode == 401) _pendingGoogleIdToken = null; // token expired: start over
      return {'success': false, 'message': data['error']?.toString() ?? 'Could not create the account.'};
    } catch (_) {
      return {'success': false, 'message': 'Could not reach the server. Please try again.'};
    }
  }

  // ---------------- Email OTP sign-in (code sent by the server through SMTP) ----------------
  String? _pendingOtpTicket;

  /// Step 1: ask the server to email a 6-digit code.
  Future<OtpResult> requestEmailOtp(String email) async {
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/auth/otp/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'channel': 'email', 'target': email.trim()}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        return OtpResult(OtpOutcome.sent, cooldownSeconds: (data['cooldownSeconds'] as num?)?.toInt() ?? 45);
      }
      return OtpResult(
        OtpOutcome.error,
        message: data['error']?.toString() ?? 'Could not send the code.',
        cooldownSeconds: (data['retryAfter'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const OtpResult(OtpOutcome.error, message: 'Could not reach the server. Please try again.');
    }
  }

  /// Step 2: check the code. Existing account -> signed in. New email -> choose a username next.
  Future<OtpResult> verifyEmailOtp(String email, String code) async {
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/auth/otp/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'channel': 'email', 'target': email.trim(), 'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (data['needsUsername'] == true) {
          _pendingOtpTicket = data['ticket']?.toString();
          return const OtpResult(OtpOutcome.needsUsername);
        }
        _pendingOtpTicket = null;
        _startRegisteredSession(data);
        return const OtpResult(OtpOutcome.signedIn);
      }
      return OtpResult(OtpOutcome.error, message: data['error']?.toString() ?? 'Wrong code. Please try again.');
    } catch (_) {
      return const OtpResult(OtpOutcome.error, message: 'Could not reach the server. Please try again.');
    }
  }

  /// Step 3 (new email only): create the account with the chosen username.
  Future<Map<String, dynamic>> completeOtpSignUp({
    required String username,
    required String displayName,
  }) async {
    final ticket = _pendingOtpTicket;
    if (ticket == null) return {'success': false, 'message': 'Please verify your email again.'};
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/auth/otp/complete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ticket': ticket, 'username': username, 'displayName': displayName}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true && data['user'] != null) {
        _pendingOtpTicket = null;
        _startRegisteredSession(data);
        return {'success': true};
      }
      final msg = data['error']?.toString() ?? 'Could not create the account.';
      if (msg.toLowerCase().contains('expired')) _pendingOtpTicket = null;
      return {'success': false, 'message': msg};
    } catch (_) {
      return {'success': false, 'message': 'Could not reach the server. Please try again.'};
    }
  }

  // 2. Register Permanent User
  Future<Map<String, dynamic>> registerPermanentUser({
    required String username,
    required String displayName,
    String? email,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'displayName': displayName,
          'email': email ?? '',
        }),
      );

      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        _startRegisteredSession(data);
        return {'success': true};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Could not connect to server'};
    }
  }

  // 3. Username Availability Check
  Future<Map<String, dynamic>> checkUsernameAvailability(String username) async {
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/api/username/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'valid': false, 'message': 'Network error checking username'};
    }
  }

  // 4. Start Matchmaking (Random Call)
  void startRandomCall({String mode = 'audio'}) {
    if (currentUser == null) return;
    if (currentUser!.isGuest && currentUser!.isGuestExpired) {
      _handleGuestExpired();
      return;
    }

    searchMode = mode;
    lastMode = mode;
    isSearching = true;
    notifyListeners();

    socketService.joinQueue(
      mode: mode,
      userId: currentUser!.userId,
      displayName: currentUser!.displayName,
      avatarUrl: currentUser!.avatarUrl,
      isGuest: currentUser!.isGuest,
      sessionId: currentUser!.isGuest ? currentUser!.userId : null,
    );
  }

  /// Signs out on this device: stops timers, closes the socket, clears the session.
  void logout() {
    if (activeCall != null) endCall();
    if (isSearching) cancelSearch();
    guestService.stop();
    socketService.dispose();
    authToken = null;
    currentUser = null;
    show5MinWarning = false;
    broadcastMessage = null;
    notifyListeners();
  }

  void cancelSearch() {
    isSearching = false;
    socketService.leaveQueue();
    notifyListeners();
  }

  // 5. Matchmaking Found Handler
  // ---------------- Call setup state (guards against the races described below) ----------------
  int _callGen = 0;                         // changes for every call; old async work stops when it differs
  bool _pcReady = false;                    // our peer connection exists
  bool _remoteDescSet = false;              // the other side's offer/answer has been applied
  Map<String, dynamic>? _pendingOffer;      // offer that arrived before our peer connection was ready
  final List<Map<String, dynamic>> _pendingCandidates = []; // ICE candidates that arrived too early
  Future<void>? _cleanupFuture;             // the previous call's teardown
  Timer? _connectTimer;
  String? endReason;                        // shown on the "conversation ended" screen
  String? broadcastMessage;                 // message from the admin
  String? forcedLogoutNotice;               // set when the server signs us out (suspended / deleted)

  bool _alive(int gen) => gen == _callGen && activeCall != null;

  void _resetSignalling() {
    _pcReady = false;
    _remoteDescSet = false;
    _pendingOffer = null;
    _pendingCandidates.clear();
  }

  void _markConnected() {
    _connectTimer?.cancel();
    final call = activeCall;
    if (call != null && !call.isConnected) {
      call.isConnected = true;
      notifyListeners();
    }
  }

  /// The call cannot work: end it and tell the person why.
  void _failCall(String reason) {
    if (activeCall == null) return;
    debugPrint('[CALL] failed: $reason');
    endReason = reason;
    endCall();
  }

  Future<void> _handleMatched(Map<String, dynamic> data) async {
    isSearching = false;
    final gen = ++_callGen;
    _connectTimer?.cancel();
    _resetSignalling();
    endReason = null;
    final roomId = data['roomId'];
    final bool isInitiator = data['isInitiator'] ?? false;
    final stranger = data['stranger'] ?? {};
    final String mode = (data['mode'] == 'video' || data['mode'] == 'text') ? data['mode'] as String : 'audio';
    chatMessages.clear();
    unreadChat = 0;
    chatOpen = false;
    lastMode = mode;

    activeCall = CallSession(
      roomId: roomId,
      strangerId: stranger['id'] ?? 'stranger',
      strangerName: stranger['displayName'] ?? 'Stranger',
      strangerAvatar: stranger['avatarUrl'] ?? '',
      isInitiator: isInitiator,
      startedAt: DateTime.now(),
      mode: mode,
    );

    notifyListeners();

    // Text chat needs no media at all: the server just relays the messages.
    if (mode == 'text') return;

    // Wait for the previous call to be fully closed, then fresh (short-lived) TURN credentials.
    await _cleanupFuture;
    if (!_alive(gen)) return;
    await _refreshIceServers();
    if (!_alive(gen)) return;

    // Microphone (and camera for video).
    final gotMic = await webrtcService.initMedia(video: mode == 'video');
    if (!_alive(gen)) {
      await webrtcService.cleanUp(); // the call ended while we were opening the mic / camera
      return;
    }
    if (!gotMic) {
      _failCall('The microphone is not available. Allow microphone access in your phone settings.');
      return;
    }
    notifyListeners(); // camera is ready: show the local preview

    final created = await webrtcService.createPeerConnectionInstance();
    if (!_alive(gen)) {
      await webrtcService.cleanUp();
      return;
    }
    if (!created) {
      _failCall('Could not start the call on this phone.');
      return;
    }
    _pcReady = true;

    // If nobody connects within 30 seconds, give up instead of hanging forever.
    _connectTimer = Timer(const Duration(seconds: 30), () {
      if (_alive(gen) && !(activeCall?.isConnected ?? false)) {
        _failCall('Could not connect. Check your internet connection and try again.');
      }
    });

    try {
      if (isInitiator) {
        final offer = await webrtcService.createOffer();
        if (!_alive(gen)) return;
        socketService.sendOffer(roomId, offer.toMap());
      } else if (_pendingOffer != null) {
        // The other phone was faster: its offer arrived while we were still getting ready.
        final early = _pendingOffer!;
        _pendingOffer = null;
        await _applyOffer(early, gen);
      }
    } catch (e) {
      debugPrint('[CALL] setup error: $e');
      if (_alive(gen)) _failCall('Could not start the call. Please try again.');
    }
  }

  // 6. WebRTC Handlers
  Future<void> _handleRemoteOffer(Map<String, dynamic> data) async {
    final call = activeCall;
    if (call == null || call.mode == 'text') return;
    if (!_pcReady) {
      _pendingOffer = data; // keep it until our peer connection exists
      return;
    }
    await _applyOffer(data, _callGen);
  }

  Future<void> _applyOffer(Map<String, dynamic> data, int gen) async {
    try {
      final sdp = data['sdp'];
      await webrtcService.setRemoteDescription(sdp['sdp'], sdp['type']);
      if (!_alive(gen)) return;
      _remoteDescSet = true;
      await _flushCandidates(gen);
      final answer = await webrtcService.createAnswer();
      if (!_alive(gen)) return;
      socketService.sendAnswer(activeCall!.roomId, answer.toMap());
    } catch (e) {
      debugPrint('[CALL] could not apply offer: $e');
      if (_alive(gen)) _failCall('Could not start the call. Please try again.');
    }
  }

  Future<void> _handleRemoteAnswer(Map<String, dynamic> data) async {
    if (activeCall == null || !_pcReady) return;
    final gen = _callGen;
    try {
      final sdp = data['sdp'];
      await webrtcService.setRemoteDescription(sdp['sdp'], sdp['type']);
      if (!_alive(gen)) return;
      _remoteDescSet = true;
      await _flushCandidates(gen);
    } catch (e) {
      debugPrint('[CALL] could not apply answer: $e');
      if (_alive(gen)) _failCall('Could not start the call. Please try again.');
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> data) async {
    final candidate = data['candidate'];
    if (candidate is! Map || activeCall == null) return;
    final c = Map<String, dynamic>.from(candidate);
    if (!_remoteDescSet) {
      _pendingCandidates.add(c); // adding a candidate before the offer/answer is applied would fail
      return;
    }
    await _addCandidateSafely(c);
  }

  Future<void> _flushCandidates(int gen) async {
    final waiting = List<Map<String, dynamic>>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in waiting) {
      if (!_alive(gen)) return;
      await _addCandidateSafely(c);
    }
  }

  Future<void> _addCandidateSafely(Map<String, dynamic> c) async {
    try {
      await webrtcService.addCandidate(c);
    } catch (e) {
      debugPrint('[CALL] ignoring a bad ICE candidate: $e');
    }
  }

  void _handleQueueStatus(Map<String, dynamic> data) {
    queuePosition = data['queuePosition'] ?? 1;
    notifyListeners();
  }

  // 7. Call Controls
  void toggleMute() {
    webrtcService.toggleMute();
    activeCall?.isMuted = webrtcService.isMuted;
    notifyListeners();
  }

  // ---------------- Chat ----------------
  /// Sends a chat message to the stranger (text chat, or during an audio / video call).
  void sendChat(String raw) {
    final call = activeCall;
    final text = raw.trim();
    if (call == null || text.isEmpty) return;
    final clipped = text.length > 500 ? text.substring(0, 500) : text;
    socketService.sendChat(call.roomId, clipped);
    chatMessages.add(ChatMessage(text: clipped, mine: true));
    notifyListeners();
  }

  void _handleChatMessage(Map<String, dynamic> data) {
    if (activeCall == null) return;
    final text = data['text'];
    if (text is! String || text.isEmpty) return;
    chatMessages.add(ChatMessage(text: text, mine: false));
    if (!chatOpen) unreadChat++;
    notifyListeners();
  }

  /// Call when the chat panel opens/closes so unread badges stay correct.
  void setChatOpen(bool open) {
    chatOpen = open;
    if (open) unreadChat = 0;
    notifyListeners();
  }

  void toggleCamera() {
    webrtcService.toggleCamera();
    activeCall?.isCameraOff = webrtcService.cameraOff;
    notifyListeners();
  }

  Future<void> switchCamera() => webrtcService.switchCamera();

  void toggleSpeaker() {
    webrtcService.toggleSpeaker();
    activeCall?.isSpeakerOn = webrtcService.isSpeakerOn;
    notifyListeners();
  }

  void endCall() {
    if (activeCall != null) {
      socketService.endCall(activeCall!.roomId);
      _terminateCallCleanup();
    }
  }

  void skipToNextStranger() {
    if (activeCall != null) {
      final mode = activeCall!.mode;
      socketService.skipCall(activeCall!.roomId);
      _terminateCallCleanup(showInterstitial: false);
      // Rejoin the same kind of queue immediately
      startRandomCall(mode: mode);
    }
  }

  void _handleCallEnded(String reason) {
    endReason = reason;
    _terminateCallCleanup();
  }

  /// The "conversation ended" screen asks for the reason once.
  String? takeEndReason() {
    final r = endReason;
    endReason = null;
    return r;
  }

  void clearBroadcast() {
    broadcastMessage = null;
    notifyListeners();
  }

  String? takeLogoutNotice() {
    final r = forcedLogoutNotice;
    forcedLogoutNotice = null;
    return r;
  }

  /// The server ended our session (account suspended or deleted).
  void _handleAccountNotice(String reason) {
    if (currentUser == null) return;
    forcedLogoutNotice = reason;
    logout();
  }

  // ---------------- Terms and Conditions ----------------
  /// The person ticked the box and pressed "Accept". Returns null on success, else a message to show.
  Future<String?> acceptTerms() async {
    final user = currentUser;
    if (user == null) return 'Please sign in again.';
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/terms/accept'),
            headers: _authHeaders,
            body: jsonEncode({'version': TermsText.version}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        user.termsAccepted = true;
        notifyListeners();
        return null;
      }
      if (res.statusCode == 401) {
        _handleAccountNotice('Please sign in again.');
        return null;
      }
      return data['error']?.toString() ?? 'Could not save your choice. Please try again.';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ---------------- Account ----------------
  // ---------------- Virtual gifts + wallet history ----------------

  List<Gift> gifts = List<Gift>.of(Gift.defaults);
  List<WalletTx> walletHistory = [];
  bool walletHistoryLoading = false;
  bool walletHistoryFailed = false;

  final StreamController<GiftEvent> _giftController = StreamController<GiftEvent>.broadcast();

  /// Gifts to animate on the call screens (sent by us, or received from the stranger).
  Stream<GiftEvent> get giftEvents => _giftController.stream;

  // A gift request that timed out keeps its id, so tapping Send again is a retry of the SAME
  // gift: the server answers "duplicate" instead of charging twice.
  String? _pendingGiftId;
  String? _pendingGiftRequestId;
  bool giftSending = false;

  String _newRequestId() {
    final r = Random.secure();
    final tail = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$tail';
  }

  Gift? giftById(String id) {
    for (final g in gifts) {
      if (g.id == id) return g;
    }
    for (final g in Gift.defaults) {
      if (g.id == id) return g;
    }
    return null;
  }

  Future<void> loadGifts() async {
    if (authToken == null) return;
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/api/gifts'), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body)['gifts'];
        if (list is List && list.isNotEmpty) {
          gifts = list.map((e) => Gift.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          notifyListeners();
        }
      }
    } catch (_) {
      // offline: keep the built-in list (the server still decides the real price)
    }
  }

  Future<void> loadWalletHistory() async {
    final user = currentUser;
    if (user == null || user.isGuest || authToken == null) return;
    walletHistoryLoading = true;
    walletHistoryFailed = false;
    notifyListeners();
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/api/wallet/transactions?limit=40'), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['transactions'] as List? ?? []);
        walletHistory = list.map((e) => WalletTx.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (body['balance'] is num) user.coins = (body['balance'] as num).toInt();
      } else {
        walletHistoryFailed = true;
      }
    } catch (_) {
      walletHistoryFailed = true;
    }
    walletHistoryLoading = false;
    notifyListeners();
  }

  /// Sends [gift] to the stranger in the current call. The SERVER checks the call, the
  /// price and the balance, and deducts the coins; we only update the UI from its answer.
  Future<GiftSendResult> sendGift(Gift gift) async {
    final user = currentUser;
    final call = activeCall;
    if (user == null || authToken == null) return const GiftSendResult.failure('Please sign in again.');
    if (user.isGuest) return const GiftSendResult.failure('Sign up with a username to send gifts.');
    if (call == null) return const GiftSendResult.failure('Gifts can be sent during a call.');
    if (giftSending) return const GiftSendResult.failure('Sending your gift...');

    if (_pendingGiftId != gift.id || _pendingGiftRequestId == null) {
      _pendingGiftId = gift.id;
      _pendingGiftRequestId = _newRequestId();
    }
    giftSending = true;
    notifyListeners();
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/gifts/send'),
            headers: _authHeaders,
            body: jsonEncode({'roomId': call.roomId, 'giftId': gift.id, 'requestId': _pendingGiftRequestId}),
          )
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}

      if (res.statusCode == 200) {
        _pendingGiftId = null;
        _pendingGiftRequestId = null;
        if (body['newBalance'] is num) user.coins = (body['newBalance'] as num).toInt();
        if (body['duplicate'] != true) {
          _giftController.add(GiftEvent(gift: gift, received: false));
        }
        return const GiftSendResult.success();
      }

      // The server gave a definite answer, so the next tap is a brand-new gift.
      _pendingGiftId = null;
      _pendingGiftRequestId = null;
      if (body['newBalance'] is num) user.coins = (body['newBalance'] as num).toInt();
      if (res.statusCode == 402) {
        if (body['balance'] is num) user.coins = (body['balance'] as num).toInt();
        return GiftSendResult.failure(
          'Not enough coins. You need ${gift.price} coins.',
          notEnoughCoins: true,
          needed: gift.price,
        );
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return GiftSendResult.failure((body['error'] ?? 'Please sign in again.').toString());
      }
      return GiftSendResult.failure((body['error'] ?? 'Could not send the gift. No coins were charged.').toString());
    } catch (_) {
      // Timeout / no network: we do NOT know if the server accepted it. Keep the request id so a
      // retry cannot charge twice, and refresh the balance from the server.
      refreshProfile();
      return const GiftSendResult.failure('No connection. Your coins are safe. Tap Send to try again.');
    } finally {
      giftSending = false;
      notifyListeners();
    }
  }

  void _handleGiftReceived(Map<String, dynamic> data) {
    if (activeCall == null) return;
    final id = (data['giftId'] ?? '').toString();
    final gift = giftById(id) ??
        Gift(id: id, name: (data['name'] ?? 'Gift').toString(), price: 0, animation: (data['animation'] ?? 'pop').toString());
    _giftController.add(GiftEvent(gift: gift, received: true, fromName: (data['fromName'] ?? '').toString()));
  }

  /// Fresh coins / profile from the server (an admin may have changed them).
  Future<void> refreshProfile() async {
    final user = currentUser;
    if (user == null || user.isGuest || authToken == null) return;
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/api/me'), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final u = jsonDecode(res.body)['user'];
        if (u is Map && u['coins'] is num) {
          user.coins = (u['coins'] as num).toInt();
          if (u.containsKey('termsAccepted')) user.termsAccepted = u['termsAccepted'] == true;
          notifyListeners();
        }
      } else if (res.statusCode == 403) {
        _handleAccountNotice('Your account has been suspended.');
      } else if (res.statusCode == 401) {
        _handleAccountNotice('Please sign in again.');
      }
    } catch (_) {
      // offline: keep what we have
    }
  }

  /// Permanently deletes the account on the server. Returns null on success, else a message to show.
  Future<String?> deleteAccount() async {
    final user = currentUser;
    if (user == null) return null;
    if (user.isGuest) {
      logout();
      return null;
    }
    try {
      final req = http.Request('DELETE', Uri.parse('$backendUrl/api/account'))
        ..headers.addAll(_authHeaders)
        ..body = jsonEncode({'confirm': 'DELETE'});
      final streamed = await req.send().timeout(const Duration(seconds: 20));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200 || res.statusCode == 401) {
        logout(); // 401 = the account is already gone
        return null;
      }
      final data = jsonDecode(res.body);
      return data['error']?.toString() ?? 'Could not delete the account. Please try again.';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  void _terminateCallCleanup({bool showInterstitial = true}) {
    final hadCall = activeCall != null;
    _callGen++; // stops any call setup that is still running
    _connectTimer?.cancel();
    _resetSignalling();
    _cleanupFuture = webrtcService.cleanUp();
    activeCall = null;
    chatMessages.clear();
    unreadChat = 0;
    chatOpen = false;
    notifyListeners();
    // Natural break: show an interstitial after a call ends, subject to the
    // admin switch and the cooldown (never between back-to-back skips).
    if (hadCall && showInterstitial) {
      adService.maybeShowInterstitial(
        enabled: adsInterstitialEnabled,
        cooldownSeconds: interstitialCooldownSeconds,
      );
    }
  }

  void _handleGuestExpired() {
    isSearching = false;
    _terminateCallCleanup(showInterstitial: false);
    notifyListeners();
  }

  // 8. Safety & Moderation (Play Store UGC compliance). The server knows who you
  // are from your token and only accepts reports about people you actually spoke to.
  Future<void> blockUser(String strangerId) async {
    try {
      await http
          .post(
            Uri.parse('$backendUrl/api/safety/block'),
            headers: _authHeaders,
            body: jsonEncode({'blockedUserId': strangerId}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> reportUser({
    required String strangerId,
    required String category,
    required String description,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$backendUrl/api/safety/report'),
            headers: _authHeaders,
            body: jsonEncode({
              'reportedUserId': strangerId,
              'category': category,
              'description': description,
              'callId': activeCall?.roomId,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _refreshIceServers() async {
    if (authToken == null) return;
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/api/ice-servers'), headers: _authHeaders)
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['iceServers'] as List?) ?? [];
        webrtcService.setIceServers(list);
      }
    } catch (_) {
      // Keep the STUN-only defaults if the server can't be reached.
    }
  }

  // 9. Coin Wallet Actions
  /// Opens the Google Play purchase sheet. Coins arrive only after the server
  /// verifies the purchase with Google. Returns a message on failure, null if launched.
  Future<String?> startPurchase(String productId) async {
    final user = currentUser;
    if (user == null || authToken == null) return 'Please sign in first.';
    if (user.isGuest) return 'Sign up with a username to buy coins.';
    return billingService.buyPack(productId);
  }

  /// Sends a Play purchase to the server. Returns true when the purchase can be
  /// completed (server credited it, already had it, or definitively rejected it);
  /// false to keep it pending and retry on the next app start.
  Future<bool> _verifyPurchaseWithServer(PurchaseDetails purchase) async {
    final user = currentUser;
    if (user == null || user.isGuest || authToken == null) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/wallet/purchase'),
            headers: _authHeaders,
            body: jsonEncode({
              'productId': purchase.productID,
              'purchaseToken': purchase.verificationData.serverVerificationData,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        user.coins = (data['newBalance'] ?? user.coins) as int;
        notifyListeners();
        final added = (data['coinsAdded'] ?? 0) as int;
        if (added > 0) _say('Purchase complete! +$added coins');
        return true;
      }
      if (res.statusCode == 402 || res.statusCode == 409) {
        _say(data['error']?.toString() ?? 'Purchase could not be verified.');
        return true; // nothing to credit; safe to close it out
      }
      _say('We are still confirming your purchase. Your coins will appear shortly.');
      return false;
    } catch (_) {
      _say('We are still confirming your purchase. Your coins will appear shortly.');
      return false;
    }
  }

  /// Rewarded ad -> coins. Coins are credited by the SERVER after Google's
  /// server-side verification; this method only shows the ad and reads the result.
  /// Returns a message for the UI.
  Future<String> watchRewardedAdForCoins() async {
    final user = currentUser;
    if (user == null) return 'Please sign in first.';
    if (user.isGuest) return 'Sign in with a username to earn coins from ads.';
    if (!adsRewardedEnabled) return 'Rewarded ads are unavailable right now.';
    if (_rewardInProgress) return 'Please wait...';
    if (!adService.isRewardedReady) {
      adService.loadRewardedAd();
      return 'No ad is available right now. Please try again in a moment.';
    }

    _rewardInProgress = true;
    notifyListeners();
    try {
      final nonceResult = await _requestRewardNonce(user.userId);
      if (nonceResult.nonce == null) {
        return nonceResult.error ?? 'Could not start the reward. Check your connection.';
      }
      final nonce = nonceResult.nonce!;

      final outcome = await adService.showRewardedAd(userId: user.userId, nonce: nonce);
      switch (outcome) {
        case RewardedAdOutcome.notReady:
          return 'No ad is available right now. Please try again in a moment.';
        case RewardedAdOutcome.error:
          return 'The ad could not be shown. Please try again.';
        case RewardedAdOutcome.dismissed:
          return 'Watch the whole video to earn coins.';
        case RewardedAdOutcome.rewarded:
          // Google's verification call reaches our server within a few seconds.
          for (var i = 0; i < 10; i++) {
            final status = await _rewardStatus(user.userId, nonce);
            if (status != null && status['credited'] == true) {
              user.coins = (status['newBalance'] ?? user.coins) as int;
              notifyListeners();
              return 'You earned ${status['coinsEarned'] ?? 10} coins!';
            }
            await Future.delayed(const Duration(milliseconds: 1500));
          }
          return 'Reward is being verified. Your coins will appear shortly.';
      }
    } finally {
      _rewardInProgress = false;
      notifyListeners();
    }
  }

  Future<({String? nonce, String? error})> _requestRewardNonce(String userId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/ads/reward-nonce'),
            headers: _authHeaders,
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        return (nonce: data['nonce'] as String, error: null);
      }
      return (nonce: null, error: data['error']?.toString());
    } catch (_) {
      return (nonce: null, error: null);
    }
  }

  Future<Map<String, dynamic>?> _rewardStatus(String userId, String nonce) async {
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/ads/reward-status'),
            headers: _authHeaders,
            body: jsonEncode({'nonce': nonce}),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
