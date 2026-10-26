import 'package:flutter/material.dart';

/// A virtual gift. Prices come from the server (GET /api/gifts); [defaults] is only
/// shown while that request is loading or when the phone is offline. The server always
/// uses its own price, so editing a price in the app can never change what is charged.
class Gift {
  final String id;
  final String name;
  final int price;
  final String animation; // pop | petals | burst | sparkle
  final bool popular;

  const Gift({
    required this.id,
    required this.name,
    required this.price,
    this.animation = 'pop',
    this.popular = false,
  });

  factory Gift.fromJson(Map<String, dynamic> j) => Gift(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        price: (j['price'] as num).toInt(),
        animation: (j['animation'] ?? 'pop').toString(),
        popular: j['popular'] == true,
      );

  static const List<Gift> defaults = [
    Gift(id: 'heart', name: 'Heart', price: 10, animation: 'pop'),
    Gift(id: 'rose', name: 'Rose', price: 20, animation: 'petals'),
    Gift(id: 'golden_star', name: 'Golden Star', price: 50, animation: 'burst', popular: true),
    Gift(id: 'diamond', name: 'Diamond', price: 100, animation: 'sparkle'),
  ];

  /// Artwork. Swap these for PNG/Lottie assets later without touching the rest of the app.
  String get emoji {
    switch (id) {
      case 'heart':
        return '\u2764\uFE0F';
      case 'rose':
        return '\u{1F339}';
      case 'golden_star':
        return '\u2B50';
      case 'diamond':
        return '\u{1F48E}';
      default:
        return '\u{1F381}';
    }
  }

  /// Glow / accent colour used behind the artwork and on the card border.
  Color get glow {
    switch (id) {
      case 'heart':
        return const Color(0xFFFF3D7F);
      case 'rose':
        return const Color(0xFFE0245E);
      case 'golden_star':
        return const Color(0xFFFFC928);
      case 'diamond':
        return const Color(0xFF2FA8FF);
      default:
        return const Color(0xFFB44CFF);
    }
  }

  /// "Star received" style text for the receiver's banner.
  String get receivedLabel {
    switch (id) {
      case 'golden_star':
        return 'Star received';
      default:
        return '$name received';
    }
  }
}

/// Something that should be animated on screen: a gift we just sent, or one we received.
class GiftEvent {
  final Gift gift;
  final bool received;
  final String fromName;
  const GiftEvent({required this.gift, required this.received, this.fromName = ''});
}

/// One row of the wallet history.
class WalletTx {
  final String id;
  final int delta;
  final String title;
  final String source;
  final DateTime createdAt;

  const WalletTx({
    required this.id,
    required this.delta,
    required this.title,
    required this.source,
    required this.createdAt,
  });

  factory WalletTx.fromJson(Map<String, dynamic> j) => WalletTx(
        id: j['id'].toString(),
        delta: (j['delta'] as num).toInt(),
        title: (j['title'] ?? 'Coins').toString(),
        source: (j['source'] ?? '').toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt()),
      );
}

/// Result of trying to send a gift.
class GiftSendResult {
  final bool ok;
  final String? error;
  final bool notEnoughCoins;
  final int? needed;
  const GiftSendResult.success() : ok = true, error = null, notEnoughCoins = false, needed = null;
  const GiftSendResult.failure(this.error, {this.notEnoughCoins = false, this.needed}) : ok = false;
}
