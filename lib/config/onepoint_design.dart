import 'package:flutter/material.dart';

/// Values read from the supplied Figma SVG exports.
abstract final class OnepointDesign {
  static const background = Color(0xFF070101);
  static const surface = Color(0xFF252525);
  static const lime = Color(0xFFC7F000);
  static const blue = Color(0xFF24A9FF);
  static const muted = Color(0xFF949494);
  static const control = TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: ['Pretendard'],
      fontSize: 14,
      fontWeight: FontWeight.w600);
  static const heading = TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: ['Pretendard'],
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}
