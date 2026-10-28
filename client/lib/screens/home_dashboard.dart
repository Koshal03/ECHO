import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/guest_timer_badge.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/echo_brand.dart';
import '../widgets/echo_motion.dart';
import 'searching_screen.dart';
import 'coin_store_screen.dart';
import 'profile_screen.dart';
import 'safety_screen.dart';
import 'username_screen.dart';
import 'entry_screen.dart';
import 'terms_screen.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _currentIndex = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Coins can change on the server (admin gift, purchase on another phone): load the latest.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Provider.of<AppState>(context, listen: false).refreshProfile();
    });
  }

  static bool _videoNoticeAccepted = false; // asked once per app session

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: AppColors.danger));
  }

  Future<bool> _confirmVideoNotice() async {
    if (_videoNoticeAccepted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Video chat with strangers', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'The stranger will see you on camera, and you will see them.\n\n'
          '\u2022  Never share personal information.\n'
          '\u2022  Nudity or inappropriate behaviour leads to a permanent ban.\n'
          '\u2022  You can report or block anyone at any time.\n'
          '\u2022  Echo is strictly for ages 18+. Calls are never recorded.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I agree'),
          ),
        ],
      ),
    );
    if (ok == true) _videoNoticeAccepted = true;
    return ok == true;
  }

  /// mode: 'audio' | 'video' | 'text'
  Future<void> _startCall(AppState appState, {String mode = 'audio'}) async {
    if (mode != 'text') {
      final mic = await Permission.microphone.request();
      if (!mounted) return;
      if (!mic.isGranted) {
        _showMessage('Microphone permission is needed for calls.');
        return;
      }
      if (mode == 'video') {
        final cam = await Permission.camera.request();
        if (!mounted) return;
        if (!cam.isGranted) {
          _showMessage('Camera permission is needed for video calls.');
          return;
        }
        if (!await _confirmVideoNotice()) return;
        if (!mounted) return;
      }
    }
    appState.startRandomCall(mode: mode);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // The server ended our session (account suspended or deleted): back to the welcome screen.
    if (appState.currentUser == null && appState.forcedLogoutNotice != null && !_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const EntryScreen()),
          (route) => false,
        );
      });
    }

    // Terms and Conditions: nobody can use Echo until they have accepted the current version.
    final me = appState.currentUser;
    if (me != null && !me.termsAccepted) return const TermsScreen();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: <Widget>[...previousChildren, if (currentChild != null) currentChild],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_currentIndex),
                    child: _buildCurrentTab(appState),
                  ),
                ),
              ),
              BannerAdWidget(
                enabled: appState.adsBannerEnabled,
                sdkReady: appState.adService.isReady,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  // ---------------- Bottom navigation ----------------
  Widget _buildNavBar() {
    const items = [
      [Icons.home_rounded, 'Home'],
      [Icons.monetization_on_outlined, 'Coins'],
      [Icons.shield_outlined, 'Safety'],
      [Icons.person_outline_rounded, 'Profile'],
    ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    setState(() => _currentIndex = i);
                    if (i == 1 || i == 3) Provider.of<AppState>(context, listen: false).refreshProfile();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: _currentIndex == i ? 26 : 0,
                          height: 3,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        AnimatedScale(
                          scale: _currentIndex == i ? 1.18 : 1.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: Icon(
                            items[i][0] as IconData,
                            size: 24,
                            color: _currentIndex == i ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i][1] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _currentIndex == i ? FontWeight.w700 : FontWeight.w500,
                            color: _currentIndex == i ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab(AppState appState) {
    switch (_currentIndex) {
      case 1:
        return const CoinStoreScreen();
      case 2:
        return const SafetyScreen();
      case 3:
        return const ProfileScreen();
      default:
        return _buildHomeTab(appState);
    }
  }

  // ---------------- Home tab ----------------
  Widget _buildHeader(AppState appState) {
    final user = appState.currentUser;
    final hasNotice = appState.broadcastMessage != null;
    return Row(
      children: [
        CoinPill(
          coins: user?.coins ?? 50,
          onTap: () => setState(() => _currentIndex = 1),
        ),
        const Spacer(),
        if (user != null && user.isGuest)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GuestTimerBadge(
              remainingSeconds: appState.guestRemainingSeconds,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsernameScreen()),
                );
              },
            ),
          ),
        // Bell: shows the latest message from the Echo team (admin broadcast), if there is one.
        InkWell(
          onTap: () => _showNotifications(appState),
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cardBorder.withOpacity(0.6)),
                ),
                child: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary, size: 23),
              ),
              if (hasNotice)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.background, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showNotifications(AppState appState) {
    final msg = appState.broadcastMessage;
    if (msg == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No new notifications.'), backgroundColor: AppColors.surfaceElevated),
        );
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Message from Echo', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(msg, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () {
              appState.clearBroadcast();
              Navigator.pop(dialogContext);
            },
            child: const Text('Dismiss'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildHomeTab(AppState appState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: staggerIn([
          _buildHeader(appState),
          const SizedBox(height: 18),

          // Guest time warning
          if (appState.show5MinWarning && (appState.currentUser?.isGuest ?? false))
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'You have less than 5 minutes of guest access left. Create an account to keep using Echo.',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UsernameScreen()),
                      );
                    },
                    child: const Text('Upgrade', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // Hero banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 14, 20),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Meet New People',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Video Call  \u2022  Audio Call  \u2022  Text Chat',
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 150,
                        child: GradientButton(
                          label: 'Start Now',
                          trailingIcon: Icons.arrow_forward,
                          height: 42,
                          gradient: AppColors.pinkGradient,
                          onPressed: () => _startCall(appState),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const EchoMark(size: 104, animate: true),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Quick actions
          Row(
            children: [
              Expanded(
                child: _quickTile(
                  icon: Icons.videocam_rounded,
                  label: 'Video Call',
                  colors: const [Color(0xFF3A6BFF), Color(0xFF1B3FD0)],
                  onTap: () => _startCall(appState, mode: 'video'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickTile(
                  icon: Icons.call_rounded,
                  label: 'Audio Call',
                  colors: const [Color(0xFF16C7A8), Color(0xFF0E8A8F)],
                  onTap: () => _startCall(appState, mode: 'audio'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickTile(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Text Chat',
                  colors: const [Color(0xFFB44CFF), Color(0xFF7A2BD6)],
                  onTap: () => _startCall(appState, mode: 'text'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Rooms (not built yet)
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            radius: 18,
            onTap: () => showComingSoon(context, 'Rooms'),
            child: Row(
              children: [
                const IconTile(icon: Icons.groups_rounded, colors: [Color(0xFF2F80FF), Color(0xFF1B4FD0)], size: 44),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rooms', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('Group conversations', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Coming Soon',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Safety reminder (Play Store UGC compliance)
          const GlassCard(
            padding: EdgeInsets.all(14),
            radius: 16,
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, color: AppColors.success, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Echo is safe & moderated. Inappropriate behaviour leads to an immediate permanent ban.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _quickTile({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
    bool soon = false,
  }) {
    return PressScale(
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 112,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated.withOpacity(0.8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder.withOpacity(0.5)),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTile(icon: icon, colors: colors, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (soon) const Positioned(top: 5, right: 5, child: SoonPill()),
          ],
        ),
      ),
      ),
    );
  }
}
