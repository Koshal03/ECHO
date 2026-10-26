import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/echo_widgets.dart';
import 'audio_call_screen.dart';
import 'video_call_screen.dart';
import 'text_chat_screen.dart';

class SearchingScreen extends StatefulWidget {
  const SearchingScreen({super.key});

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _dots;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  void _cancel(AppState appState) {
    appState.cancelSearch();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // The server wants the Terms accepted first: go back (the home page shows the Terms).
    final me = appState.currentUser;
    if (me != null && !me.termsAccepted && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }

    // Auto-navigate to call screen when a stranger is matched
    if (appState.activeCall != null && !_navigated) {
      _navigated = true;
      final matchedMode = appState.activeCall!.mode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => matchedMode == 'video'
                ? const VideoCallScreen()
                : matchedMode == 'text'
                    ? const TextChatScreen()
                    : const AudioCallScreen(),
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => _cancel(appState),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.6)),
                      ),
                      child: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 26),
                    ),
                  ),
                ),
                const Spacer(),

                // Pulsing avatar
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SpinKitRipple(color: AppColors.primary.withOpacity(0.45), size: 280),
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4C7DFF), Color(0xFF7A5CFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.55), blurRadius: 36)],
                      ),
                      child: const Icon(Icons.person_rounded, color: Colors.white70, size: 70),
                    ),
                  ],
                ),

                const SizedBox(height: 36),
                const Text(
                  'Connecting...',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  appState.searchMode == 'video'
                      ? 'Finding a stranger\nfor a video chat...'
                      : appState.searchMode == 'text'
                          ? 'Finding a stranger\nto chat with...'
                          : 'Finding a random stranger\nfor you...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary.withOpacity(0.95), fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 22),
                _buildDots(),

                const Spacer(),

                // Cancel panel
                GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  radius: 24,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _cancel(appState),
                          borderRadius: BorderRadius.circular(34),
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppColors.danger.withOpacity(0.5), blurRadius: 18)],
                            ),
                            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    const colors = [AppColors.pink, AppColors.primary, AppColors.primary];
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < 3; i++)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[i].withOpacity(0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * (_dots.value - i * 0.2)))),
                ),
              ),
          ],
        );
      },
    );
  }
}
