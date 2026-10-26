import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/echo_widgets.dart';
import 'home_dashboard.dart';
import 'username_screen.dart';

/// Step 1 of email sign-in: type your email, we send a 6-digit code.
class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final TextEditingController _email = TextEditingController();
  bool _busy = false;
  String? _error;

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final appState = Provider.of<AppState>(context, listen: false);
    final r = await appState.requestEmailOtp(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.outcome == OtpOutcome.sent) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OtpVerifyScreen(email: email, cooldownSeconds: r.cooldownSeconds)),
      );
    } else {
      setState(() => _error = r.message ?? 'Could not send the code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                const IconTile(icon: Icons.mail_rounded, colors: [Color(0xFF4C7DFF), Color(0xFF7A5CFF)], size: 54),
                const SizedBox(height: 18),
                const Text('Continue with email',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'We will email you a 6-digit code. Use it to sign in or create your Echo account. No password needed.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.alternate_email, color: AppColors.primaryLight),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    errorText: _error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 22),
                GradientButton(label: 'Send code', trailingIcon: Icons.arrow_forward, busy: _busy, onPressed: _send),
                const SizedBox(height: 14),
                Text(
                  'By continuing you confirm you are 18 or older and agree to the Echo Terms and Privacy Policy.',
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Step 2: enter the 6-digit code from the email.
class OtpVerifyScreen extends StatefulWidget {
  final String email;
  final int cooldownSeconds;
  const OtpVerifyScreen({super.key, required this.email, this.cooldownSeconds = 45});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _wait = widget.cooldownSeconds;
    _startCountdown(widget.cooldownSeconds, first: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds, {bool first = false}) {
    _timer?.cancel();
    if (!first) setState(() => _wait = seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait = _wait - 1);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final appState = Provider.of<AppState>(context, listen: false);
    final r = await appState.verifyEmailOtp(widget.email, code);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (r.outcome) {
      case OtpOutcome.signedIn:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeDashboard()),
          (route) => false,
        );
        return;
      case OtpOutcome.needsUsername:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UsernameScreen(viaEmailOtp: true)),
        );
        return;
      default:
        _code.clear();
        setState(() => _error = r.message ?? 'Wrong code. Please try again.');
    }
  }

  Future<void> _resend() async {
    if (_wait > 0) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final r = await appState.requestEmailOtp(widget.email);
    if (!mounted) return;
    if (r.outcome == OtpOutcome.sent) {
      _startCountdown(r.cooldownSeconds);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code was sent.'), backgroundColor: AppColors.surfaceElevated),
      );
    } else {
      if (r.cooldownSeconds > 0) _startCountdown(r.cooldownSeconds);
      setState(() => _error = r.message ?? 'Could not send the code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                const IconTile(icon: Icons.mark_email_read_rounded, colors: [Color(0xFF16C7A8), Color(0xFF0E8A8F)], size: 54),
                const SizedBox(height: 18),
                const Text('Enter the code',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'We sent a 6-digit code to ${widget.email}. It expires in 10 minutes. Check your spam folder too.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  onChanged: (v) {
                    if (v.length == 6) _verify();
                  },
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 30, letterSpacing: 12, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '------',
                    hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5), letterSpacing: 12),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    errorText: _error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 22),
                GradientButton(label: 'Verify', trailingIcon: Icons.check, busy: _busy, onPressed: _verify),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: _wait > 0 ? null : _resend,
                    child: Text(
                      _wait > 0 ? 'Resend code in ${_wait}s' : 'Resend code',
                      style: TextStyle(color: _wait > 0 ? AppColors.textSecondary : AppColors.primaryLight, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Use a different email', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
