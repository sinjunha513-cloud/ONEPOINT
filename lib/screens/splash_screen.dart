import 'package:flutter/material.dart';
import 'dart:async';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../widgets/onepoint_logo.dart';
import '../config/onepoint_design.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.service, this.homeBuilder});

  final AuthService? service;
  final WidgetBuilder? homeBuilder;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showLogo = false;
  Timer? _reveal, _finish;

  @override
  void initState() {
    super.initState();
    _reveal = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _showLogo = true);
    });
    _finish = Timer(const Duration(milliseconds: 1250), _openLogin);
  }

  void _openLogin() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
            pageBuilder: (_, animation, secondaryAnimation) => LoginScreen(
                service: widget.service, homeBuilder: widget.homeBuilder)),
      );
    }
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _finish?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnepointDesign.background,
      body: Center(
        child: AnimatedSlide(
          offset: _showLogo || MediaQuery.of(context).disableAnimations
              ? Offset.zero
              : const Offset(0, 0.12),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity:
                _showLogo || MediaQuery.of(context).disableAnimations ? 1 : 0,
            duration: const Duration(milliseconds: 650),
            child: const OnepointLogo(width: 224),
          ),
        ),
      ),
    );
  }
}
