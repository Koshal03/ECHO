class ChatMessage {
  final String text;
  final bool mine;
  final DateTime time;
  ChatMessage({required this.text, required this.mine, DateTime? time}) : time = time ?? DateTime.now();
}
