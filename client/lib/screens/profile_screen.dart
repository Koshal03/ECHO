import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/echo_widgets.dart';
import 'username_screen.dart';
import 'coin_store_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;
    final isGuest = user?.isGuest ?? true;
    final minutesLeft = (appState.guestRemainingSeconds / 60).ceil();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        children: [
          // Title row
          Row(
            children: [
              const Text('Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cardBorder.withOpacity(0.6)),
                  ),
                  child: const Icon(Icons.settings_outlined, color: AppColors.textPrimary, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Avatar
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF4C7DFF), Color(0xFF7A5CFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 28)],
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white70, size: 58),
          ),
          const SizedBox(height: 14),
          Text(
            user?.displayName ?? 'Anonymous User',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (!isGuest && (user?.username.isNotEmpty ?? false)) ...[
            const SizedBox(height: 2),
            Text('@${user!.username}', style: const TextStyle(color: AppColors.accent, fontSize: 13.5)),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder.withOpacity(0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isGuest ? Icons.timer_outlined : Icons.verified, color: AppColors.primaryLight, size: 14),
                const SizedBox(width: 6),
                Text(isGuest ? 'Guest' : 'Member', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stats
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                _stat('${user?.coins ?? 0}', 'Coins', AppColors.coinGold, leading: Icons.monetization_on),
                _divider(),
                _stat(isGuest ? 'Guest' : 'Member', 'Account', AppColors.textPrimary),
                _divider(),
                _stat(isGuest ? '${minutesLeft}m' : 'No limit', isGuest ? 'Time left' : 'Calling', AppColors.primaryLight),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Privacy note
          GlassCard(
            child: Row(
              children: [
                const IconTile(icon: Icons.lock_rounded, colors: [Color(0xFF2F80FF), Color(0xFF1B4FD0)], size: 42),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your profile is private', style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                      SizedBox(height: 3),
                      Text(
                        'Strangers only see your display name and avatar.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Guest upgrade
          if (isGuest) ...[
            GlassCard(
              borderColor: AppColors.warning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                      SizedBox(width: 8),
                      Text('Temporary Guest Session', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your guest access expires after 60 minutes. Register to keep your coins and continue talking.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  GradientButton(
                    label: 'Upgrade to Permanent Account',
                    height: 46,
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsernameScreen())),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Menu
          _menuTile(
            icon: Icons.monetization_on_rounded,
            colors: const [Color(0xFFFFC928), Color(0xFFFF9F1C)],
            title: 'My Coins',
            trailing: Text('${user?.coins ?? 0}', style: const TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.w800, fontSize: 14)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoinStoreScreen())),
          ),
          _menuTile(
            icon: Icons.settings_rounded,
            colors: const [Color(0xFF4C7DFF), Color(0xFF7A5CFF)],
            title: 'Settings',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color, {IconData? leading}) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[Icon(leading, color: color, size: 16), const SizedBox(width: 4)],
              Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: AppColors.cardBorder.withOpacity(0.5));

  Widget _menuTile({
    required IconData icon,
    required List<Color> colors,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 16,
      onTap: onTap,
      child: Row(
        children: [
          IconTile(icon: icon, colors: colors, size: 36),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600))),
          if (trailing != null) ...[trailing, const SizedBox(width: 8)],
          const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 22),
        ],
      ),
    );
  }
}
