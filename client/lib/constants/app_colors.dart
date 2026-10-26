import 'package:flutter/material.dart';

/// ECHO design system: deep navy background, blue / purple / pink gradients.
/// (Old names are kept so every existing screen picks up the new look automatically.)
class AppColors {
  // Surfaces
  static const Color background = Color(0xFF050A2B);
  static const Color backgroundTop = Color(0xFF040824);
  static const Color backgroundBottom = Color(0xFF0A1A6E);
  static const Color surface = Color(0xFF0B1442);
  static const Color surfaceElevated = Color(0xFF101B57);
  static const Color cardBorder = Color(0xFF24399A);

  // Brand
  static const Color primary = Color(0xFF2F80FF);
  static const Color primaryLight = Color(0xFF8DB8FF);
  static const Color accent = Color(0xFF22D3EE);
  static const Color secondary = Color(0xFFFF4FD8);
  static const Color pink = Color(0xFFFF3D9A);
  static const Color purple = Color(0xFFB44CFF);

  // Text
  static const Color textPrimary = Color(0xFFF5F7FF);
  static const Color textSecondary = Color(0xFFA3B1E0);

  // Status
  static const Color danger = Color(0xFFFF3B6B);
  static const Color success = Color(0xFF2ED573);
  static const Color warning = Color(0xFFFFA502);
  static const Color coinGold = Color(0xFFFFC928);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF1FA2FF), Color(0xFFB44CFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const LinearGradient pinkGradient = LinearGradient(
    colors: [Color(0xFFFF3D9A), Color(0xFFFF63C8)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF3A5BFF), Color(0xFF6A3DF0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient screenGradient = LinearGradient(
    colors: [backgroundTop, Color(0xFF07123F), backgroundBottom],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
