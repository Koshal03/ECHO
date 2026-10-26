import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/report_block_dialog.dart';
import 'call_ended_screen.dart';
import 'searching_screen.dart';

class AudioCallScreen extends StatefulWidget {
  const AudioCallScreen({super.key});

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  bool _left = false;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTimer(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final call = appState.activeCall;

    if (call == null) {
      // Call ended: go to the summary (or straight to the searching screen after "Skip").
      if (!_left) {
        _left = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final Widget next = appState.isSearching ? const SearchingScreen() : const CallEndedScreen();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => next),
          );
        });
      }
      return const Scaffold(backgroundColor: AppColors.background);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            children: [
              // Header with Report/Block Action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                        SizedBox(width: 6),
                        Text('CONNECTED', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.shield_outlined, color: AppColors.danger),
                    tooltip: 'Report or Block',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => ReportBlockDialog(
                          strangerId: call.strangerId,
                          strangerName: call.strangerName,
                          onBlock: () => appState.blockUser(call.strangerId),
                          onReport: (cat, desc) => appState.reportUser(
                            strangerId: call.strangerId,
                            category: cat,
                            description: desc,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const Spacer(),

              // Stranger Avatar & Details
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryLight.withOpacity(0.4), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: const Icon(Icons.person, color: AppColors.primaryLight, size: 70),
              ),

              const SizedBox(height: 24),
              Text(
                call.strangerName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Call duration
              Text(
                _formatTimer(_seconds),
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),

              const Spacer(),

              // Call Control Buttons (Blueprint Section 5)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute / Unmute
                  _buildCallButton(
                    icon: call.isMuted ? Icons.mic_off : Icons.mic,
                    label: call.isMuted ? 'Muted' : 'Mute',
                    isActive: call.isMuted,
                    activeColor: AppColors.warning,
                    onTap: () => appState.toggleMute(),
                  ),

                  // Speaker Toggle
                  _buildCallButton(
                    icon: call.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    label: 'Speaker',
                    isActive: call.isSpeakerOn,
                    activeColor: AppColors.accent,
                    onTap: () => appState.toggleSpeaker(),
                  ),

                  // Skip / Next Stranger
                  _buildCallButton(
                    icon: Icons.skip_next,
                    label: 'Skip',
                    isActive: false,
                    activeColor: AppColors.primary,
                    onTap: () => appState.skipToNextStranger(),
                  ),

                  // End Call (Hangup)
                  _buildCallButton(
                    icon: Icons.call_end,
                    label: 'End',
                    isActive: true,
                    activeColor: AppColors.danger,
                    onTap: () => appState.endCall(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive ? activeColor : AppColors.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : AppColors.textPrimary,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
