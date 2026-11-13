import 'dart:convert';

import 'package:flutter/material.dart';

/// Supports both historical uploaded photos (base64) and image URLs.
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({
    super.key,
    required this.image,
    this.placeholder =
        const Icon(Icons.person, color: Colors.white54, size: 40),
  });

  final String image;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    if (image.isEmpty) return placeholder;
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(
        image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    try {
      final bytes = base64Decode(
        image.contains(',') ? image.substring(image.indexOf(',') + 1) : image,
      );
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } on FormatException {
      return placeholder;
    }
  }
}
