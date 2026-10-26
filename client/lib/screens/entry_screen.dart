import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import 'home_dashboard.dart';
import 'username_screen.dart';
import 'email_login_screen.dart';
import '../widgets/echo_widgets.dart';
import '../utils/legal_links.dart';
import '../constants/terms_text.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _googleBusy = false;

  @override
  void initState() {
    super.initState();
    // If the server signed us out (account suspended / deleted), explain why.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notice = Provider.of<AppState>(context, listen: false).takeLogoutNotice();
      if (notice != null) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Signed out', style: TextStyle(color: AppColors.textPrimary)),
            content: Text(notice, style: const TextStyle(color: AppColors.textSecondary)),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
          ),
        );
      }
    });
  }

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    if (_googleBusy) return;
    setState(() => _googleBusy = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final result = await appState.signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleBusy = false);

    switch (result.outcome) {
      case GoogleOutcome.cancelled:
        return;
      case GoogleOutcome.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Google sign-in failed.'), backgroundColor: AppColors.danger),
        );
        return;
      case GoogleOutcome.needsUsername:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UsernameScreen(viaGoogle: true, suggestedName: result.suggestedName),
          ),
        );
        return;
      case GoogleOutcome.signedIn:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeDashboard()),
          (route) => false,
        );
        return;
    }
  }

  Future<void> _handleGuestAccess(BuildContext context) async {
    // Request microphone permission gracefully as required by blueprint
    final micStatus = await Permission.microphone.request();
    if (!context.mounted) return;

    if (micStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required to talk to strangers.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final error = await appState.loginAsGuest();
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.danger),
      );
      return;
    }

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeDashboard()),
      );
    }
  }

  Widget _altButton({required IconData icon, required String label, required VoidCallback onTap, bool busy = false}) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface.withOpacity(0.6),
          side: BorderSide(color: AppColors.cardBorder.withOpacity(0.9)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
        ),
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 21),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      const Spacer(),
                      const EchoLogo(size: 260),
                      const SizedBox(height: 20),
                      const Text(
                        'Real People. Real Conversations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Live voice calls. Anytime. Anywhere.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                      const Spacer(),

                      // Guest mode info (60 minutes, server enforced)
                      GlassCard(
                        padding: const EdgeInsets.all(12),
                        radius: 14,
                        child: const Row(
                          children: [
                            Icon(Icons.access_time_filled, color: AppColors.primaryLight, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Guest Mode gives you 60 minutes of instant calling without sign-up.',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Primary: continue as guest
                      GradientButton(
                        label: 'Get Started',
                        trailingIcon: Icons.arrow_forward,
                        onPressed: () => _handleGuestAccess(context),
                      ),
                      const SizedBox(height: 12),

                      // Google / Email sign-in (recoverable account on any device)
                      Row(
                        children: [
                          Expanded(
                            child: _altButton(
                              icon: Icons.account_circle_outlined,
                              label: 'Google',
                              busy: _googleBusy,
                              onTap: () => _handleGoogleSignIn(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _altButton(
                              icon: Icons.mail_outline_rounded,
                              label: 'Email',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Username-only account (no recovery if the phone is lost)
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const UsernameScreen()),
                          );
                        },
                        child: const Text(
                          'Create account without Google',
                          style: TextStyle(color: AppColors.primaryLight, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(
                        'By continuing, you agree to Echo Terms of Service & Privacy Policy.\nStrictly for ages 18+.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 11, height: 1.4),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => openLegalPage(context, TermsText.pageName),
                            child: const Text('Terms of Service', style: TextStyle(fontSize: 12, color: AppColors.primaryLight)),
                          ),
                          TextButton(
                            onPressed: () => openLegalPage(context, 'privacy_policy.html'),
                            child: const Text('Privacy Policy', style: TextStyle(fontSize: 12, color: AppColors.primaryLight)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
