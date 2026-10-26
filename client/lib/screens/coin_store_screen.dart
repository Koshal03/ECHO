import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../models/coin_pack.dart';
import '../widgets/coin_pack_card.dart';

class CoinStoreScreen extends StatefulWidget {
  const CoinStoreScreen({super.key});

  @override
  State<CoinStoreScreen> createState() => _CoinStoreScreenState();
}

class _CoinStoreScreenState extends State<CoinStoreScreen> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    // Show purchase results (credited / cancelled / pending) from the server flow.
    _sub = Provider.of<AppState>(context, listen: false).messages.listen((msg) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.surfaceElevated),
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Coin Store', style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Balance Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C3A47), Color(0xFF130F40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.coinGold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.coinGold.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.monetization_on, color: AppColors.coinGold, size: 36),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Balance',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${user?.coins ?? 50} Coins',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Rewarded Ad Opportunity (Blueprint Section 7B)
            InkWell(
              onTap: appState.rewardInProgress
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final message = await appState.watchRewardedAdForCoins();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(message),
                          backgroundColor: AppColors.surfaceElevated,
                        ),
                      );
                    },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_circle_fill, color: AppColors.success, size: 26),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Watch Video Ad',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Earn +10 free coins (sign-in required)',
                            style: TextStyle(color: AppColors.success, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: AppColors.textSecondary, size: 14),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Coin Packages',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Secure purchases via Google Play Billing. No subscriptions.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // In-app Coin Packs
            ...CoinPack.packs.map((pack) {
              return CoinPackCard(
                pack: pack,
                onBuy: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  // Coins are added only after the server verifies the Google Play purchase.
                  final error = await appState.startPurchase(pack.id);
                  if (error != null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(error), backgroundColor: AppColors.danger),
                    );
                  }
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
