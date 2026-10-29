import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// The Echo mark from the design: a glowing gradient ring with a sound wave inside.
/// Drawn in code, so it stays sharp at every size.
class EchoMark extends StatefulWidget {
  final double size;

  /// When true the sound wave keeps moving and the ring glow gently pulses.
  final bool animate;
  const EchoMark({super.key, this.size = 96, this.animate = false});

  @override
  State<EchoMark> createState() => _EchoMarkState();
}

class _EchoMarkState extends State<EchoMark> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(painter: _EchoMarkPainter(_c)),
    );
  }
}

class _EchoMarkPainter extends CustomPainter {
  final Animation<double>? anim;
  _EchoMarkPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim?.value ?? 0.0;
    final pulse = 1.0 + (anim == null ? 0.0 : 0.25 * math.sin(2 * math.pi * t));
    final c = size.center(Offset.zero);
    final w = size.width;
    final ringW = w * 0.07;
    final ringR = w / 2 - ringW * 1.6;
    final rect = Rect.fromCircle(center: c, radius: ringR);
    final shader = const SweepGradient(
      colors: [Color(0xFF22D3EE), Color(0xFF4C7DFF), Color(0xFFB44CFF), Color(0xFF4C7DFF), Color(0xFF22D3EE)],
      transform: GradientRotation(-math.pi / 2),
    ).createShader(rect);

    // soft glow (pulses when animated)
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW * 1.8
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ringW * 1.4 * pulse),
    );
    // dark centre
    canvas.drawCircle(c, ringR, Paint()..color = const Color(0xFF0A1250));
    // ring
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW,
    );

    // sound wave (the bars bounce when animated)
    const heights = [0.14, 0.28, 0.46, 0.62, 0.46, 0.28, 0.14];
    final barW = w * 0.055;
    final gap = w * 0.092;
    final barShader = const LinearGradient(
      colors: [Color(0xFF22D3EE), Color(0xFFB44CFF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromCenter(center: c, width: w, height: w * 0.64));
    final barPaint = Paint()..shader = barShader;
    for (var i = 0; i < heights.length; i++) {
      final dx = (i - 3) * gap;
      final m = anim == null ? 1.0 : 0.72 + 0.28 * math.sin(2 * math.pi * t + i * 0.9);
      final h = heights[i] * w * m;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c.translate(dx, 0), width: barW, height: h),
          Radius.circular(barW / 2),
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EchoMarkPainter oldDelegate) => oldDelegate.anim != anim;
}

/// Mark + "ECHO" + "Talk to Strangers", stacked (splash and welcome screens).
class EchoWordmark extends StatelessWidget {
  final double markSize;
  final double titleSize;
  final bool animate;
  const EchoWordmark({super.key, this.markSize = 120, this.titleSize = 44, this.animate = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EchoMark(size: markSize, animate: animate),
        SizedBox(height: markSize * 0.12),
        Text(
          'ECHO',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            letterSpacing: titleSize * 0.06,
            height: 1.0,
          ),
        ),
        SizedBox(height: titleSize * 0.18),
        Text(
          'Talk to Strangers',
          style: TextStyle(
            color: AppColors.textPrimary.withOpacity(0.9),
            fontSize: titleSize * 0.34 < 13.0 ? 13.0 : titleSize * 0.34,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Glowing purple / blue waves along the bottom edge. They drift slowly.
class EchoWaves extends StatefulWidget {
  final double height;
  const EchoWaves({super.key, this.height = 180});

  @override
  State<EchoWaves> createState() => _EchoWavesState();
}

class _EchoWavesState extends State<EchoWaves> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: CustomPaint(painter: _WavesPainter(_c)),
    );
  }
}

class _WavesPainter extends CustomPainter {
  final Animation<double> anim;
  _WavesPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    const layers = [
      [Color(0xFF3A2BD8), Color(0xFF1B2A9A)],
      [Color(0xFF6A3DF0), Color(0xFF2A39C8)],
      [Color(0xFFB44CFF), Color(0xFF4C3DF0)],
    ];
    final phase = anim.value * 2 * math.pi;
    for (var layer = 0; layer < layers.length; layer++) {
      final base = size.height * (0.50 + 0.14 * layer);
      final amp = size.height * (0.13 - 0.02 * layer);
      final dir = layer.isEven ? 1.0 : -1.0;
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 4) {
        final y = base + math.sin((x / size.width) * 2 * math.pi * (1.1 + 0.35 * layer) + layer * 1.4 + dir * phase) * amp;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      final rect = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [layers[layer][0].withOpacity(0.55), layers[layer][1].withOpacity(0.15)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavesPainter oldDelegate) => oldDelegate.anim != anim;
}
