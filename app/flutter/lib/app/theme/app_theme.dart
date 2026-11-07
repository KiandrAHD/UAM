import 'package:flutter/material.dart';

/// Material 3 theme definitions for the UAM shell.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF2D6CDF);

  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  );

  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  );
}
