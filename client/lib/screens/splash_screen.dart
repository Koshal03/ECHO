import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/echo_brand.dart';
import '../widgets/echo_motion.dart';
import 'entry_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.initApp();

    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        fadeRoute(const EntryScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Align(alignment: Alignment.bottomCenter, child: EchoWaves(height: 220)),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 5),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 950),
                    curve: Curves.easeOutBack,
                    builder: (context, v, child) => Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
                    ),
                    child: const EchoWordmark(markSize: 132, titleSize: 48, animate: true),
                  ),
                  const Spacer(flex: 4),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FadeSlideIn(
                    delay: Duration(milliseconds: 600),
                    child: Text(
                      'Real People. Real Conversations.',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
