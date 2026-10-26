import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class GuestTimerBadge extends StatelessWidget {
  final int remainingSeconds;
  final VoidCallback onTap;

  const GuestTimerBadge({
    super.key,
    required this.remainingSeconds,
    required this.onTap,
  });

  String _formatTime(int totalSeconds) {
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final bool isCritical = remainingSeconds <= 300; // <= 5 minutes

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isCritical ? AppColors.danger.withOpacity(0.15) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCritical ? AppColors.danger : AppColors.primaryLight.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 16,
              color: isCritical ? AppColors.danger : AppColors.primaryLight,
            ),
            const SizedBox(width: 6),
            Text(
              'Guest: ${_formatTime(remainingSeconds)}',
              style: TextStyle(
                color: isCritical ? AppColors.danger : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
