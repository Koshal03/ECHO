import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/echo_motion.dart';

/// Safety tab: how Echo keeps people safe and what to do if something feels wrong.
/// (Shown inside the Home screen's bottom navigation, so it has no app bar of its own.)
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: staggerIn([
            const Text('Safety', style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _hero(),
            const SizedBox(height: 22),
            _heading('If something feels wrong'),
            _toolCard(
              icon: Icons.shield_rounded,
              colors: const [Color(0xFFFF3B6B), Color(0xFFD02050)],
              title: 'Report and block',
              body: 'During a call, tap the shield button. It ends the call, blocks that person for good and sends a report to our moderators.',
            ),
            _toolCard(
              icon: Icons.call_end_rounded,
              colors: const [Color(0xFF3A6BFF), Color(0xFF1B3FD0)],
              title: 'Leave any time',
              body: 'You can end a call or skip to the next person whenever you want. You never have to stay.',
            ),
            _toolCard(
              icon: Icons.flag_rounded,
              colors: const [Color(0xFFB44CFF), Color(0xFF7A2BD6)],
              title: 'Report after a call',
              body: 'Missed something? You can still report or block the person from the call summary screen.',
            ),
            const SizedBox(height: 10),
            _heading('Community rules'),
            _ruleCard(Icons.record_voice_over_rounded, 'Be respectful',
                'Treat everyone with kindness. No hate speech, racism, harassment or vulgarity.'),
            _ruleCard(Icons.lock_rounded, 'Protect your identity',
                'Never share your phone number, address, bank details or passwords.'),
            _ruleCard(Icons.person_off_rounded, '18+ only',
                'Echo is an adult conversation app. Minors are not allowed.'),
            const SizedBox(height: 10),
            _heading('Good to know'),
            _noteCard(
              icon: Icons.info_outline_rounded,
              color: AppColors.primaryLight,
              text: 'Echo does not record your calls. But the person you talk to could record their own screen or audio, '
                  'so only share what you are happy for a stranger to keep.',
            ),
            _noteCard(
              icon: Icons.emergency_rounded,
              color: AppColors.warning,
              text: 'If you or someone else is in immediate danger, contact your local emergency number '
                  '(112 in India). Echo cannot send help.',
            ),
          ]),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      );

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16206B), Color(0xFF0B1442)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const _PulsingShield(),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your safety comes first',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text(
                  'Harassment, abuse, explicit content and threats are not allowed. Reports are reviewed by our team, '
                  'and people who break the rules can be banned.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolCard({
    required IconData icon,
    required List<Color> colors,
    required String title,
    required String body,
  }) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, colors: colors, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleCard(IconData icon, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteCard({required IconData icon, required Color color, required String text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// The shield on the hero card gently pulses.
class _PulsingShield extends StatefulWidget {
  const _PulsingShield();

  @override
  State<_PulsingShield> createState() => _PulsingShieldState();
}

class _PulsingShieldState extends State<_PulsingShield> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.success.withOpacity(0.14),
            boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.15 + 0.25 * t), blurRadius: 10 + 14 * t)],
          ),
          child: Transform.scale(
            scale: 1.0 + 0.08 * t,
            child: const Icon(Icons.verified_user_rounded, color: AppColors.success, size: 34),
          ),
        );
      },
    );
  }
}
