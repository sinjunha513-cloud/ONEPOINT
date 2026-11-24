import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';

/// Native wordmark using the existing Figma Inter font, with no image dependency.
class OnepointLogo extends StatelessWidget {
  const OnepointLogo({super.key, this.width = 121});
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'onepoint',
        child: ExcludeSemantics(
            child: SizedBox(
          width: width,
          height: width * 34 / 121,
          child: const FittedBox(
              fit: BoxFit.contain,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'one'),
                  TextSpan(
                      text: 'p', style: TextStyle(color: OnepointDesign.blue)),
                  TextSpan(text: 'oint')
                ]),
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.8,
                    height: 1,
                    color: Colors.white),
              )),
        )),
      );
}
