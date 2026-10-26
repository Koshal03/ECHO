class UserModel {
  final String userId;
  final String username;
  final String displayName;
  final String avatarUrl;
  int coins;
  final bool isGuest;
  final DateTime? guestExpiresAt;
  bool termsAccepted; // has accepted the CURRENT Terms and Conditions (decided by the server)

  UserModel({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    this.coins = 50,
    this.isGuest = false,
    this.guestExpiresAt,
    this.termsAccepted = false,
  });

  bool get isGuestExpired {
    if (!isGuest || guestExpiresAt == null) return false;
    return DateTime.now().isAfter(guestExpiresAt!);
  }

  int get guestRemainingSeconds {
    if (!isGuest || guestExpiresAt == null) return 0;
    final diff = guestExpiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  factory UserModel.guest(String sessionId, DateTime expiresAt, {bool termsAccepted = false}) {
    final randomNum = (1000 + (DateTime.now().microsecond % 9000));
    return UserModel(
      userId: sessionId,
      username: 'Guest_$randomNum',
      displayName: 'Guest #$randomNum',
      avatarUrl: 'https://api.dicebear.com/7.x/bottts/png?seed=$sessionId',
      coins: 30,
      isGuest: true,
      guestExpiresAt: expiresAt,
      termsAccepted: termsAccepted,
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'] ?? '',
      username: json['username'] ?? '',
      displayName: json['displayName'] ?? json['username'] ?? 'User',
      avatarUrl: json['avatarUrl'] ?? '',
      coins: json['coins'] ?? 50,
      isGuest: json['isGuest'] ?? false,
      guestExpiresAt: json['guestExpiresAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['guestExpiresAt']) 
          : null,
      termsAccepted: json['termsAccepted'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'coins': coins,
    'isGuest': isGuest,
    'guestExpiresAt': guestExpiresAt?.millisecondsSinceEpoch,
    'termsAccepted': termsAccepted,
  };
}
