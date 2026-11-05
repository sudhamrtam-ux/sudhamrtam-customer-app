import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light {
    const primaryGreen = Color(0xFF82B440);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: primaryGreen),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF263A1A),
        centerTitle: true,
      ),
    );
  }
}
