import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/chat_panel.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/report_block_dialog.dart';
import 'call_ended_screen.dart';
import 'searching_screen.dart';

/// Random text-only chat with a stranger (no microphone or camera).
class TextChatScreen extends StatefulWidget {
  const TextChatScreen({super.key});

  @override
  State<TextChatScreen> createState() => _TextChatScreenState();
}

class _TextChatScreenState extends State<TextChatScreen> {
  bool _left = false;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final call = appState.activeCall;

    if (call == null) {
      // Chat ended (either side): go to the summary screen once.
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    const IconTile(icon: Icons.person_rounded, colors: [Color(0xFF4C7DFF), Color(0xFF7A5CFF)], size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            call.strangerName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const Row(
                            children: [
                              CircleAvatar(radius: 3.5, backgroundColor: AppColors.success),
                              SizedBox(width: 5),
                              Text('Text chat', style: TextStyle(color: AppColors.success, fontSize: 12)),
                            ],
                          ),
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
                    IconButton(
                      tooltip: 'Next stranger',
                      icon: const Icon(Icons.skip_next_rounded, color: AppColors.primaryLight, size: 28),
                      onPressed: () => appState.skipToNextStranger(),
                    ),
                    IconButton(
                      tooltip: 'End chat',
                      icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
                      onPressed: () => appState.endCall(),
                    ),
                  ],
                ),
              ),

              // Safety reminder
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'You are chatting with a stranger. Never share personal information. Messages are not saved.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.35),
                ),
              ),

              const Expanded(child: ChatPanel()),
            ],
          ),
        ),
      ),
    );
  }
}
