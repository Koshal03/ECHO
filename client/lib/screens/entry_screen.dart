import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import 'home_dashboard.dart';
import 'username_screen.dart';
import 'email_login_screen.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/echo_brand.dart';
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
      width: double.infinity,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Align(alignment: Alignment.bottomCenter, child: EchoWaves(height: 150)),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const SizedBox(height: 28),
                          const EchoWordmark(markSize: 84, titleSize: 36),
                          const SizedBox(height: 28),
                          const Text(
                            'Welcome!',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Connect with people around the world',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                          const Spacer(),

                          // Guest mode: 60 minutes, enforced by the server
                          GradientButton(
                            label: 'Continue as Guest',
                            subLabel: '60 min free',
                            height: 62,
                            onPressed: () => _handleGuestAccess(context),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: Divider(color: AppColors.cardBorder.withOpacity(0.6))),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('or', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              ),
                              Expanded(child: Divider(color: AppColors.cardBorder.withOpacity(0.6))),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Google / Email sign-in (recoverable account on any device)
                          _altButton(
                            icon: Icons.g_mobiledata_rounded,
                            label: 'Continue with Google',
                            busy: _googleBusy,
                            onTap: () => _handleGoogleSignIn(context),
                          ),
                          const SizedBox(height: 10),
                          _altButton(
                            icon: Icons.mail_outline_rounded,
                            label: 'Continue with Email',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Username-only account (no recovery if the phone is lost)
                          _altButton(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'Create Account (Username)',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const UsernameScreen()),
                            ),
                          ),

                          const SizedBox(height: 16),
                          Text(
                            'By continuing, you agree to our Terms of Service & Privacy Policy.\nStrictly for ages 18+.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 11, height: 1.4),
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
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
