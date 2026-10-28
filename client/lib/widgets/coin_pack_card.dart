import 'package:flutter/material.dart';
import '../models/coin_pack.dart';
import '../constants/app_colors.dart';
import 'echo_motion.dart';

class CoinPackCard extends StatelessWidget {
  final CoinPack pack;
  final VoidCallback onBuy;

  const CoinPackCard({
    super.key,
    required this.pack,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pack.isPopular ? AppColors.purple : AppColors.cardBorder.withOpacity(0.6),
          width: pack.isPopular ? 1.6 : 1,
        ),
        boxShadow: pack.isPopular
            ? [BoxShadow(color: AppColors.purple.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 4))]
            : [],
      ),
      child: Stack(
        children: [
          PressScale(child: InkWell(
            onTap: onBuy,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.coinGold.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.monetization_on, color: AppColors.coinGold, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.name,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${pack.coins} coins',
                          style: const TextStyle(color: AppColors.coinGold, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pack.priceFormatted,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          )),
          if (pack.isPopular)
            Positioned(
              top: 0,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: const BoxDecoration(
                  gradient: AppColors.pinkGradient,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: const Text(
                  'Most Popular',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
