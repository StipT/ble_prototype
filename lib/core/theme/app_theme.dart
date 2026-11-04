import 'package:flutter/material.dart';

/// Minimal Material 3 theme (UI polish is a non-goal).
abstract final class AppTheme {
  static const _seed = Color(0xFFD81B60);

  /// Light theme.
  static ThemeData get light =>
      ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed));

  /// Dark theme.
  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
  );
}
