import 'package:flutter/material.dart';

/// Original Figma artwork, rasterized at 3x without redrawing its paths.
class OnepointIcon extends StatelessWidget {
  const OnepointIcon(this.name,
      {super.key, required this.width, required this.height, this.color});

  final String name;
  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/design/$name.png',
        width: width,
        height: height,
        color: color,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.high,
      );
}
