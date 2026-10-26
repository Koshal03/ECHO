import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Full-screen navy gradient with two soft glows. Wrap a screen body in this.
class GradientBackground extends StatelessWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.screenGradient),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _glow(AppColors.purple.withOpacity(0.18), 260),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: _glow(AppColors.primary.withOpacity(0.20), 300),
          ),
          child,
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
      ),
    );
  }
}

/// The Echo logo (the same artwork as the app icon, with its own name + tagline).
class EchoLogo extends StatelessWidget {
  final double size;
  const EchoLogo({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/appicon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

/// Big rounded gradient button (e.g. "Get Started").
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final double height;
  final bool busy;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailingIcon,
    this.gradient = AppColors.brandGradient,
    this.height = 56,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        if (trailingIcon != null) ...[
                          const SizedBox(width: 8),
                          Icon(trailingIcon, color: Colors.white, size: 20),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark translucent rounded card used for lists and panels.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.radius = 18,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withOpacity(0.75),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: (borderColor ?? AppColors.cardBorder).withOpacity(0.55)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Rounded icon tile with a gradient fill.
class IconTile extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double size;
  const IconTile({super.key, required this.icon, required this.colors, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

/// Small "Soon" pill for features that are designed but not built yet.
class SoonPill extends StatelessWidget {
  const SoonPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purple.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('SOON', style: TextStyle(color: AppColors.textPrimary, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
    );
  }
}

void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon!'),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Gold coin balance chip: [coin 50 (+)].
class CoinPill extends StatelessWidget {
  final int coins;
  final VoidCallback? onTap;
  const CoinPill({super.key, required this.coins, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, color: AppColors.coinGold, size: 18),
            const SizedBox(width: 5),
            Text('$coins', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 6),
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.add, color: Colors.white, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}
