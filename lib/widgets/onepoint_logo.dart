import 'package:flutter/material.dart';

/// The supplied SVG wraps a PNG rather than vector paths. Render its unchanged
/// embedded image so it works on Flutter web and mobile without SVG patterns.
class OnepointLogo extends StatelessWidget {
  const OnepointLogo({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/onepoint-logo.png',
        width: 121,
        height: 34,
        // Reproduce the SVG's centered, cropped 121 x 34 viewport.
        fit: BoxFit.cover,
        semanticLabel: 'ONEPOINT',
        filterQuality: FilterQuality.high,
      );
}
