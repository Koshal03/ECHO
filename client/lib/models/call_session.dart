class CallSession {
  final String roomId;
  final String strangerId;
  final String strangerName;
  final String strangerAvatar;
  final bool isInitiator;

  /// 'audio', 'video' or 'text'
  final String mode;
  DateTime startedAt;
  bool isConnected;
  bool isMuted;
  bool isSpeakerOn;
  bool isCameraOff;

  CallSession({
    required this.roomId,
    required this.strangerId,
    required this.strangerName,
    required this.strangerAvatar,
    required this.isInitiator,
    required this.startedAt,
    this.mode = 'audio',
    this.isConnected = false,
    this.isMuted = false,
    this.isSpeakerOn = true,
    this.isCameraOff = false,
  });

  bool get isVideo => mode == 'video';
  bool get isText => mode == 'text';

  int get durationSeconds => DateTime.now().difference(startedAt).inSeconds;

  String get formattedDuration {
    final secs = durationSeconds;
    final mins = secs ~/ 60;
    final remainingSecs = secs % 60;
    return '${mins.toString().padLeft(2, '0')}:${remainingSecs.toString().padLeft(2, '0')}';
  }
}
