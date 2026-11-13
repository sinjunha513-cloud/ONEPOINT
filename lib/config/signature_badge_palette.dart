import 'package:flutter/material.dart';

/// Shared palette for globally registered signature badges.
///
/// The sequence order is intentionally shuffled. The first 30 catalog entries
/// therefore receive different colors while still producing the same result on
/// every client. After all 30 colors are used, the palette starts a new cycle.
const signatureBadgePalette = <Color>[
  Color(0xFFC6FF00),
  Color(0xFF38BDF8),
  Color(0xFFF472B6),
  Color(0xFFA78BFA),
  Color(0xFFF59E0B),
  Color(0xFF34D399),
  Color(0xFFFB7185),
  Color(0xFF22D3EE),
  Color(0xFFE879F9),
  Color(0xFFFACC15),
  Color(0xFF4ADE80),
  Color(0xFF60A5FA),
  Color(0xFFF97316),
  Color(0xFF2DD4BF),
  Color(0xFFC084FC),
  Color(0xFFEAB308),
  Color(0xFF818CF8),
  Color(0xFF14B8A6),
  Color(0xFFEF4444),
  Color(0xFF84CC16),
  Color(0xFF06B6D4),
  Color(0xFFD946EF),
  Color(0xFFF43F5E),
  Color(0xFF0EA5E9),
  Color(0xFFA3E635),
  Color(0xFF8B5CF6),
  Color(0xFF10B981),
  Color(0xFFFBBF24),
  Color(0xFFEC4899),
  Color(0xFF6366F1),
];

const signatureBadgeColorOrder = <int>[
  7,
  19,
  2,
  25,
  11,
  0,
  16,
  28,
  5,
  22,
  13,
  3,
  27,
  9,
  18,
  1,
  24,
  14,
  6,
  29,
  10,
  21,
  4,
  17,
  26,
  8,
  20,
  12,
  23,
  15,
];

int signatureBadgeColorIndexForSequence(int sequence) =>
    signatureBadgeColorOrder[sequence % signatureBadgeColorOrder.length];

Color signatureBadgeColor(int? colorIndex, {String legacyIdentity = ''}) {
  if (colorIndex != null &&
      colorIndex >= 0 &&
      colorIndex < signatureBadgePalette.length) {
    return signatureBadgePalette[colorIndex];
  }
  final hash = legacyIdentity.runes.fold<int>(0, (value, rune) => value + rune);
  return signatureBadgePalette[hash % signatureBadgePalette.length];
}
