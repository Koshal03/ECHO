class CoinPack {
  final String id;
  final String name;
  final int coins;
  final String priceFormatted;
  final String description;
  final bool isPopular;

  const CoinPack({
    required this.id,
    required this.name,
    required this.coins,
    required this.priceFormatted,
    required this.description,
    this.isPopular = false,
  });

  static const List<CoinPack> packs = [
    CoinPack(
      id: 'coins_starter_49',
      name: 'Starter Pack',
      coins: 50,
      priceFormatted: '₹49',
      description: 'Perfect for quick profile flair and testing features.',
    ),
    CoinPack(
      id: 'coins_popular_149',
      name: 'Popular Pack',
      coins: 200,
      priceFormatted: '₹149',
      description: 'Most popular! Best value for frequent stranger audio chats.',
      isPopular: true,
    ),
    CoinPack(
      id: 'coins_value_299',
      name: 'Value Pack',
      coins: 500,
      priceFormatted: '₹299',
      description: 'Maximum coins for active conversationalists.',
    ),
  ];
}
