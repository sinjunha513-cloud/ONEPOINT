import 'package:flutter/material.dart';

/// A shared, subtle transition that can be replaced when the new design arrives.
class OnepointPageTransitionsBuilder extends PageTransitionsBuilder {
  const OnepointPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: curved
            .drive(Tween(begin: const Offset(0.035, 0), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
