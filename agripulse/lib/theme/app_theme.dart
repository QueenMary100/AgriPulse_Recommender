import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color lightGreen = Color(0xFFE8F5E9);

  static const LinearGradient mainGradient = LinearGradient(
    colors: [Color(0xFFF5F7F4), lightGreen],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
