import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Result of asking the server for a guest session.
class GuestSessionResult {
  final String? sessionId;
  final String? token;
  final DateTime? expiresAt;
  final bool expired;
  final String? error;
  final bool termsAccepted;
  const GuestSessionResult({this.sessionId, this.token, this.expiresAt, this.expired = false, this.error, this.termsAccepted = false});
  bool get ok => sessionId != null && token != null && expiresAt != null;
}

/// Guest access is enforced by the SERVER (one 60-minute allowance per device).
/// The phone only shows a countdown; it can't grant itself more time.
class GuestService {
  static const String KEY_DEVICE_ID = 'echo_device_id';

  Timer? _ticker;
  Function(int remainingSeconds)? onTick;
  Function()? onWarning5Min;
  Function()? onExpired;

  bool _warningTriggered = false;

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(KEY_DEVICE_ID);
    if (id == null || id.length < 8) {
      final rnd = Random.secure();
      id = List.generate(24, (_) => rnd.nextInt(16).toRadixString(16)).join();
      await prefs.setString(KEY_DEVICE_ID, id);
    }
    return id;
  }

  Future<GuestSessionResult> startSession(String backendUrl) async {
    try {
      final res = await http
          .post(
            Uri.parse('$backendUrl/api/guest/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceFingerprint': await _deviceId()}),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (res.statusCode == 403 && data['expired'] == true) {
        return GuestSessionResult(expired: true, error: data['error']?.toString());
      }
      if (res.statusCode != 200 || data['success'] != true) {
        return GuestSessionResult(error: data['error']?.toString() ?? 'Server error (${res.statusCode})');
      }
      // Use the server's remaining time so a wrong phone clock can't extend access.
      final remaining = (data['remainingSeconds'] as num).toInt();
      return GuestSessionResult(
        sessionId: data['session']['sessionId'] as String,
        token: data['token'] as String,
        expiresAt: DateTime.now().add(Duration(seconds: remaining)),
        termsAccepted: data['session']['termsAccepted'] == true,
      );
    } catch (e) {
      debugPrint('[GUEST] start failed: $e');
      return const GuestSessionResult(error: 'Could not connect to the server. Check your internet and try again.');
    }
  }

  void startCountdown(DateTime expiresAt) {
    _ticker?.cancel();
    _warningTriggered = false;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = expiresAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        onExpired?.call();
      } else {
        onTick?.call(remaining);
        if (remaining <= 300 && !_warningTriggered) {
          _warningTriggered = true;
          onWarning5Min?.call();
        }
      }
    });
  }

  void stop() {
    _ticker?.cancel();
  }
}
