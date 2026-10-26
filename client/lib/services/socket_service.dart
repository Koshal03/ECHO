import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  // Default emulator host is 10.0.2.2; on real device use LAN IP or your deployed cloud server domain
  String serverUrl = 'http://10.0.2.2:3000';

  Function(Map<String, dynamic>)? onMatched;
  Function(Map<String, dynamic>)? onQueueStatus;
  Function(String reason)? onCallEnded;
  Function(String message)? onGuestExpired;
  Function(Map<String, dynamic>)? onWebRtcOffer;
  Function(Map<String, dynamic>)? onWebRtcAnswer;
  Function(Map<String, dynamic>)? onWebRtcIceCandidate;
  Function(Map<String, dynamic>)? onChatMessage;
  Function(String message)? onAdminBroadcast;
  Function(int coins)? onWalletUpdated;
  Function(String reason)? onAccountNotice;
  Function()? onTermsRequired;
  Function()? onAuthError;

  bool get isConnected => socket?.connected ?? false;

  void init({required String url, required String token}) {
    serverUrl = url;
    try {
      // Drop any previous connection (e.g. guest -> registered) so we never leak sockets.
      socket?.dispose();
      socket = IO.io(
        serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token}) // the server derives who you are from this token
            .disableAutoConnect()
            .build(),
      );

      socket?.onConnectError((err) {
        debugPrint('[SOCKET] connect error: $err');
        if ('$err'.contains('unauthorized')) onAuthError?.call();
        if ('$err'.contains('suspended')) onAccountNotice?.call('Your account has been suspended.');
      });

      socket?.onConnect((_) {
        debugPrint('[SOCKET] Connected to $serverUrl');
      });

      socket?.onDisconnect((_) {
        debugPrint('[SOCKET] Disconnected');
      });

      socket?.on('matched', (data) {
        if (data is Map<String, dynamic>) {
          onMatched?.call(data);
        }
      });

      socket?.on('queue-status', (data) {
        if (data is Map<String, dynamic>) {
          onQueueStatus?.call(data);
        }
      });

      socket?.on('call-ended', (data) {
        final reason = (data is Map && data['reason'] != null) ? data['reason'] : 'Call ended';
        onCallEnded?.call(reason);
      });

      socket?.on('guest-expired', (data) {
        final msg = (data is Map && data['message'] != null) ? data['message'] : 'Guest limit reached';
        onGuestExpired?.call(msg);
      });

      socket?.on('chat-message', (data) {
        if (data is Map) onChatMessage?.call(Map<String, dynamic>.from(data));
      });

      socket?.on('admin-broadcast', (data) {
        if (data is Map && data['message'] != null) onAdminBroadcast?.call(data['message'].toString());
      });

      socket?.on('wallet-updated', (data) {
        if (data is Map && data['coins'] is num) onWalletUpdated?.call((data['coins'] as num).toInt());
      });

      socket?.on('terms-required', (_) {
        onTermsRequired?.call();
      });

      socket?.on('account-notice', (data) {
        final reason = (data is Map && data['reason'] != null) ? data['reason'].toString() : 'Disconnected';
        onAccountNotice?.call(reason);
      });

      socket?.on('webrtc-offer', (data) {
        if (data is Map<String, dynamic>) onWebRtcOffer?.call(data);
      });

      socket?.on('webrtc-answer', (data) {
        if (data is Map<String, dynamic>) onWebRtcAnswer?.call(data);
      });

      socket?.on('webrtc-ice-candidate', (data) {
        if (data is Map<String, dynamic>) onWebRtcIceCandidate?.call(data);
      });

      socket?.connect();
    } catch (e) {
      debugPrint('[SOCKET ERROR] $e');
    }
  }

  void registerClient({required String userId, required bool isGuest, String? sessionId}) {
    // Identity comes from the auth token; the payload is intentionally empty.
    socket?.emit('register-client', {});
  }

  void joinQueue({
    required String userId,
    required String displayName,
    required String avatarUrl,
    required bool isGuest,
    String? sessionId,
    String mode = 'audio', // 'audio' | 'video' | 'text'
  }) {
    // Identity comes from the auth token; only the mode is sent.
    socket?.emit('join-queue', {'mode': mode});
  }

  void sendChat(String roomId, String text) {
    socket?.emit('chat-message', {'roomId': roomId, 'text': text});
  }

  void leaveQueue() {
    socket?.emit('leave-queue');
  }

  void sendOffer(String roomId, dynamic sdp) {
    socket?.emit('webrtc-offer', {'roomId': roomId, 'sdp': sdp});
  }

  void sendAnswer(String roomId, dynamic sdp) {
    socket?.emit('webrtc-answer', {'roomId': roomId, 'sdp': sdp});
  }

  void sendIceCandidate(String roomId, dynamic candidate) {
    socket?.emit('webrtc-ice-candidate', {'roomId': roomId, 'candidate': candidate});
  }

  void endCall(String roomId, [String? reason]) {
    socket?.emit('end-call', {'roomId': roomId, 'reason': reason});
  }

  void skipCall(String roomId) {
    socket?.emit('skip-call', {'roomId': roomId});
  }

  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}
