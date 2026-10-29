import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/echo_motion.dart';
import 'entry_screen.dart';
import 'username_screen.dart';
import '../utils/legal_links.dart';
import '../constants/terms_text.dart';
import 'terms_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _logout(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const EntryScreen()),
      (route) => false,
    );
  }

  void _showAccount(BuildContext context) {
    final user = Provider.of<AppState>(context, listen: false).currentUser;
    if (user == null) return;
    if (user.isGuest) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const UsernameScreen()));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Your account', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Display name: ${user.displayName}', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text('Username: @${user.username}', style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Privacy & Rules', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 14),
            Text('\u2022  Calls are never recorded or stored.', style: TextStyle(color: AppColors.textSecondary, height: 1.6)),
            Text('\u2022  Strangers only see your display name and avatar.', style: TextStyle(color: AppColors.textSecondary, height: 1.6)),
            Text('\u2022  Echo is strictly for ages 18+.', style: TextStyle(color: AppColors.textSecondary, height: 1.6)),
            Text('\u2022  You can report or block anyone after a call.', style: TextStyle(color: AppColors.textSecondary, height: 1.6)),
            SizedBox(height: 14),
            _LegalLinks(),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final error = await appState.deleteAccount();
    navigator.pop(); // close the progress dialog
    if (error == null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EntryScreen()),
        (route) => false,
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.danger));
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Account?', style: TextStyle(color: AppColors.danger)),
        content: const Text(
          'This permanently deletes your account, username, email and coins from Echo. Purchase records are kept without your name. This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteAccount(context);
            },
            child: const Text('Confirm Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AppState>(context).currentUser;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: staggerIn([
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  const Text('Settings', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),

              // Who is signed in
              if (user != null)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  onTap: () => _showAccount(context),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
                        child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(user.isGuest ? 'Guest. Tap to create an account' : '@${user.username}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ],
                  ),
                ),

              _section('Account'),
              _tile(
                icon: Icons.person_rounded,
                colors: const [Color(0xFF4C7DFF), Color(0xFF2F4FD8)],
                title: 'Account',
                subtitle: 'Manage your profile',
                onTap: () => _showAccount(context),
              ),
              _tile(
                icon: Icons.lock_rounded,
                colors: const [Color(0xFF16C7A8), Color(0xFF0E8A8F)],
                title: 'Privacy',
                subtitle: 'Control your data',
                onTap: () => _showPrivacy(context),
              ),

              _section('Preferences'),
              _tile(
                icon: Icons.notifications_rounded,
                colors: const [Color(0xFFFF4FD8), Color(0xFFB44CFF)],
                title: 'Notifications',
                subtitle: 'Chat & call alerts',
                soon: true,
                onTap: () => showComingSoon(context, 'Notification settings'),
              ),
              _tile(
                icon: Icons.palette_rounded,
                colors: const [Color(0xFF7A5CFF), Color(0xFF4C7DFF)],
                title: 'Appearance',
                subtitle: 'Dark mode, theme',
                soon: true,
                onTap: () => showComingSoon(context, 'Appearance settings'),
              ),
              _tile(
                icon: Icons.language_rounded,
                colors: const [Color(0xFF2F80FF), Color(0xFF1B4FD0)],
                title: 'Language',
                subtitle: 'English',
                soon: true,
                onTap: () => showComingSoon(context, 'Language settings'),
              ),

              _section('Legal & help'),
              _tile(
                icon: Icons.gavel_rounded,
                colors: const [Color(0xFF7A5CFF), Color(0xFF4C7DFF)],
                title: 'Terms and Conditions',
                subtitle: 'Read the rules of using Echo',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TermsScreen(readOnly: true)),
                ),
              ),
              _tile(
                icon: Icons.privacy_tip_rounded,
                colors: const [Color(0xFF16C7A8), Color(0xFF0E8A8F)],
                title: 'Privacy Policy',
                subtitle: 'How we handle your data',
                onTap: () => openLegalPage(context, 'privacy_policy.html'),
              ),
              _tile(
                icon: Icons.help_rounded,
                colors: const [Color(0xFF4C7DFF), Color(0xFF7A5CFF)],
                title: 'Help & Support',
                subtitle: 'Get help or contact us',
                soon: true,
                onTap: () => showComingSoon(context, 'Help & Support'),
              ),

              _section('Danger zone'),
              _tile(
                icon: Icons.delete_outline_rounded,
                colors: const [Color(0xFFFF3B6B), Color(0xFFD62B57)],
                title: 'Delete Account & Data',
                subtitle: 'Permanently remove all user records',
                danger: true,
                onTap: () => _confirmDelete(context),
              ),
              const SizedBox(height: 18),
              GradientButton(
                label: 'Log Out',
                trailingIcon: Icons.logout_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFFD946EF)]),
                onPressed: () => _logout(context),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
      );

  Widget _tile({
    required IconData icon,
    required List<Color> colors,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool soon = false,
    bool danger = false,
  }) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 16,
      onTap: onTap,
      borderColor: danger ? AppColors.danger : null,
      child: Row(
        children: [
          IconTile(icon: icon, colors: colors, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: danger ? AppColors.danger : AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (soon) ...[const SizedBox(width: 8), const SoonPill()],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 22),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.primaryLight,
      side: BorderSide(color: AppColors.cardBorder.withOpacity(0.9)),
    );
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        OutlinedButton(
          style: style,
          onPressed: () => openLegalPage(context, 'privacy_policy.html'),
          child: const Text('Privacy Policy'),
        ),
        OutlinedButton(
          style: style,
          onPressed: () => openLegalPage(context, TermsText.pageName),
          child: const Text('Terms of Service'),
        ),
      ],
    );
  }
}
