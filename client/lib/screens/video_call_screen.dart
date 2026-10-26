import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/chat_panel.dart';
import '../widgets/report_block_dialog.dart';
import 'call_ended_screen.dart';
import 'searching_screen.dart';

/// Video call: stranger full-screen, your camera as a small preview, chat in a sheet.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  Timer? _timer;
  int _seconds = 0;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _openChat(AppState appState) {
    appState.setChatOpen(true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.6,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.all(10),
                child: Text('Chat', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const Expanded(child: ChatPanel()),
            ],
          ),
        ),
      ),
    ).whenComplete(() => appState.setChatOpen(false));
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final call = appState.activeCall;

    if (call == null) {
      if (!_left) {
        _left = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // After "Skip" the app is already searching for the next stranger: go to the searching screen.
          final Widget next = appState.isSearching ? const SearchingScreen() : const CallEndedScreen();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => next),
          );
        });
      }
      return const Scaffold(backgroundColor: AppColors.background);
    }

    final remote = appState.webrtcService.remoteRenderer;
    final local = appState.webrtcService.localRenderer;
    final showLocal = appState.webrtcService.hasLocalVideo && !call.isCameraOff;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Stranger's video (full screen). Shows a placeholder until the first frame arrives.
          Positioned.fill(
            child: ValueListenableBuilder<RTCVideoValue>(
              valueListenable: remote,
              builder: (context, value, _) {
                if (value.width <= 0) {
                  return Container(
                    color: AppColors.background,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent)),
                          const SizedBox(height: 16),
                          Text('Connecting video with ${call.strangerName}...',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                }
                return RTCVideoView(remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
              },
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(call.strangerName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                          Text(_fmt(_seconds),
                              style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Report or Block',
                      icon: const Icon(Icons.shield_outlined, color: AppColors.danger),
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
              ),
            ),
          ),

          // Your camera preview
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 14,
            child: Container(
              width: 104,
              height: 148,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: showLocal
                  ? RTCVideoView(local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : const Center(child: Icon(Icons.videocam_off_rounded, color: AppColors.textSecondary, size: 30)),
            ),
          ),

          // Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _btn(call.isMuted ? Icons.mic_off : Icons.mic, call.isMuted ? 'Muted' : 'Mute',
                        active: call.isMuted, color: AppColors.warning, onTap: appState.toggleMute),
                    _btn(call.isCameraOff ? Icons.videocam_off : Icons.videocam, 'Camera',
                        active: call.isCameraOff, color: AppColors.warning, onTap: appState.toggleCamera),
                    _btn(Icons.cameraswitch_rounded, 'Flip', onTap: () => appState.switchCamera()),
                    _btn(Icons.chat_bubble_rounded, 'Chat',
                        badge: appState.unreadChat, onTap: () => _openChat(appState)),
                    _btn(Icons.skip_next_rounded, 'Skip', onTap: appState.skipToNextStranger),
                    _btn(Icons.call_end_rounded, 'End',
                        active: true, color: AppColors.danger, onTap: appState.endCall),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    IconData icon,
    String label, {
    required VoidCallback onTap,
    bool active = false,
    Color color = AppColors.primary,
    int badge = 0,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(26),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: active ? color : Colors.white.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 23),
              ),
            ),
            if (badge > 0)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.pink, borderRadius: BorderRadius.circular(9)),
                  child: Text(badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
