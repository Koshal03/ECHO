import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// The Echo mark from the design: a glowing gradient ring with a sound wave inside.
/// Drawn in code, so it stays sharp at every size.
class EchoMark extends StatelessWidget {
  final double size;
  const EchoMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _EchoMarkPainter()));
  }
}

class _EchoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final w = size.width;
    final ringW = w * 0.07;
    final ringR = w / 2 - ringW * 1.6;
    final rect = Rect.fromCircle(center: c, radius: ringR);
    final shader = const SweepGradient(
      colors: [Color(0xFF22D3EE), Color(0xFF4C7DFF), Color(0xFFB44CFF), Color(0xFF4C7DFF), Color(0xFF22D3EE)],
      transform: GradientRotation(-math.pi / 2),
    ).createShader(rect);

    // soft glow
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW * 1.8
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ringW * 1.4),
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

    // sound wave
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
      final h = heights[i] * w;
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mark + "ECHO" + "Talk to Strangers", stacked (splash and welcome screens).
class EchoWordmark extends StatelessWidget {
  final double markSize;
  final double titleSize;
  const EchoWordmark({super.key, this.markSize = 120, this.titleSize = 44});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EchoMark(size: markSize),
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

/// Glowing purple / blue waves along the bottom edge (splash screen).
class EchoWaves extends StatelessWidget {
  final double height;
  const EchoWaves({super.key, this.height = 180});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(painter: _WavesPainter()),
    );
  }
}

class _WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const layers = [
      [Color(0xFF3A2BD8), Color(0xFF1B2A9A)],
      [Color(0xFF6A3DF0), Color(0xFF2A39C8)],
      [Color(0xFFB44CFF), Color(0xFF4C3DF0)],
    ];
    for (var layer = 0; layer < layers.length; layer++) {
      final base = size.height * (0.50 + 0.14 * layer);
      final amp = size.height * (0.13 - 0.02 * layer);
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 4) {
        final y = base + math.sin((x / size.width) * 2 * math.pi * (1.1 + 0.35 * layer) + layer * 1.4) * amp;
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
