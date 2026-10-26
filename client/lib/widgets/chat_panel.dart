import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';

/// Message list + input box. Used by the text-chat screen and the chat sheet in video calls.
/// Messages only live in memory while the conversation lasts (the server never stores them).
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(AppState appState) {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    appState.sendChat(text);
    _input.clear();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final messages = appState.chatMessages;
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToEnd();
    }

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    'Say hi to your stranger',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return Align(
                      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          color: m.mine ? AppColors.primary : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(m.mine ? 18 : 4),
                            bottomRight: Radius.circular(m.mine ? 4 : 18),
                          ),
                        ),
                        child: Text(
                          m.text,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.3),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.cardBorder.withOpacity(0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(appState),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Type a message',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _send(appState),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
