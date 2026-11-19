import 'package:flutter/material.dart';

/// Reveal the resolved destination after the session/profile check completes.
class SessionEntrance extends StatefulWidget {
  const SessionEntrance({super.key, required this.child});
  final Widget child;
  @override
  State<SessionEntrance> createState() => _SessionEntranceState();
}

class _SessionEntranceState extends State<SessionEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  late final _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _curve,
      child: SlideTransition(
          position: Tween(begin: const Offset(0, .035), end: Offset.zero)
              .animate(_curve),
          child: widget.child));
}
